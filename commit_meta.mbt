///|
pub struct CommitMeta {
  mut message : String?
  mut origin : String?
  mut timestamp : Int64
} derive(Show)

///|
pub fn CommitMeta::new(timestamp : Int64) -> CommitMeta {
  CommitMeta::{ message: None, origin: None, timestamp }
}

///|
pub fn CommitMeta::message(self : CommitMeta) -> String? {
  self.message
}

///|
pub fn CommitMeta::origin(self : CommitMeta) -> String? {
  self.origin
}

///|
pub fn CommitMeta::timestamp(self : CommitMeta) -> Int64 {
  self.timestamp
}

///|
pub fn CommitMeta::set_message(self : CommitMeta, message : String?) -> Unit {
  self.message = message
}

///|
pub fn CommitMeta::set_origin(self : CommitMeta, origin : String?) -> Unit {
  self.origin = origin
}

///|
pub fn CommitMeta::set_timestamp(self : CommitMeta, timestamp : Int64) -> Unit {
  self.timestamp = timestamp
}

///|
pub type PreCommitCallback = (CommitMeta) -> Bool
