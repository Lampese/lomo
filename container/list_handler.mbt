///|
// List container handler for local edits.
pub struct ListHandler {
  id : @types.ContainerID
} derive(Show)

///|
pub fn ListHandler::new(id : @types.ContainerID) -> ListHandler {
  ListHandler::{ id, }
}

///|
pub fn ListHandler::id(self : ListHandler) -> @types.ContainerID {
  self.id
}
