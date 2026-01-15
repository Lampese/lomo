///|
// Text container handler for local edits.
pub struct TextHandler {
  id : @types.ContainerID
} derive(Show)

///|
pub fn TextHandler::new(id : @types.ContainerID) -> TextHandler {
  TextHandler::{ id, }
}

///|
pub fn TextHandler::id(self : TextHandler) -> @types.ContainerID {
  self.id
}
