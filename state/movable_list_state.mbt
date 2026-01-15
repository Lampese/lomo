///|
// Movable list state built on top of list state.
pub struct MovableListState {
  list : ListState
} derive(Show)

///|
pub fn MovableListState::new() -> MovableListState {
  MovableListState::{ list: ListState::new() }
}

///|
pub fn MovableListState::len(self : MovableListState) -> Int {
  self.list.len()
}

///|
pub fn MovableListState::to_value(self : MovableListState) -> @types.LoroValue {
  self.list.to_value()
}

///|
pub fn MovableListState::elems(self : MovableListState) -> Array[Elem] {
  self.list.elems()
}

///|
pub fn MovableListState::append_elem(
  self : MovableListState,
  value : @types.LoroValue,
  id : @types.IdFull,
) -> Unit {
  self.list.append_elem(value, id)
}

///|
pub fn MovableListState::id_at(
  self : MovableListState,
  index : Int,
) -> Result[@types.IdFull, @types.LoroError] {
  self.list.id_at(index)
}

///|
pub fn MovableListState::value_at(
  self : MovableListState,
  index : Int,
) -> Result[@types.LoroValue?, @types.LoroError] {
  self.list.value_at(index)
}

///|
pub fn MovableListState::apply_inner_op(
  self : MovableListState,
  arena : @arena.SharedArena,
  op : @op.InnerListOp,
  base_id : @types.IdFull,
) -> Result[Unit, @types.LoroError] {
  self.list.apply_inner_op(arena, op, base_id)
}
