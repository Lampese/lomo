///|
const EPHEMERAL_MAGIC : Bytes = b"LME1"

///|
const EPHEMERAL_VERSION : Byte = b'\x01'

///|
const TAG_EPHEMERAL_NONE : Byte = b'\x00'

///|
const TAG_EPHEMERAL_SOME : Byte = b'\x01'

///|
pub enum EphemeralEventTrigger {
  Local
  Import
  Timeout
} derive(Show, Eq)

///|
pub struct EphemeralStoreEvent {
  by : EphemeralEventTrigger
  added : Array[String]
  updated : Array[String]
  removed : Array[String]
} derive(Show)

///|
pub fn EphemeralStoreEvent::by(
  self : EphemeralStoreEvent,
) -> EphemeralEventTrigger {
  self.by
}

///|
pub fn EphemeralStoreEvent::added(self : EphemeralStoreEvent) -> Array[String] {
  self.added
}

///|
pub fn EphemeralStoreEvent::updated(
  self : EphemeralStoreEvent,
) -> Array[String] {
  self.updated
}

///|
pub fn EphemeralStoreEvent::removed(
  self : EphemeralStoreEvent,
) -> Array[String] {
  self.removed
}

///|
pub type LocalEphemeralCallback = (Bytes) -> Bool

///|
pub type EphemeralSubscriber = (EphemeralStoreEvent) -> Bool

///|
pub struct EphemeralStore {
  timeout_ms : UInt64
  mut next_sub_id : Int
  mut states : Map[String, EphemeralRecord]
  mut local_subs : Array[EphemeralLocalEntry]
  mut subs : Array[EphemeralSubscriberEntry]
}

///|
struct EphemeralRecord {
  value : @types.LoroValue?
  timestamp : UInt64
}

///|
struct EphemeralLocalEntry {
  id : Int
  callback : LocalEphemeralCallback
}

///|
struct EphemeralSubscriberEntry {
  id : Int
  callback : EphemeralSubscriber
}

///|
pub struct EphemeralSubscription {
  store : EphemeralStore
  id : Int
}

///|
pub fn EphemeralSubscription::unsubscribe(self : EphemeralSubscription) -> Unit {
  self.store.unsubscribe(self.id)
}

///|
pub fn EphemeralStore::new(timeout_ms : UInt64) -> EphemeralStore {
  EphemeralStore::{
    timeout_ms,
    next_sub_id: 1,
    states: Map::new(),
    local_subs: [],
    subs: [],
  }
}

///|
pub fn EphemeralStore::encode(self : EphemeralStore, key : String) -> Bytes {
  let now = now_ms()
  match self.states.get(key) {
    Some(record) =>
      if is_expired(record.timestamp, now, self.timeout_ms) {
        b""
      } else {
        encode_entries([(key, record)])
      }
    None => b""
  }
}

///|
pub fn EphemeralStore::encode_all(self : EphemeralStore) -> Bytes {
  let now = now_ms()
  let entries : Array[(String, EphemeralRecord)] = []
  for key, record in self.states {
    if !is_expired(record.timestamp, now, self.timeout_ms) {
      entries.push((key, record))
    }
  }
  encode_entries(entries)
}

///|
pub fn EphemeralStore::apply(
  self : EphemeralStore,
  data : Bytes,
) -> Result[Unit, @types.LoroError] {
  let entries = match decode_entries(data) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  if entries.length() == 0 {
    return Ok(())
  }
  let now = now_ms()
  let added : Array[String] = []
  let updated : Array[String] = []
  let removed : Array[String] = []
  for entry in entries {
    let (key, record) = entry
    if is_expired(record.timestamp, now, self.timeout_ms) {
      continue
    }
    match self.states.get(key) {
      Some(existing) => {
        if existing.timestamp >= record.timestamp {
          continue
        }
        self.states[key] = record
        match (existing.value, record.value) {
          (Some(_), Some(_)) => updated.push(key)
          (Some(_), None) => removed.push(key)
          (None, Some(_)) => added.push(key)
          (None, None) => ()
        }
      }
      None => {
        self.states[key] = record
        match record.value {
          Some(_) => added.push(key)
          None => ()
        }
      }
    }
  }
  if added.length() > 0 || updated.length() > 0 || removed.length() > 0 {
    let event = EphemeralStoreEvent::{
      by: EphemeralEventTrigger::Import,
      added,
      updated,
      removed,
    }
    self.subs = filter_ephemeral_subs(self.subs, event)
  }
  Ok(())
}

///|
pub fn EphemeralStore::set(
  self : EphemeralStore,
  key : String,
  value : @types.LoroValue,
) -> Unit {
  self.set_state(key, Some(value))
}

///|
pub fn EphemeralStore::delete(self : EphemeralStore, key : String) -> Unit {
  self.set_state(key, None)
}

///|
pub fn EphemeralStore::get(
  self : EphemeralStore,
  key : String,
) -> @types.LoroValue? {
  match self.states.get(key) {
    Some(record) => record.value
    None => None
  }
}

///|
pub fn EphemeralStore::get_all_states(
  self : EphemeralStore,
) -> Map[String, @types.LoroValue] {
  let out : Map[String, @types.LoroValue] = {}
  for key, record in self.states {
    match record.value {
      Some(value) => out[key] = value
      None => ()
    }
  }
  out
}

///|
pub fn EphemeralStore::keys(self : EphemeralStore) -> Array[String] {
  let out : Array[String] = []
  for key, record in self.states {
    match record.value {
      Some(_) => out.push(key)
      None => ()
    }
  }
  out
}

///|
pub fn EphemeralStore::remove_outdated(self : EphemeralStore) -> Unit {
  let now = now_ms()
  let removed : Array[String] = []
  let next : Map[String, EphemeralRecord] = {}
  for key, record in self.states {
    if is_expired(record.timestamp, now, self.timeout_ms) {
      match record.value {
        Some(_) => removed.push(key)
        None => ()
      }
    } else {
      next[key] = record
    }
  }
  self.states = next
  if removed.length() > 0 {
    let event = EphemeralStoreEvent::{
      by: EphemeralEventTrigger::Timeout,
      added: [],
      updated: [],
      removed,
    }
    self.subs = filter_ephemeral_subs(self.subs, event)
  }
}

///|
pub fn EphemeralStore::subscribe_local_updates(
  self : EphemeralStore,
  callback : LocalEphemeralCallback,
) -> EphemeralSubscription {
  let id = self.alloc_sub_id()
  self.local_subs.push(EphemeralLocalEntry::{ id, callback })
  EphemeralSubscription::{ store: self, id }
}

///|
pub fn EphemeralStore::subscribe(
  self : EphemeralStore,
  callback : EphemeralSubscriber,
) -> EphemeralSubscription {
  let id = self.alloc_sub_id()
  self.subs.push(EphemeralSubscriberEntry::{ id, callback })
  EphemeralSubscription::{ store: self, id }
}

///|
fn EphemeralStore::set_state(
  self : EphemeralStore,
  key : String,
  value : @types.LoroValue?,
) -> Unit {
  let now = now_ms()
  let record = EphemeralRecord::{ value, timestamp: now }
  let old = self.states.get(key)
  self.states[key] = record
  self.local_subs = filter_local_subs(self.local_subs, self.encode(key))
  let added : Array[String] = []
  let updated : Array[String] = []
  let removed : Array[String] = []
  match (old, value) {
    (Some(old_record), Some(_)) =>
      match old_record.value {
        Some(_) => updated.push(key)
        None => added.push(key)
      }
    (None, Some(_)) => added.push(key)
    (Some(old_record), None) =>
      match old_record.value {
        Some(_) => removed.push(key)
        None => ()
      }
    (None, None) => ()
  }
  if added.length() > 0 || updated.length() > 0 || removed.length() > 0 {
    let event = EphemeralStoreEvent::{
      by: EphemeralEventTrigger::Local,
      added,
      updated,
      removed,
    }
    self.subs = filter_ephemeral_subs(self.subs, event)
  }
}

///|
fn EphemeralStore::alloc_sub_id(self : EphemeralStore) -> Int {
  let id = self.next_sub_id
  self.next_sub_id = id + 1
  id
}

///|
fn EphemeralStore::unsubscribe(self : EphemeralStore, id : Int) -> Unit {
  self.local_subs = filter_local_subs_by_id(self.local_subs, id)
  self.subs = filter_ephemeral_subs_by_id(self.subs, id)
}

///|
fn filter_local_subs(
  entries : Array[EphemeralLocalEntry],
  bytes : Bytes,
) -> Array[EphemeralLocalEntry] {
  let out : Array[EphemeralLocalEntry] = []
  for entry in entries {
    if (entry.callback)(bytes) {
      out.push(entry)
    }
  }
  out
}

///|
fn filter_local_subs_by_id(
  entries : Array[EphemeralLocalEntry],
  id : Int,
) -> Array[EphemeralLocalEntry] {
  let out : Array[EphemeralLocalEntry] = []
  for entry in entries {
    if entry.id != id {
      out.push(entry)
    }
  }
  out
}

///|
fn filter_ephemeral_subs(
  entries : Array[EphemeralSubscriberEntry],
  event : EphemeralStoreEvent,
) -> Array[EphemeralSubscriberEntry] {
  let out : Array[EphemeralSubscriberEntry] = []
  for entry in entries {
    if (entry.callback)(event) {
      out.push(entry)
    }
  }
  out
}

///|
fn filter_ephemeral_subs_by_id(
  entries : Array[EphemeralSubscriberEntry],
  id : Int,
) -> Array[EphemeralSubscriberEntry] {
  let out : Array[EphemeralSubscriberEntry] = []
  for entry in entries {
    if entry.id != id {
      out.push(entry)
    }
  }
  out
}

///|
fn now_ms() -> UInt64 {
  @env.now()
}

///|
fn is_expired(timestamp : UInt64, now : UInt64, timeout_ms : UInt64) -> Bool {
  if timeout_ms == 0 {
    return false
  }
  now > timestamp && now - timestamp > timeout_ms
}

///|
fn encode_entries(entries : Array[(String, EphemeralRecord)]) -> Bytes {
  let buf = @buffer.new()
  buf.write_bytes(EPHEMERAL_MAGIC)
  buf.write_byte(EPHEMERAL_VERSION)
  @encoding.write_uvarint(buf, entries.length().to_uint64())
  for entry in entries {
    let (key, record) = entry
    @encoding.write_string(buf, key)
    @encoding.write_uvarint(buf, record.timestamp)
    match record.value {
      Some(value) => {
        buf.write_byte(TAG_EPHEMERAL_SOME)
        match @encoding.write_value(buf, value) {
          Ok(_) => ()
          Err(_) => return b""
        }
      }
      None => buf.write_byte(TAG_EPHEMERAL_NONE)
    }
  }
  buf.to_bytes()
}

///|
fn decode_entries(
  data : Bytes,
) -> Result[Array[(String, EphemeralRecord)], @types.LoroError] {
  if data.length() == 0 {
    return Ok([])
  }
  let reader = @encoding.Reader::new(data)
  let magic = match reader.read_bytes(4) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  if magic != EPHEMERAL_MAGIC {
    return Err(@types.LoroError::DecodeError("invalid awareness magic"))
  }
  let version = match reader.read_byte() {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  if version != EPHEMERAL_VERSION {
    return Err(@types.LoroError::DecodeError("unsupported awareness version"))
  }
  let count = match @encoding.read_uvarint(reader) {
    Ok(value) => value.to_int()
    Err(err) => return Err(err)
  }
  let out : Array[(String, EphemeralRecord)] = []
  for i = 0; i < count; i = i + 1 {
    let key = match @encoding.read_string(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let timestamp = match @encoding.read_uvarint(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let tag = match reader.read_byte() {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    if tag == TAG_EPHEMERAL_SOME {
      let value = match @encoding.read_value(reader) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      out.push((key, EphemeralRecord::{ value: Some(value), timestamp }))
    } else if tag == TAG_EPHEMERAL_NONE {
      out.push((key, EphemeralRecord::{ value: None, timestamp }))
    } else {
      return Err(@types.LoroError::DecodeError("invalid awareness value tag"))
    }
  }
  Ok(out)
}
