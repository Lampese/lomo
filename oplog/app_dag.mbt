///|
// Minimal AppDag to track causal frontiers and version vectors.
pub struct AppDagNode {
  peer : @types.PeerID
  cnt : @types.Counter
  lamport : @types.Lamport
  deps : @types.Frontiers
  len : Int
  has_succ : Bool
} derive(Show)

///|
pub fn AppDagNode::id_start(self : AppDagNode) -> @types.ID {
  @types.ID::new(self.peer, self.cnt)
}

///|
pub fn AppDagNode::id_end(self : AppDagNode) -> @types.ID {
  @types.ID::new(self.peer, self.cnt + self.len)
}

///|
pub fn AppDagNode::id_last(self : AppDagNode) -> @types.ID {
  @types.ID::new(self.peer, self.cnt + self.len - 1)
}

///|
pub fn AppDagNode::ctr_end(self : AppDagNode) -> @types.Counter {
  self.cnt + self.len
}

///|
pub fn AppDagNode::contains_id(self : AppDagNode, id : @types.ID) -> Bool {
  id.peer == self.peer &&
  id.counter >= self.cnt &&
  id.counter < self.cnt + self.len
}

///|
pub fn AppDagNode::lamport_at(
  self : AppDagNode,
  id : @types.ID,
) -> @types.Lamport {
  self.lamport + (id.counter - self.cnt).reinterpret_as_uint()
}

///|
pub fn AppDagNode::slice(self : AppDagNode, from : Int, to : Int) -> AppDagNode {
  let deps = if from > 0 {
    @types.Frontiers::from_id(self.id_start().inc(from - 1))
  } else {
    self.deps
  }
  AppDagNode::{
    peer: self.peer,
    cnt: self.cnt + from,
    lamport: self.lamport + from.reinterpret_as_uint(),
    deps,
    len: to - from,
    has_succ: if to == self.len {
      self.has_succ
    } else {
      true
    },
  }
}

///|
pub struct AppDag {
  nodes : Map[@types.PeerID, Array[AppDagNode]]
  frontiers : @types.Frontiers
  vv : @types.VersionVector
}

///|
pub fn AppDag::new() -> AppDag {
  AppDag::{
    nodes: Map::new(),
    frontiers: @types.Frontiers::new(),
    vv: @types.VersionVector::new(),
  }
}

///|
pub fn AppDag::frontiers(self : AppDag) -> @types.Frontiers {
  self.frontiers
}

///|
pub fn AppDag::vv(self : AppDag) -> @types.VersionVector {
  self.vv
}

///|
pub fn AppDag::is_empty(self : AppDag) -> Bool {
  self.vv.is_empty()
}

///|
pub fn AppDag::contains(self : AppDag, id : @types.ID) -> Bool {
  self.vv.includes_id(id)
}

///|
pub fn AppDag::get_node(self : AppDag, id : @types.ID) -> AppDagNode? {
  match self.nodes.get(id.peer) {
    Some(nodes) => {
      for node in nodes {
        if node.contains_id(id) {
          return Some(node)
        }
      }
      None
    }
    None => None
  }
}

///|
pub fn AppDag::get_lamport(self : AppDag, id : @types.ID) -> @types.Lamport? {
  match self.get_node(id) {
    Some(node) => Some(node.lamport_at(id))
    None => None
  }
}

///|
pub fn AppDag::handle_new_change(self : AppDag, change : Change) -> Unit {
  let len = change.len()
  let peer = change.id.peer
  let nodes = match self.nodes.get(peer) {
    Some(existing) => existing
    None => []
  }
  let mut inserted = false
  if change.deps_on_self() && nodes.length() > 0 {
    let last_idx = nodes.length() - 1
    let last = nodes[last_idx]
    if !last.has_succ &&
      last.ctr_end() == change.id.counter &&
      last.lamport + last.len.reinterpret_as_uint() == change.lamport {
      let merged = AppDagNode::{
        peer: last.peer,
        cnt: last.cnt,
        lamport: last.lamport,
        deps: last.deps,
        len: last.len + len,
        has_succ: last.has_succ,
      }
      nodes[last_idx] = merged
      inserted = true
    }
  }
  if !inserted {
    let node = AppDagNode::{
      peer,
      cnt: change.id.counter,
      lamport: change.lamport,
      deps: change.deps,
      len,
      has_succ: false,
    }
    nodes.push(node)
  }
  self.nodes[peer] = nodes
  self.handle_deps_break_points(change.deps, peer)
  let new_end = change.id.counter + len
  let current_end = self.vv.get(peer)
  if new_end > current_end {
    self.vv.set(peer, new_end)
  }
  self.frontiers.update_on_new_change(change.id_last(), change.deps)
}

///|
// Calculate lamport for a change based on deps.
pub fn AppDag::calc_unknown_lamport_change(
  self : AppDag,
  change : Change,
) -> Result[Change, @types.LoroError] {
  let mut lamport = change.lamport
  for dep in change.deps.iter() {
    match self.get_lamport(dep) {
      Some(l) => {
        let candidate = l + 1
        if candidate > lamport {
          lamport = candidate
        }
      }
      None => return Err(@types.LoroError::MissingDependency("missing dep"))
    }
  }
  Ok(Change::{
    id: change.id,
    lamport,
    deps: change.deps,
    timestamp: change.timestamp,
    commit_msg: change.commit_msg,
    origin: change.origin,
    ops: change.ops,
  })
}

///|
fn find_node_index(nodes : Array[AppDagNode], id : @types.ID) -> Int? {
  for i = 0; i < nodes.length(); i = i + 1 {
    if nodes[i].contains_id(id) {
      return Some(i)
    }
  }
  None
}

///|
pub fn AppDag::handle_deps_break_points(
  self : AppDag,
  deps : @types.Frontiers,
  skip_peer : @types.PeerID,
) -> Unit {
  for dep in deps.iter() {
    if dep.peer == skip_peer {
      continue
    }
    match self.nodes.get(dep.peer) {
      Some(nodes) =>
        match find_node_index(nodes, dep) {
          Some(idx) => {
            let node = nodes[idx]
            if node.id_last() == dep {
              let updated = AppDagNode::{
                peer: node.peer,
                cnt: node.cnt,
                lamport: node.lamport,
                deps: node.deps,
                len: node.len,
                has_succ: true,
              }
              nodes[idx] = updated
            } else {
              let offset = dep.counter - node.cnt + 1
              let new_node = node.slice(offset, node.len)
              let left = AppDagNode::{
                peer: node.peer,
                cnt: node.cnt,
                lamport: node.lamport,
                deps: node.deps,
                len: offset,
                has_succ: true,
              }
              nodes[idx] = left
              nodes.insert(idx + 1, new_node)
            }
            self.nodes[dep.peer] = nodes
          }
          None => ()
        }
      None => ()
    }
  }
}
