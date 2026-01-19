///|
// Movable list elements include position and element IDs.
pub struct MovableElem {
  v : @types.LoroValue
  id : @types.IdFull
  elem_id : @types.IdLp
  last_set_id : @types.IdLp
} derive(Show)

///|
// Movable list state with separate element IDs.
pub struct MovableListState {
  list : Array[MovableElem]
} derive(Show)

///|
pub fn MovableListState::new() -> MovableListState {
  MovableListState::{ list: [] }
}

///|
pub fn MovableListState::len(self : MovableListState) -> Int {
  self.list.length()
}

///|
pub fn MovableListState::to_value(self : MovableListState) -> @types.LoroValue {
  let out : Array[@types.LoroValue] = []
  for elem in self.list {
    out.push(elem.v)
  }
  @types.LoroValue::List(out)
}

///|
pub fn MovableListState::elems(self : MovableListState) -> Array[MovableElem] {
  let out : Array[MovableElem] = []
  for elem in self.list {
    out.push(elem)
  }
  out
}

///|
pub fn MovableListState::append_elem(
  self : MovableListState,
  value : @types.LoroValue,
  id : @types.IdFull,
) -> Unit {
  let elem_id = id.to_id_lp()
  self.append_elem_full(value, id, elem_id, elem_id)
}

///|
pub fn MovableListState::append_elem_full(
  self : MovableListState,
  value : @types.LoroValue,
  id : @types.IdFull,
  elem_id : @types.IdLp,
  last_set_id : @types.IdLp,
) -> Unit {
  self.list.push(MovableElem::{ v: value, id, elem_id, last_set_id })
}

///|
pub fn MovableListState::id_at(
  self : MovableListState,
  index : Int,
) -> Result[@types.IdFull, @types.LoroError] {
  if index < 0 || index >= self.list.length() {
    return Err(@types.LoroError::InternalError("index out of range"))
  }
  Ok(self.list[index].id)
}

///|
pub fn MovableListState::ids_in_range(
  self : MovableListState,
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
pub fn MovableListState::elem_id_at(
  self : MovableListState,
  index : Int,
) -> Result[@types.IdLp, @types.LoroError] {
  if index < 0 || index >= self.list.length() {
    return Err(@types.LoroError::InternalError("index out of range"))
  }
  Ok(self.list[index].elem_id)
}

///|
pub fn MovableListState::value_at(
  self : MovableListState,
  index : Int,
) -> Result[@types.LoroValue?, @types.LoroError] {
  if index < 0 || index >= self.list.length() {
    return Err(@types.LoroError::InternalError("index out of range"))
  }
  Ok(Some(self.list[index].v))
}

///|
fn MovableListState::find_index_by_elem_id(
  self : MovableListState,
  elem_id : @types.IdLp,
) -> Int? {
  for i = 0; i < self.list.length(); i = i + 1 {
    let id = self.list[i].elem_id
    if id.peer == elem_id.peer && id.lamport == elem_id.lamport {
      return Some(i)
    }
  }
  None
}

///|
fn movable_list_id_at(base : @types.IdFull, offset : Int) -> @types.IdFull {
  @types.IdFull::new(
    base.peer,
    base.counter + offset,
    base.lamport + offset.reinterpret_as_uint(),
  )
}

///|
fn MovableListState::insert_batch(
  self : MovableListState,
  index : Int,
  values : Array[@types.LoroValue],
  base_id : @types.IdFull,
) -> Result[Unit, @types.LoroError] {
  if index < 0 || index > self.list.length() {
    return Err(@types.LoroError::InternalError("index out of range"))
  }
  let mut offset = 0
  for v in values {
    let id = movable_list_id_at(base_id, offset)
    let elem_id = id.to_id_lp()
    self.list.insert(index + offset, MovableElem::{
      v,
      id,
      elem_id,
      last_set_id: elem_id,
    })
    offset = offset + 1
  }
  Ok(())
}

///|
fn MovableListState::set_by_elem_id(
  self : MovableListState,
  elem_id : @types.IdLp,
  value : @types.LoroValue,
  last_set_id : @types.IdLp,
) -> Result[Unit, @types.LoroError] {
  match self.find_index_by_elem_id(elem_id) {
    Some(idx) => {
      let existing = self.list[idx]
      self.list[idx] = MovableElem::{
        v: value,
        id: existing.id,
        elem_id: existing.elem_id,
        last_set_id,
      }
      Ok(())
    }
    None => Err(@types.LoroError::InternalError("element not found"))
  }
}

///|
fn MovableListState::move_by_elem_id(
  self : MovableListState,
  elem_id : @types.IdLp,
  to : Int,
) -> Result[Unit, @types.LoroError] {
  let len = self.list.length()
  if to < 0 || to >= len {
    return Err(@types.LoroError::InternalError("index out of range"))
  }
  let idx = match self.find_index_by_elem_id(elem_id) {
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
fn MovableListState::delete_by_id(
  self : MovableListState,
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
pub fn MovableListState::apply_inner_op(
  self : MovableListState,
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
    Move(from=_, elem_id~, to~) => self.move_by_elem_id(elem_id, to)
    Set(elem_id~, value~) =>
      self.set_by_elem_id(elem_id, value, base_id.to_id_lp())
    _ => Err(@types.LoroError::Unsupported("list op not supported"))
  }
}
