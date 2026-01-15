///|
// Pending changes wait for missing dependencies.
pub enum PendingChange {
  Unknown(Change)
  Known(Change)
} derive(Show)

///|
pub struct PendingChanges {
  changes : Map[@types.PeerID, Map[@types.Counter, Array[PendingChange]]]
}

///|
pub fn PendingChanges::new() -> PendingChanges {
  PendingChanges::{ changes: Map::new() }
}

///|

///|
fn remote_change_apply_state(
  vv : @types.VersionVector,
  change : Change,
) -> ChangeState {
  let peer = change.id.peer
  let span = change.ctr_span()
  let vv_latest_ctr = vv.get(peer)
  if vv_latest_ctr >= span.end {
    return ChangeState::Applied
  }
  if vv_latest_ctr < span.start {
    return ChangeState::AwaitingMissingDependency(change.id.inc(-1))
  }
  for dep in change.deps.iter() {
    let dep_vv_latest_ctr = vv.get(dep.peer)
    if dep_vv_latest_ctr - 1 < dep.counter {
      return ChangeState::AwaitingMissingDependency(dep)
    }
  }
  ChangeState::CanApplyDirectly
}

///|
fn push_pending(
  pending : PendingChanges,
  miss_dep : @types.ID,
  change : PendingChange,
) -> Unit {
  let peer = miss_dep.peer
  let counter = miss_dep.counter
  let per_peer = match pending.changes.get(peer) {
    Some(map) => map
    None => Map::new()
  }
  let bucket = match per_peer.get(counter) {
    Some(existing) => existing
    None => []
  }
  bucket.push(change)
  per_peer[counter] = bucket
  pending.changes[peer] = per_peer
}

///|
pub enum ChangeState {
  Applied
  CanApplyDirectly
  AwaitingMissingDependency(@types.ID)
} derive(Show)

///|
pub fn OpLog::extend_pending_changes_with_unknown_lamport(
  self : OpLog,
  remote_changes : Array[Change],
) -> Result[Unit, @types.LoroError] {
  for change in remote_changes {
    match remote_change_apply_state(self.vv(), change) {
      ChangeState::AwaitingMissingDependency(miss_dep) =>
        push_pending(
          self.pending_changes,
          miss_dep,
          PendingChange::Unknown(change),
        )
      ChangeState::Applied =>
        return Err(@types.LoroError::InternalError("already applied"))
      ChangeState::CanApplyDirectly =>
        return Err(@types.LoroError::InternalError("can apply"))
    }
  }
  Ok(())
}

///|
pub fn OpLog::try_apply_pending(
  self : OpLog,
  new_ids : Array[@types.ID],
) -> Unit {
  let queue = new_ids
  while queue.length() > 0 {
    let id = match queue.pop() {
      Some(value) => value
      None => break
    }
    match self.pending_changes.changes.get(id.peer) {
      Some(tree) => {
        let to_remove : Array[@types.Counter] = []
        for cnt, _ in tree {
          if cnt <= id.counter {
            to_remove.push(cnt)
          }
        }
        let pending_sets : Array[Array[PendingChange]] = []
        for cnt in to_remove {
          match tree.get(cnt) {
            Some(items) => {
              pending_sets.push(items)
              tree.remove(cnt)
            }
            None => ()
          }
        }
        if tree.length() == 0 {
          self.pending_changes.changes.remove(id.peer)
        } else {
          self.pending_changes.changes[id.peer] = tree
        }
        for pending_set in pending_sets {
          for pending_change in pending_set {
            match pending_change {
              PendingChange::Unknown(change) =>
                match remote_change_apply_state(self.dag.vv(), change) {
                  ChangeState::CanApplyDirectly => {
                    queue.push(change.id_last())
                    self.apply_change_from_remote(
                      PendingChange::Unknown(change),
                    )
                  }
                  ChangeState::Applied => ()
                  ChangeState::AwaitingMissingDependency(miss_dep) =>
                    push_pending(
                      self.pending_changes,
                      miss_dep,
                      PendingChange::Unknown(change),
                    )
                }
              PendingChange::Known(change) =>
                match remote_change_apply_state(self.dag.vv(), change) {
                  ChangeState::CanApplyDirectly => {
                    queue.push(change.id_last())
                    self.apply_change_from_remote(PendingChange::Known(change))
                  }
                  ChangeState::Applied => ()
                  ChangeState::AwaitingMissingDependency(miss_dep) =>
                    push_pending(
                      self.pending_changes,
                      miss_dep,
                      PendingChange::Known(change),
                    )
                }
            }
          }
        }
      }
      None => ()
    }
  }
}

///|
pub fn OpLog::apply_change_from_remote(
  self : OpLog,
  pending_change : PendingChange,
) -> Unit {
  let change = match pending_change {
    PendingChange::Unknown(c) => c
    PendingChange::Known(c) => c
  }
  let change = match self.dag.calc_unknown_lamport_change(change) {
    Ok(c) => c
    Err(_) => return
  }
  match self.trim_the_known_part_of_change(change) {
    Some(trimmed) => self.insert_new_change(trimmed, false)
    None => ()
  }
}
