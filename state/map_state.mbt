///|
// Map state with last-write-wins semantics.
pub struct MapValue {
  value : @types.LoroValue?
  lamport : @types.Lamport
  peer : @types.PeerID
} derive(Show)

///|
pub fn MapValue::new(
  value : @types.LoroValue?,
  lamport : @types.Lamport,
  peer : @types.PeerID,
) -> MapValue {
  MapValue::{ value, lamport, peer }
}

///|
pub struct MapState {
  entries : Map[String, MapValue]
  child_containers : Map[@types.ContainerID, String]
} derive(Show)

///|
pub fn MapState::new() -> MapState {
  MapState::{ entries: Map::new(), child_containers: Map::new() }
}

///|
pub fn MapState::get(self : MapState, key : String) -> @types.LoroValue? {
  match self.entries.get(key) {
    Some(map_value) => map_value.value
    None => None
  }
}

///|
pub fn MapState::set(
  self : MapState,
  key : String,
  value : @types.LoroValue,
  id : @types.IdFull,
) -> Unit {
  let next = MapValue::{
    value: Some(value),
    lamport: id.lamport,
    peer: id.peer,
  }
  match self.entries.get(key) {
    Some(existing) =>
      if map_value_newer(next, existing) {
        self.update_entry(key, next)
      }
    None => self.update_entry(key, next)
  }
}

///|
pub fn MapState::delete(
  self : MapState,
  key : String,
  id : @types.IdFull,
) -> Unit {
  let next = MapValue::{ value: None, lamport: id.lamport, peer: id.peer }
  match self.entries.get(key) {
    Some(existing) =>
      if map_value_newer(next, existing) {
        self.update_entry(key, next)
      }
    None => self.update_entry(key, next)
  }
}

///|
pub fn MapState::to_value(self : MapState) -> @types.LoroValue {
  let out : Map[String, @types.LoroValue] = {}
  for key, map_value in self.entries {
    match map_value.value {
      Some(v) => out[key] = v
      None => ()
    }
  }
  @types.LoroValue::Map(out)
}

///|
pub fn MapState::entry_items(self : MapState) -> Array[(String, MapValue)] {
  let out : Array[(String, MapValue)] = []
  for key, value in self.entries {
    out.push((key, value))
  }
  out
}

///|
pub fn MapState::insert_entry(
  self : MapState,
  key : String,
  value : MapValue,
) -> Unit {
  self.update_entry(key, value)
}

///|
fn map_value_newer(next : MapValue, existing : MapValue) -> Bool {
  if next.lamport > existing.lamport {
    true
  } else if next.lamport < existing.lamport {
    false
  } else {
    next.peer >= existing.peer
  }
}

///|
pub fn MapState::update_entry(
  self : MapState,
  key : String,
  next : MapValue,
) -> Unit {
  match self.entries.get(key) {
    Some(prev) =>
      match prev.value {
        Some(@types.LoroValue::Container(id)) =>
          self.child_containers.remove(id)
        _ => ()
      }
    None => ()
  }
  match next.value {
    Some(@types.LoroValue::Container(id)) => self.child_containers[id] = key
    _ => ()
  }
  self.entries[key] = next
}
