///|
// Changes group contiguous ops with shared metadata.
pub struct Change {
  id : @types.ID
  lamport : @types.Lamport
  deps : @types.Frontiers
  timestamp : Int64
  commit_msg : String?
  origin : String?
  ops : Array[@op.Op]
} derive(Show)

///|
pub fn Change::new(
  ops : Array[@op.Op],
  deps : @types.Frontiers,
  id : @types.ID,
  lamport : @types.Lamport,
  timestamp : Int64,
) -> Change {
  Change::new_with_meta(ops, deps, id, lamport, timestamp, None, None)
}

///|
pub fn Change::new_with_meta(
  ops : Array[@op.Op],
  deps : @types.Frontiers,
  id : @types.ID,
  lamport : @types.Lamport,
  timestamp : Int64,
  commit_msg : String?,
  origin : String?,
) -> Change {
  Change::{ id, lamport, deps, timestamp, commit_msg, origin, ops }
}

///|
pub fn Change::ops(self : Change) -> Array[@op.Op] {
  self.ops
}

///|
pub fn Change::deps(self : Change) -> @types.Frontiers {
  self.deps
}

///|
pub fn Change::peer(self : Change) -> @types.PeerID {
  self.id.peer
}

///|
pub fn Change::lamport(self : Change) -> @types.Lamport {
  self.lamport
}

///|
pub fn Change::timestamp(self : Change) -> Int64 {
  self.timestamp
}

///|
pub fn Change::commit_msg(self : Change) -> String? {
  self.commit_msg
}

///|
pub fn Change::origin(self : Change) -> String? {
  self.origin
}

///|
pub fn Change::id(self : Change) -> @types.ID {
  self.id
}

///|
pub fn Change::deps_on_self(self : Change) -> Bool {
  match self.deps.as_single() {
    Some(id) => id.peer == self.id.peer
    None => false
  }
}

///|
pub fn Change::len(self : Change) -> Int {
  let mut total = 0
  for op in self.ops {
    total = total + op.content_len()
  }
  total
}

///|
pub fn Change::is_empty(self : Change) -> Bool {
  self.len() == 0
}

///|
pub fn Change::ctr_span(self : Change) -> @types.CounterSpan {
  let start = self.id.counter
  let end = start + self.len()
  @types.CounterSpan::new(start, end)
}

///|
pub fn Change::id_span(self : Change) -> @types.IdSpan {
  let start = self.id.counter
  let end = start + self.len()
  @types.IdSpan::new(self.id.peer, start, end)
}

///|
pub fn Change::id_end(self : Change) -> @types.ID {
  let end = self.id.counter + self.len()
  @types.ID::new(self.id.peer, end)
}

///|
pub fn Change::id_last(self : Change) -> @types.ID {
  let last = self.id.counter + self.len() - 1
  @types.ID::new(self.id.peer, last)
}

///|
pub fn Change::slice(self : Change, from : Int, to : Int) -> Change {
  if from >= to {
    Change::new_with_meta(
      [],
      self.deps,
      self.id,
      self.lamport,
      self.timestamp,
      self.commit_msg,
      self.origin,
    )
  } else {
    let ops : Array[@op.Op] = []
    let mut offset = 0
    for op in self.ops {
      let op_len = op.content_len()
      let op_start = offset
      let op_end = offset + op_len
      if op_end <= from {
        offset = op_end
        continue
      }
      if op_start >= to {
        break
      }
      let slice_start = if from > op_start { from - op_start } else { 0 }
      let slice_end = if to < op_end { to - op_start } else { op_len }
      ops.push(op.slice(slice_start, slice_end))
      offset = op_end
    }
    let new_id = self.id.inc(from)
    let deps = if from > 0 {
      @types.Frontiers::from_id(self.id.inc(from - 1))
    } else {
      self.deps
    }
    Change::{
      id: new_id,
      lamport: self.lamport + from.reinterpret_as_uint(),
      deps,
      timestamp: self.timestamp,
      commit_msg: self.commit_msg,
      origin: self.origin,
      ops,
    }
  }
}
