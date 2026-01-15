///|
// Shared arena for list values.
pub struct SharedArena {
  values : Array[@types.LoroValue]
}

///|
pub fn SharedArena::new() -> SharedArena {
  SharedArena::{ values: [] }
}

///|
pub fn SharedArena::alloc_values(
  self : SharedArena,
  values : Array[@types.LoroValue],
) -> @op.SliceRange {
  let start = self.values.length().reinterpret_as_uint()
  for v in values {
    self.values.push(v)
  }
  let end = self.values.length().reinterpret_as_uint()
  @op.SliceRange::new(start, end)
}

///|
pub fn SharedArena::get_values(
  self : SharedArena,
  range : @op.SliceRange,
) -> Array[@types.LoroValue] {
  if range.is_unknown() {
    []
  } else {
    let out : Array[@types.LoroValue] = []
    let start = range.start().reinterpret_as_int()
    let end = range.end().reinterpret_as_int()
    for i = start; i < end; i = i + 1 {
      out.push(self.values[i])
    }
    out
  }
}

///|
// Convert a RawOp into a persisted Op using arena storage for list inserts.
pub fn SharedArena::to_persisted_op(
  self : SharedArena,
  op : @op.RawOp,
) -> @op.Op {
  let content = match op.content() {
    @op.RawOpContent::Map(map_set) => @op.InnerContent::Map(map_set)
    @op.RawOpContent::List(list_op) =>
      @op.InnerContent::List(raw_list_to_inner(self, list_op))
    @op.RawOpContent::Tree(tree_op) => @op.InnerContent::Tree(tree_op)
  }
  let id = op.id()
  @op.Op::new(id.counter, op.container(), content)
}

///|
fn raw_list_to_inner(
  arena : SharedArena,
  list_op : @op.ListOp,
) -> @op.InnerListOp {
  match list_op {
    @op.ListOp::Insert(slice~, pos~) =>
      match slice {
        @op.ListSlice::RawData(values) => {
          let range = arena.alloc_values(values)
          @op.InnerListOp::Insert(slice=range, pos~)
        }
        @op.ListSlice::RawStr(str~, unicode_len=len) =>
          @op.InnerListOp::InsertText(
            str~,
            unicode_start=0,
            unicode_len=len,
            pos~,
          )
      }
    @op.ListOp::Delete(span) => @op.InnerListOp::Delete(span)
    @op.ListOp::Move(from~, to~, elem_id~) =>
      @op.InnerListOp::Move(from~, elem_id~, to~)
    @op.ListOp::Set(elem_id~, value~) => @op.InnerListOp::Set(elem_id~, value~)
    @op.ListOp::StyleStart(start~, end~, key~, info~, value~) =>
      @op.InnerListOp::StyleStart(start~, end~, key~, info~, value~)
    @op.ListOp::StyleEnd => @op.InnerListOp::StyleEnd
  }
}
