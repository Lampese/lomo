///|
// Movable list container handler for local edits.
pub struct MovableListHandler {
  id : @types.ContainerID
} derive(Show)

///|
pub fn MovableListHandler::new(id : @types.ContainerID) -> MovableListHandler {
  MovableListHandler::{ id, }
}

///|
pub fn MovableListHandler::id(self : MovableListHandler) -> @types.ContainerID {
  self.id
}
