///|
// TreeID identifies nodes in movable tree.
pub(all) struct TreeID {
  peer : PeerID
  counter : Counter
} derive(Show, Eq, Hash)

///|
pub(all) enum TreeParentId {
  Root
  Deleted
  Node(TreeID)
} derive(Show, Eq)

///|
const DELETED_TREE_PEER : UInt64 = 0xffffffffffffffffUL

///|
const DELETED_TREE_COUNTER : Int = 0x7fffffff

///|
pub fn TreeID::new(peer : PeerID, counter : Counter) -> TreeID {
  TreeID::{ peer, counter }
}

///|
pub fn TreeID::delete_root() -> TreeID {
  TreeID::{ peer: DELETED_TREE_PEER, counter: DELETED_TREE_COUNTER }
}

///|
pub fn TreeID::is_deleted_root(self : TreeID) -> Bool {
  self.peer == DELETED_TREE_PEER && self.counter == DELETED_TREE_COUNTER
}

///|
pub fn TreeID::from_id(id : ID) -> TreeID {
  TreeID::new(id.peer, id.counter)
}

///|
pub fn TreeID::id(self : TreeID) -> ID {
  ID::{ peer: self.peer, counter: self.counter }
}

///|
pub fn TreeID::meta_container(self : TreeID) -> ContainerID {
  ContainerID::normal(self.peer, self.counter, ContainerType::Map)
}

///|
pub fn TreeParentId::from_option(parent : TreeID?) -> TreeParentId {
  match parent {
    Some(id) => TreeParentId::Node(id)
    None => TreeParentId::Root
  }
}

///|
pub fn TreeParentId::to_option(self : TreeParentId) -> TreeID? {
  match self {
    TreeParentId::Node(id) => Some(id)
    _ => None
  }
}

///|
pub fn TreeParentId::deleted() -> TreeParentId {
  TreeParentId::Deleted
}
