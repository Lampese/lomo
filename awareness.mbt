///|
const TAG_AWARENESS_NULL : Byte = b'\x00'

///|
const TAG_AWARENESS_BOOL : Byte = b'\x01'

///|
const TAG_AWARENESS_F64 : Byte = b'\x02'

///|
const TAG_AWARENESS_I64 : Byte = b'\x03'

///|
const TAG_AWARENESS_STRING : Byte = b'\x04'

///|
const TAG_AWARENESS_LIST : Byte = b'\x05'

///|
const TAG_AWARENESS_MAP : Byte = b'\x06'

///|
const TAG_AWARENESS_BYTES : Byte = b'\x08'

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
  clock : Int64
  updated_at : UInt64
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
      if is_expired(record.updated_at, now, self.timeout_ms) {
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
    if !is_expired(record.updated_at, now, self.timeout_ms) {
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
    match self.states.get(key) {
      Some(existing) => {
        if existing.clock >= record.clock {
          continue
        }
        let incoming = EphemeralRecord::{
          value: record.value,
          clock: record.clock,
          updated_at: now,
        }
        self.states[key] = incoming
        match (existing.value, record.value) {
          (Some(_), Some(_)) => updated.push(key)
          (Some(_), None) => removed.push(key)
          (None, Some(_)) => added.push(key)
          (None, None) => ()
        }
      }
      None => {
        let incoming = EphemeralRecord::{
          value: record.value,
          clock: record.clock,
          updated_at: now,
        }
        self.states[key] = incoming
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
  match value {
    @types.LoroValue::Null => self.set_state(key, None)
    _ => self.set_state(key, Some(value))
  }
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
    if is_expired(record.updated_at, now, self.timeout_ms) {
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
  let old = self.states.get(key)
  let next_clock = match old {
    Some(record) => record.clock + 1
    None => 1
  }
  let record = EphemeralRecord::{ value, clock: next_clock, updated_at: now }
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
fn is_expired(updated_at : UInt64, now : UInt64, timeout_ms : UInt64) -> Bool {
  if timeout_ms == 0 {
    return false
  }
  now > updated_at && now - updated_at > timeout_ms
}

///|
fn encode_entries(entries : Array[(String, EphemeralRecord)]) -> Bytes {
  let buf = @buffer.new()
  let filtered : Array[(UInt64, Int64, @types.LoroValue)] = []
  for entry in entries {
    let (key, record) = entry
    let peer = match parse_peer_id(key) {
      Some(value) => value
      None => continue
    }
    let value = match record.value {
      Some(value) => value
      None => @types.LoroValue::Null
    }
    if !can_encode_awareness_value(value) {
      continue
    }
    filtered.push((peer, record.clock, value))
  }
  @encoding.write_uvarint(buf, filtered.length().to_uint64())
  for entry in filtered {
    let (peer, clock, value) = entry
    @encoding.write_uvarint(buf, peer)
    @encoding.write_ivarint(buf, clock)
    write_awareness_value(buf, value)
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
  let count = match @encoding.read_uvarint(reader) {
    Ok(value) => value.to_int()
    Err(err) => return Err(err)
  }
  let out : Array[(String, EphemeralRecord)] = []
  for i = 0; i < count; i = i + 1 {
    let peer = match @encoding.read_uvarint(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let clock = match @encoding.read_ivarint(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let value = match read_awareness_value(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let value_opt = match value {
      @types.LoroValue::Null => None
      _ => Some(value)
    }
    out.push(
      (
        peer.to_string(),
        EphemeralRecord::{ value: value_opt, clock, updated_at: 0 },
      ),
    )
  }
  Ok(out)
}

///|
fn parse_peer_id(key : String) -> UInt64? {
  let value : UInt64 = @strconv.parse_uint64(key[:]) catch { _ => return None }
  Some(value)
}

///|
fn can_encode_awareness_value(value : @types.LoroValue) -> Bool {
  match value {
    @types.LoroValue::Container(_) => false
    @types.LoroValue::List(items) => {
      for item in items {
        if !can_encode_awareness_value(item) {
          return false
        }
      }
      true
    }
    @types.LoroValue::Map(map) => {
      for _key, item in map {
        if !can_encode_awareness_value(item) {
          return false
        }
      }
      true
    }
    _ => true
  }
}

///|
fn write_awareness_value(
  buf : @buffer.Buffer,
  value : @types.LoroValue,
) -> Unit {
  match value {
    @types.LoroValue::Null => buf.write_byte(TAG_AWARENESS_NULL)
    @types.LoroValue::Bool(v) => {
      buf.write_byte(TAG_AWARENESS_BOOL)
      buf.write_byte(if v { b'\x01' } else { b'\x00' })
    }
    @types.LoroValue::F64(v) => {
      buf.write_byte(TAG_AWARENESS_F64)
      write_f64_le(buf, v)
    }
    @types.LoroValue::I64(v) => {
      buf.write_byte(TAG_AWARENESS_I64)
      @encoding.write_ivarint(buf, v)
    }
    @types.LoroValue::String(v) => {
      buf.write_byte(TAG_AWARENESS_STRING)
      @encoding.write_string(buf, v)
    }
    @types.LoroValue::Bytes(v) => {
      buf.write_byte(TAG_AWARENESS_BYTES)
      @encoding.write_bytes(buf, v)
    }
    @types.LoroValue::List(items) => {
      buf.write_byte(TAG_AWARENESS_LIST)
      @encoding.write_uvarint(buf, items.length().to_uint64())
      for item in items {
        write_awareness_value(buf, item)
      }
    }
    @types.LoroValue::Map(map) => {
      buf.write_byte(TAG_AWARENESS_MAP)
      @encoding.write_uvarint(buf, map.length().to_uint64())
      for key, item in map {
        @encoding.write_string(buf, key)
        write_awareness_value(buf, item)
      }
    }
    @types.LoroValue::Container(_) => buf.write_byte(TAG_AWARENESS_NULL)
  }
}

///|
fn read_awareness_value(
  reader : @encoding.Reader,
) -> Result[@types.LoroValue, @types.LoroError] {
  let tag = match reader.read_byte() {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  if tag == TAG_AWARENESS_NULL {
    Ok(@types.LoroValue::Null)
  } else if tag == TAG_AWARENESS_BOOL {
    let raw = match reader.read_byte() {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    if raw == b'\x00' {
      Ok(@types.LoroValue::Bool(false))
    } else if raw == b'\x01' {
      Ok(@types.LoroValue::Bool(true))
    } else {
      Err(@types.LoroError::DecodeError("invalid awareness bool"))
    }
  } else if tag == TAG_AWARENESS_F64 {
    match read_f64_le(reader) {
      Ok(value) => Ok(@types.LoroValue::F64(value))
      Err(err) => Err(err)
    }
  } else if tag == TAG_AWARENESS_I64 {
    match @encoding.read_ivarint(reader) {
      Ok(value) => Ok(@types.LoroValue::I64(value))
      Err(err) => Err(err)
    }
  } else if tag == TAG_AWARENESS_STRING {
    match @encoding.read_string(reader) {
      Ok(value) => Ok(@types.LoroValue::String(value))
      Err(err) => Err(err)
    }
  } else if tag == TAG_AWARENESS_BYTES {
    match @encoding.read_bytes(reader) {
      Ok(value) => Ok(@types.LoroValue::Bytes(value))
      Err(err) => Err(err)
    }
  } else if tag == TAG_AWARENESS_LIST {
    let count = match @encoding.read_uvarint(reader) {
      Ok(value) => value.to_int()
      Err(err) => return Err(err)
    }
    let items : Array[@types.LoroValue] = []
    for i = 0; i < count; i = i + 1 {
      let item = match read_awareness_value(reader) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      items.push(item)
    }
    Ok(@types.LoroValue::List(items))
  } else if tag == TAG_AWARENESS_MAP {
    let count = match @encoding.read_uvarint(reader) {
      Ok(value) => value.to_int()
      Err(err) => return Err(err)
    }
    let map : Map[String, @types.LoroValue] = {}
    for i = 0; i < count; i = i + 1 {
      let key = match @encoding.read_string(reader) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let item = match read_awareness_value(reader) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      map[key] = item
    }
    Ok(@types.LoroValue::Map(map))
  } else {
    Err(@types.LoroError::DecodeError("invalid awareness value tag"))
  }
}

///|
fn write_f64_le(buf : @buffer.Buffer, value : Double) -> Unit {
  let bits = value.reinterpret_as_uint64()
  buf.write_byte((bits & 0xFFUL).to_int().to_byte())
  buf.write_byte(((bits >> 8) & 0xFFUL).to_int().to_byte())
  buf.write_byte(((bits >> 16) & 0xFFUL).to_int().to_byte())
  buf.write_byte(((bits >> 24) & 0xFFUL).to_int().to_byte())
  buf.write_byte(((bits >> 32) & 0xFFUL).to_int().to_byte())
  buf.write_byte(((bits >> 40) & 0xFFUL).to_int().to_byte())
  buf.write_byte(((bits >> 48) & 0xFFUL).to_int().to_byte())
  buf.write_byte(((bits >> 56) & 0xFFUL).to_int().to_byte())
}

///|
fn read_f64_le(reader : @encoding.Reader) -> Result[Double, @types.LoroError] {
  let bytes = match reader.read_bytes(8) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let mut bits : UInt64 = 0
  for i = 0; i < 8; i = i + 1 {
    bits = bits | (bytes[i].to_uint64() << (i * 8))
  }
  Ok(bits.reinterpret_as_double())
}
