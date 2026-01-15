///|
// Tree container handler for local edits.
pub struct TreeHandler {
  id : @types.ContainerID
} derive(Show)

///|
pub fn TreeHandler::new(id : @types.ContainerID) -> TreeHandler {
  TreeHandler::{ id, }
}

///|
pub fn TreeHandler::id(self : TreeHandler) -> @types.ContainerID {
  self.id
}
