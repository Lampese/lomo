///|
// Operation log and causal graph.
pub struct OpLog {
  dag : AppDag
  changes : Map[@types.ID, Change]
  change_order : Array[@types.ID]
  pending_changes : PendingChanges
}

///|
pub fn OpLog::new() -> OpLog {
  OpLog::{
    dag: AppDag::new(),
    changes: Map::new(),
    change_order: [],
    pending_changes: PendingChanges::new(),
  }
}

///|
pub fn OpLog::dag(self : OpLog) -> AppDag {
  self.dag
}

///|
pub fn OpLog::vv(self : OpLog) -> @types.VersionVector {
  self.dag.vv()
}

///|
pub fn OpLog::frontiers(self : OpLog) -> @types.Frontiers {
  self.dag.frontiers()
}

///|
pub fn OpLog::is_empty(self : OpLog) -> Bool {
  self.dag.is_empty()
}

///|
pub fn OpLog::insert_new_change(
  self : OpLog,
  change : Change,
  _from_local : Bool,
) -> Unit {
  if self.changes.contains(change.id) {
    return
  }
  self.dag.handle_new_change(change)
  self.changes[change.id] = change
  self.change_order.push(change.id)
}

///|
pub fn OpLog::get_change(self : OpLog, id : @types.ID) -> Change? {
  self.changes.get(id)
}

///|
fn OpLog::change_by_id_last(self : OpLog, id : @types.ID) -> Change? {
  for change_id in self.change_order {
    match self.changes.get(change_id) {
      Some(change) => if change.id_last() == id { return Some(change) }
      None => ()
    }
  }
  None
}

///|
pub fn OpLog::frontiers_to_vv(
  self : OpLog,
  frontiers : @types.Frontiers,
) -> Result[@types.VersionVector, @types.LoroError] {
  let vv = @types.VersionVector::new()
  let visited : Map[@types.ID, Bool] = {}
  let stack : Array[@types.ID] = []
  for id in frontiers.iter() {
    stack.push(id)
  }
  while stack.length() > 0 {
    let id = match stack.pop() {
      Some(value) => value
      None => break
    }
    if visited.get(id) is Some(true) {
      continue
    }
    visited[id] = true
    let change = match self.change_by_id_last(id) {
      Some(value) => value
      None => return Err(@types.LoroError::FrontiersNotIncluded(id))
    }
    let change_id = change.id()
    let end = change_id.counter + change.len()
    if end > vv.get(change_id.peer) {
      vv.set(change_id.peer, end)
    }
    for dep in change.deps().iter() {
      stack.push(dep)
    }
  }
  Ok(vv)
}

///|
pub fn OpLog::vv_to_frontiers(
  self : OpLog,
  vv : @types.VersionVector,
) -> @types.Frontiers {
  let candidates : Map[@types.ID, Bool] = {}
  let included : Array[Change] = []
  for change_id in self.change_order {
    match self.changes.get(change_id) {
      Some(change) => {
        let change_id_val = change.id()
        let end = change_id_val.counter + change.len()
        if end <= vv.get(change_id_val.peer) {
          included.push(change)
          candidates[change.id_last()] = true
        }
      }
      None => ()
    }
  }
  for change in included {
    for dep in change.deps().iter() {
      if candidates.get(dep) is Some(true) {
        candidates.remove(dep)
      }
    }
  }
  let ids : Array[@types.ID] = []
  for id, _ in candidates {
    ids.push(id)
  }
  @types.Frontiers::from_array(ids)
}

///|
pub fn OpLog::all_changes(self : OpLog) -> Array[Change] {
  let out : Array[Change] = []
  for id in self.change_order {
    match self.changes.get(id) {
      Some(change) => out.push(change)
      None => ()
    }
  }
  out
}

///|
pub fn OpLog::import_local_change(
  self : OpLog,
  change : Change,
) -> Result[Unit, @types.LoroError] {
  self.insert_new_change(change, true)
  Ok(())
}

///|
// Trim already-known operations based on the current version vector.
pub fn OpLog::trim_the_known_part_of_change(
  self : OpLog,
  change : Change,
) -> Change? {
  let peer = change.id.peer
  let end = self.vv().get(peer)
  if change.id.counter >= end {
    return Some(change)
  }
  let change_end = change.id.counter + change.len()
  if change_end <= end {
    return None
  }
  let offset = end - change.id.counter
  Some(change.slice(offset, change.len()))
}
