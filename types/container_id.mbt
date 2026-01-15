///|
// Container type tags used by ops and state.
pub(all) enum ContainerType {
  Map
  List
  Text
  Tree
  RichText
  MovableList
  Unknown(Byte)
} derive(Show, Eq, Hash)

///|
// Container identity. Root containers are keyed by name.
pub(all) enum ContainerID {
  Root(name~ : String, container_type~ : ContainerType)
  Normal(peer~ : PeerID, counter~ : Counter, container_type~ : ContainerType)
} derive(Show, Eq, Hash)

///|
pub fn ContainerID::root(
  name : String,
  container_type : ContainerType,
) -> ContainerID {
  ContainerID::Root(name~, container_type~)
}

///|
pub fn ContainerID::normal(
  peer : PeerID,
  counter : Counter,
  container_type : ContainerType,
) -> ContainerID {
  ContainerID::Normal(peer~, counter~, container_type~)
}

///|
pub fn ContainerID::container_type(self : ContainerID) -> ContainerType {
  match self {
    Root(name=_, container_type~) => container_type
    Normal(peer=_, counter=_, container_type~) => container_type
  }
}

///|
pub fn ContainerID::is_root(self : ContainerID) -> Bool {
  match self {
    Root(name=_, container_type=_) => true
    _ => false
  }
}
