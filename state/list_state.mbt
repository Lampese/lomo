///|
// List state for list containers.
pub struct Elem {
  v : @types.LoroValue
  id : @types.IdFull
} derive(Show)

///|
pub struct ListState {
  list : Array[Elem]
} derive(Show)

///|
pub fn ListState::new() -> ListState {
  ListState::{ list: [] }
}

///|
pub fn ListState::len(self : ListState) -> Int {
  self.list.length()
}

///|
pub fn ListState::to_values(self : ListState) -> Array[@types.LoroValue] {
  let out : Array[@types.LoroValue] = []
  for elem in self.list {
    out.push(elem.v)
  }
  out
}

///|
pub fn ListState::to_value(self : ListState) -> @types.LoroValue {
  @types.LoroValue::List(self.to_values())
}

///|
pub fn ListState::elems(self : ListState) -> Array[Elem] {
  let out : Array[Elem] = []
  for elem in self.list {
    out.push(elem)
  }
  out
}

///|
pub fn ListState::append_elem(
  self : ListState,
  value : @types.LoroValue,
  id : @types.IdFull,
) -> Unit {
  self.list.push(Elem::{ v: value, id })
}

///|
pub fn ListState::value_at(
  self : ListState,
  index : Int,
) -> Result[@types.LoroValue?, @types.LoroError] {
  if index < 0 || index >= self.list.length() {
    return Err(@types.LoroError::InternalError("index out of range"))
  }
  Ok(Some(self.list[index].v))
}

///|
pub fn ListState::id_at(
  self : ListState,
  index : Int,
) -> Result[@types.IdFull, @types.LoroError] {
  if index < 0 || index >= self.list.length() {
    return Err(@types.LoroError::InternalError("index out of range"))
  }
  Ok(self.list[index].id)
}

///|
pub fn ListState::ids_in_range(
  self : ListState,
  start : Int,
  end : Int,
) -> Result[Array[@types.IdFull], @types.LoroError] {
  if start < 0 || end < start || end > self.list.length() {
    return Err(@types.LoroError::InternalError("index out of range"))
  }
  let out : Array[@types.IdFull] = []
  for i = start; i < end; i = i + 1 {
    out.push(self.list[i].id)
  }
  Ok(out)
}

///|
fn ListState::find_index_by_id(self : ListState, elem_id : @types.IdLp) -> Int? {
  for i = 0; i < self.list.length(); i = i + 1 {
    let id = self.list[i].id
    if id.peer == elem_id.peer && id.lamport == elem_id.lamport {
      return Some(i)
    }
  }
  None
}

///|
fn list_elem_id_at(base : @types.IdFull, offset : Int) -> @types.IdFull {
  @types.IdFull::new(
    base.peer,
    base.counter + offset,
    base.lamport + offset.reinterpret_as_uint(),
  )
}

///|
pub fn ListState::insert(
  self : ListState,
  index : Int,
  value : @types.LoroValue,
  id : @types.IdFull,
) -> Result[Unit, @types.LoroError] {
  if index < 0 || index > self.list.length() {
    return Err(@types.LoroError::InternalError("index out of range"))
  }
  self.list.insert(index, Elem::{ v: value, id })
  Ok(())
}

///|
pub fn ListState::insert_batch(
  self : ListState,
  index : Int,
  values : Array[@types.LoroValue],
  base_id : @types.IdFull,
) -> Result[Unit, @types.LoroError] {
  if index < 0 || index > self.list.length() {
    return Err(@types.LoroError::InternalError("index out of range"))
  }
  let mut offset = 0
  for v in values {
    let id = list_elem_id_at(base_id, offset)
    self.list.insert(index + offset, Elem::{ v, id })
    offset = offset + 1
  }
  Ok(())
}

///|
pub fn ListState::set_by_id(
  self : ListState,
  elem_id : @types.IdLp,
  value : @types.LoroValue,
) -> Result[Unit, @types.LoroError] {
  match self.find_index_by_id(elem_id) {
    Some(idx) => {
      let existing = self.list[idx]
      self.list[idx] = Elem::{ v: value, id: existing.id }
      Ok(())
    }
    None => Err(@types.LoroError::InternalError("element not found"))
  }
}

///|
pub fn ListState::move_by_id(
  self : ListState,
  elem_id : @types.IdLp,
  to : Int,
) -> Result[Unit, @types.LoroError] {
  let len = self.list.length()
  if to < 0 || to >= len {
    return Err(@types.LoroError::InternalError("index out of range"))
  }
  let idx = match self.find_index_by_id(elem_id) {
    Some(value) => value
    None => return Err(@types.LoroError::InternalError("element not found"))
  }
  if idx == to {
    return Ok(())
  }
  let elem = self.list.remove(idx)
  self.list.insert(to, elem)
  Ok(())
}

///|
pub fn ListState::delete_range(
  self : ListState,
  start : Int,
  end : Int,
) -> Result[Unit, @types.LoroError] {
  if start < 0 || end < start || end > self.list.length() {
    return Err(@types.LoroError::InternalError("invalid delete range"))
  }
  let mut idx = start
  while idx < end {
    ignore(self.list.remove(start))
    idx = idx + 1
  }
  Ok(())
}

///|
pub fn ListState::delete_by_id(
  self : ListState,
  span : @op.DeleteSpanWithId,
) -> Result[Unit, @types.LoroError] {
  let id_start = span.id_start()
  let len = span.content_len()
  if len <= 0 {
    return Ok(())
  }
  let start_ctr = id_start.counter
  let end_ctr = start_ctr + len
  let peer = id_start.peer
  let mut i = 0
  while i < self.list.length() {
    let elem = self.list[i]
    if elem.id.peer == peer &&
      elem.id.counter >= start_ctr &&
      elem.id.counter < end_ctr {
      ignore(self.list.remove(i))
    } else {
      i = i + 1
    }
  }
  Ok(())
}

///|
pub fn ListState::apply_inner_op(
  self : ListState,
  arena : @arena.SharedArena,
  op : @op.InnerListOp,
  base_id : @types.IdFull,
) -> Result[Unit, @types.LoroError] {
  match op {
    Insert(slice~, pos~) => {
      let values = arena.get_values(slice)
      self.insert_batch(pos, values, base_id)
    }
    Delete(span) => self.delete_by_id(span)
    Move(from=_, elem_id~, to~) => self.move_by_id(elem_id, to)
    Set(elem_id~, value~) => self.set_by_id(elem_id, value)
    _ => Err(@types.LoroError::Unsupported("list op not supported"))
  }
}
