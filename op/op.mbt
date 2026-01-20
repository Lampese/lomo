///|
// Operations are the atomic units stored in the OpLog.
pub(all) enum InnerContent {
  List(InnerListOp)
  Map(MapSet)
  Tree(TreeOp)
  Counter(CounterOp)
  RichText
  MovableList
  Unknown
} derive(Show)

///|
pub struct Op {
  counter : @types.Counter
  container : @types.ContainerID
  content : InnerContent
} derive(Show)

///|
pub fn Op::new(
  counter : @types.Counter,
  container : @types.ContainerID,
  content : InnerContent,
) -> Op {
  Op::{ counter, container, content }
}

///|
// Placeholder: list/text ops will define real lengths later.
pub fn Op::content_len(self : Op) -> Int {
  self.content.content_len()
}

///|
// Placeholder slice: content slicing will be implemented with real op content.
pub fn Op::slice(self : Op, from : Int, to : Int) -> Op {
  if from == 0 && to == self.content_len() {
    self
  } else {
    Op::{
      counter: self.counter + from,
      container: self.container,
      content: self.content.slice(from, to),
    }
  }
}

///|
pub fn Op::content(self : Op) -> InnerContent {
  self.content
}

///|
pub fn Op::container(self : Op) -> @types.ContainerID {
  self.container
}

///|
pub fn Op::counter(self : Op) -> @types.Counter {
  self.counter
}

///|
pub fn InnerContent::content_len(self : InnerContent) -> Int {
  match self {
    List(op) => op.content_len()
    Map(_set) => 1
    Tree(_op) => 1
    Counter(_op) => 1
    _ => 1
  }
}

///|
pub fn InnerContent::slice(
  self : InnerContent,
  from : Int,
  to : Int,
) -> InnerContent {
  match self {
    List(op) => InnerContent::List(op.slice(from, to))
    Tree(op) => InnerContent::Tree(op)
    Counter(op) => InnerContent::Counter(op)
    other => other
  }
}
