///|
// Raw operations used before being committed into the OpLog.
pub(all) enum RawOpContent {
  Map(MapSet)
  List(ListOp)
  Tree(TreeOp)
} derive(Show)

///|
pub fn RawOpContent::content_len(self : RawOpContent) -> Int {
  match self {
    Map(_) => 1
    List(list_op) => list_op.content_len()
    Tree(_op) => 1
  }
}

///|
pub struct RawOp {
  id : @types.ID
  lamport : @types.Lamport
  container : @types.ContainerID
  content : RawOpContent
} derive(Show)

///|
pub fn RawOp::new(
  id : @types.ID,
  lamport : @types.Lamport,
  container : @types.ContainerID,
  content : RawOpContent,
) -> RawOp {
  RawOp::{ id, lamport, container, content }
}

///|
pub fn RawOp::id_full(self : RawOp) -> @types.IdFull {
  @types.IdFull::new(self.id.peer, self.id.counter, self.lamport)
}

///|
pub fn RawOp::id(self : RawOp) -> @types.ID {
  self.id
}

///|
pub fn RawOp::lamport(self : RawOp) -> @types.Lamport {
  self.lamport
}

///|
pub fn RawOp::container(self : RawOp) -> @types.ContainerID {
  self.container
}

///|
pub fn RawOp::content(self : RawOp) -> RawOpContent {
  self.content
}
