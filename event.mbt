///|
pub struct ContainerEvent {
  container : @types.ContainerID
  diff : Array[@types.LoroValue]
} derive(Show)

///|
pub fn ContainerEvent::container(self : ContainerEvent) -> @types.ContainerID {
  self.container
}

///|
pub fn ContainerEvent::diff(self : ContainerEvent) -> Array[@types.LoroValue] {
  self.diff
}

///|
pub struct EventBatch {
  events : Array[ContainerEvent]
  is_local : Bool
  peer : @types.PeerID
} derive(Show)

///|
pub fn EventBatch::events(self : EventBatch) -> Array[ContainerEvent] {
  self.events
}

///|
pub fn EventBatch::is_local(self : EventBatch) -> Bool {
  self.is_local
}

///|
pub fn EventBatch::peer(self : EventBatch) -> @types.PeerID {
  self.peer
}

///|
pub type Subscriber = (EventBatch) -> Bool

///|
pub type LocalUpdateCallback = (Bytes) -> Bool

///|
pub type PeerIdUpdateCallback = (@types.PeerID) -> Bool

///|
pub struct Subscription {
  doc : LoroDoc
  id : Int
}

///|
pub fn Subscription::unsubscribe(self : Subscription) -> Unit {
  self.doc.unsubscribe(self.id)
}
