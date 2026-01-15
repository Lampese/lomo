///|
// Version vector tracking per-peer counters.
pub struct VersionVector {
  entries : Map[PeerID, Counter]
}

///|
pub fn VersionVector::new() -> VersionVector {
  VersionVector::{ entries: Map::new() }
}

///|
pub fn VersionVector::get(self : VersionVector, peer : PeerID) -> Counter {
  match self.entries.get(peer) {
    Some(v) => v
    None => 0
  }
}

///|
pub fn VersionVector::set(
  self : VersionVector,
  peer : PeerID,
  counter : Counter,
) -> Unit {
  self.entries[peer] = counter
}

///|
pub fn VersionVector::merge(
  self : VersionVector,
  other : VersionVector,
) -> Unit {
  for peer, counter in other.entries {
    let current = self.get(peer)
    if counter > current {
      self.entries[peer] = counter
    }
  }
}

///|
pub fn VersionVector::includes_id(self : VersionVector, id : ID) -> Bool {
  self.get(id.peer) > id.counter
}

///|
pub fn VersionVector::extend_to_include_last_id(
  self : VersionVector,
  id : ID,
) -> Unit {
  let next = id.counter + 1
  if next > self.get(id.peer) {
    self.entries[id.peer] = next
  }
}

///|
pub fn VersionVector::is_empty(self : VersionVector) -> Bool {
  self.entries.length() == 0
}

///|
pub fn VersionVector::to_map(self : VersionVector) -> Map[PeerID, Counter] {
  self.entries
}

///|
// A minimal frontiers set (current heads of the DAG).
pub struct Frontiers {
  mut ids : Array[ID]
} derive(Show)

///|
pub fn Frontiers::new() -> Frontiers {
  Frontiers::{ ids: [] }
}

///|
pub fn Frontiers::clone(self : Frontiers) -> Frontiers {
  let ids : Array[ID] = []
  for id in self.ids {
    ids.push(id)
  }
  Frontiers::{ ids, }
}

///|
pub fn Frontiers::from_array(ids : Array[ID]) -> Frontiers {
  Frontiers::{ ids, }
}

///|
pub fn Frontiers::from_id(id : ID) -> Frontiers {
  Frontiers::{ ids: [id] }
}

///|
pub fn Frontiers::as_view(self : Frontiers) -> ArrayView[ID] {
  self.ids[:]
}

///|
pub fn Frontiers::push(self : Frontiers, id : ID) -> Unit {
  let mut replaced = false
  for i = 0; i < self.ids.length(); i = i + 1 {
    if self.ids[i].peer == id.peer {
      if self.ids[i].counter < id.counter {
        self.ids[i] = id
      }
      replaced = true
      break
    }
  }
  if !replaced {
    self.ids.push(id)
  }
}

///|
pub fn Frontiers::len(self : Frontiers) -> Int {
  self.ids.length()
}

///|
pub fn Frontiers::is_empty(self : Frontiers) -> Bool {
  self.ids.length() == 0
}

///|
pub fn Frontiers::as_single(self : Frontiers) -> ID? {
  if self.ids.length() == 1 {
    Some(self.ids[0])
  } else {
    None
  }
}

///|
pub fn Frontiers::iter(self : Frontiers) -> ArrayView[ID] {
  self.ids[:]
}

///|
pub fn Frontiers::contains(self : Frontiers, id : ID) -> Bool {
  for item in self.ids {
    if item == id {
      return true
    }
  }
  false
}

///|
pub fn Frontiers::remove(self : Frontiers, id : ID) -> Unit {
  let next : Array[ID] = []
  for item in self.ids {
    if item != id {
      next.push(item)
    }
  }
  self.ids = next
}

///|
pub fn Frontiers::update_on_new_change(
  self : Frontiers,
  id_last : ID,
  deps : Frontiers,
) -> Unit {
  let next : Array[ID] = []
  for item in self.ids {
    if !deps.contains(item) {
      next.push(item)
    }
  }
  self.ids = next
  self.push(id_last)
}
