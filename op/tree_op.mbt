///|
// Tree operations for movable tree containers.
pub(all) enum TreeOp {
  Create(
    target~ : @types.TreeID,
    parent~ : @types.TreeParentId,
    position~ : @types.FractionalIndex
  )
  Move(
    target~ : @types.TreeID,
    parent~ : @types.TreeParentId,
    position~ : @types.FractionalIndex
  )
  Delete(target~ : @types.TreeID)
} derive(Show)

///|
pub fn TreeOp::target(self : TreeOp) -> @types.TreeID {
  match self {
    Create(target~, parent=_, position=_) => target
    Move(target~, parent=_, position=_) => target
    Delete(target~) => target
  }
}

///|
pub fn TreeOp::content_len(_self : TreeOp) -> Int {
  1
}
