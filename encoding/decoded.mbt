///|
pub struct DecodedOp {
  container : @types.ContainerID
  content : @op.RawOpContent
} derive(Show)

///|
pub struct DecodedChange {
  id : @types.ID
  lamport : @types.Lamport
  deps : @types.Frontiers
  timestamp : Int64
  commit_msg : String?
  origin : String?
  ops : Array[DecodedOp]
} derive(Show)

///|
pub fn DecodedChange::len(self : DecodedChange) -> Int {
  let mut total = 0
  for op in self.ops {
    total = total + op.content.content_len()
  }
  total
}

///|
pub struct DecodedSnapshot {
  state : @state.DocState
  changes : Array[DecodedChange]
} derive(Show)

///|
pub enum DecodedPayload {
  Updates(Array[DecodedChange])
  Snapshot(DecodedSnapshot)
} derive(Show)
