///|
// Tree state for movable tree containers.
pub struct TreeNode {
  id : @types.TreeID
  parent : @types.TreeParentId
  position : @types.FractionalIndex
  last_id : @types.IdLp
} derive(Show)

///|
pub fn TreeNode::new(
  id : @types.TreeID,
  parent : @types.TreeParentId,
  position : @types.FractionalIndex,
  last_id : @types.IdLp,
) -> TreeNode {
  TreeNode::{ id, parent, position, last_id }
}

///|
pub fn TreeNode::parent(self : TreeNode) -> @types.TreeParentId {
  self.parent
}

///|
pub fn TreeNode::position(self : TreeNode) -> @types.FractionalIndex {
  self.position
}

///|
pub struct TreeState {
  nodes : Map[@types.TreeID, TreeNode]
} derive(Show)

///|
pub fn TreeState::new() -> TreeState {
  TreeState::{ nodes: Map::new() }
}

///|
pub fn TreeState::nodes(self : TreeState) -> Array[TreeNode] {
  let out : Array[TreeNode] = []
  for _, node in self.nodes {
    out.push(node)
  }
  out
}

///|
pub fn TreeState::set_node(self : TreeState, node : TreeNode) -> Unit {
  self.nodes[node.id] = node
}

///|
fn idlp_newer(a : @types.IdLp, b : @types.IdLp) -> Bool {
  if a.lamport > b.lamport {
    true
  } else if a.lamport < b.lamport {
    false
  } else {
    a.peer >= b.peer
  }
}

///|
fn TreeState::parent_exists(
  self : TreeState,
  parent : @types.TreeParentId,
) -> Bool {
  match parent {
    @types.TreeParentId::Root => true
    @types.TreeParentId::Deleted => false
    @types.TreeParentId::Node(pid) =>
      match self.nodes.get(pid) {
        Some(node) =>
          match node.parent {
            @types.TreeParentId::Deleted => false
            _ => true
          }
        None => false
      }
  }
}

///|
pub fn TreeState::get_node(self : TreeState, id : @types.TreeID) -> TreeNode? {
  self.nodes.get(id)
}

///|
pub fn TreeState::apply_op(
  self : TreeState,
  op : @op.TreeOp,
  base_id : @types.IdFull,
) -> Result[Unit, @types.LoroError] {
  let next_id = base_id.to_id_lp()
  match op {
    @op.TreeOp::Create(target~, parent~, position~) => {
      if !self.parent_exists(parent) {
        match parent {
          @types.TreeParentId::Node(pid) =>
            return Err(@types.LoroError::TreeParentNotFound(pid))
          _ => return Err(@types.LoroError::InternalError("invalid parent"))
        }
      }
      match self.nodes.get(target) {
        Some(existing) =>
          if idlp_newer(next_id, existing.last_id) {
            self.nodes[target] = TreeNode::{
              id: target,
              parent,
              position,
              last_id: next_id,
            }
          }
        None =>
          self.nodes[target] = TreeNode::{
            id: target,
            parent,
            position,
            last_id: next_id,
          }
      }
      Ok(())
    }
    @op.TreeOp::Move(target~, parent~, position~) => {
      if !self.parent_exists(parent) {
        match parent {
          @types.TreeParentId::Node(pid) =>
            return Err(@types.LoroError::TreeParentNotFound(pid))
          _ => return Err(@types.LoroError::InternalError("invalid parent"))
        }
      }
      match self.nodes.get(target) {
        Some(existing) => {
          if idlp_newer(next_id, existing.last_id) {
            self.nodes[target] = TreeNode::{
              id: target,
              parent,
              position,
              last_id: next_id,
            }
          }
          Ok(())
        }
        None => Err(@types.LoroError::TreeNodeNotFound(target))
      }
    }
    @op.TreeOp::Delete(target~) =>
      match self.nodes.get(target) {
        Some(existing) => {
          if idlp_newer(next_id, existing.last_id) {
            let deleted = TreeNode::{
              id: target,
              parent: @types.TreeParentId::Deleted,
              position: existing.position,
              last_id: next_id,
            }
            self.nodes[target] = deleted
          }
          Ok(())
        }
        None => Err(@types.LoroError::TreeNodeNotFound(target))
      }
  }
}

///|
fn TreeState::children_nodes(
  self : TreeState,
  parent : @types.TreeParentId,
) -> Array[TreeNode]? {
  if !self.parent_exists(parent) {
    return None
  }
  let out : Array[TreeNode] = []
  for _, node in self.nodes {
    if node.parent == parent {
      out.push(node)
    }
  }
  // Simple in-place sort by fractional index.
  for i = 0; i < out.length(); i = i + 1 {
    for j = i + 1; j < out.length(); j = j + 1 {
      if out[j].position.compare(out[i].position) < 0 {
        let tmp = out[i]
        out[i] = out[j]
        out[j] = tmp
      }
    }
  }
  Some(out)
}

///|
pub fn TreeState::children(
  self : TreeState,
  parent : @types.TreeParentId,
) -> Array[@types.TreeID]? {
  match self.children_nodes(parent) {
    Some(nodes) => {
      let out : Array[@types.TreeID] = []
      for node in nodes {
        out.push(node.id)
      }
      Some(out)
    }
    None => None
  }
}

///|
pub fn TreeState::roots(self : TreeState) -> Array[@types.TreeID] {
  match self.children(@types.TreeParentId::Root) {
    Some(ids) => ids
    None => []
  }
}
