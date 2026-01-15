///|
// Core identifiers used across the CRDT.
pub type PeerID = UInt64

///|
pub type Counter = Int

///|
pub type Lamport = UInt

///|
pub struct ID {
  peer : PeerID
  counter : Counter
} derive(Show, Eq, Hash)

///|
pub struct IdLp {
  lamport : Lamport
  peer : PeerID
} derive(Show, Eq, Hash)

///|
pub struct IdFull {
  peer : PeerID
  lamport : Lamport
  counter : Counter
} derive(Show, Eq, Hash)

///|
pub fn ID::new(peer : PeerID, counter : Counter) -> ID {
  ID::{ peer, counter }
}

///|
pub fn ID::inc(self : ID, offset : Counter) -> ID {
  ID::{ peer: self.peer, counter: self.counter + offset }
}

///|
pub fn IdLp::new(peer : PeerID, lamport : Lamport) -> IdLp {
  IdLp::{ peer, lamport }
}

///|
pub fn IdFull::new(
  peer : PeerID,
  counter : Counter,
  lamport : Lamport,
) -> IdFull {
  IdFull::{ peer, counter, lamport }
}

///|
pub fn IdFull::to_id(self : IdFull) -> ID {
  ID::new(self.peer, self.counter)
}

///|
pub fn IdFull::to_id_lp(self : IdFull) -> IdLp {
  IdLp::new(self.peer, self.lamport)
}
