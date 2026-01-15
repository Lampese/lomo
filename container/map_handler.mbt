///|
// Map container handler for local edits.
pub struct MapHandler {
  id : @types.ContainerID
} derive(Show)

///|
pub fn MapHandler::new(id : @types.ContainerID) -> MapHandler {
  MapHandler::{ id, }
}

///|
pub fn MapHandler::id(self : MapHandler) -> @types.ContainerID {
  self.id
}
