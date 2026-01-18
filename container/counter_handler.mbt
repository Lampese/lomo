///|
// Counter container handler for local edits.
pub struct CounterHandler {
  id : @types.ContainerID
} derive(Show)

///|
pub fn CounterHandler::new(id : @types.ContainerID) -> CounterHandler {
  CounterHandler::{ id, }
}

///|
pub fn CounterHandler::id(self : CounterHandler) -> @types.ContainerID {
  self.id
}
