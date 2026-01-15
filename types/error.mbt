///|
// Shared error type for the CRDT library.
pub(all) suberror LoroError {
  InvalidPeerID
  InvalidContainer(String)
  DecodeError(String)
  EncodeError(String)
  MissingDependency(String)
  InternalError(String)
  Unsupported(String)
  StyleConfigMissing(String)
  FrontiersNotIncluded(ID)
  TreeNodeNotFound(TreeID)
  TreeParentNotFound(TreeID)
  UndoGroupAlreadyStarted
  UndoGroupNotStarted
  UndoWithDifferentPeerId(expected~ : PeerID, actual~ : PeerID)
} derive(Show, Eq)
