///|
const MAX_COLLECTION_SIZE : Int = 1 << 28

///|
pub enum LoroValueKind {
  Null
  True
  False
  I64
  F64
  Str
  Binary
  List
  Map
  ContainerType
} derive(Show, Eq)

///|
pub fn LoroValueKind::from_u8(kind : Byte) -> LoroValueKind? {
  match kind.to_int() {
    0 => Some(LoroValueKind::Null)
    1 => Some(LoroValueKind::True)
    2 => Some(LoroValueKind::False)
    3 => Some(LoroValueKind::I64)
    4 => Some(LoroValueKind::F64)
    5 => Some(LoroValueKind::Str)
    6 => Some(LoroValueKind::Binary)
    7 => Some(LoroValueKind::List)
    8 => Some(LoroValueKind::Map)
    9 => Some(LoroValueKind::ContainerType)
    _ => None
  }
}

///|
pub fn LoroValueKind::to_u8(self : LoroValueKind) -> Byte {
  match self {
    LoroValueKind::Null => 0
    LoroValueKind::True => 1
    LoroValueKind::False => 2
    LoroValueKind::I64 => 3
    LoroValueKind::F64 => 4
    LoroValueKind::Str => 5
    LoroValueKind::Binary => 6
    LoroValueKind::List => 7
    LoroValueKind::Map => 8
    LoroValueKind::ContainerType => 9
  }
}

///|
pub enum LoroOpValueKind {
  Null
  True
  False
  I64
  F64
  Str
  Binary
  ContainerType
  DeleteOnce
  DeleteSeq
  DeltaInt
  LoroValue
  MarkStart
  TreeMove
  ListMove
  ListSet
  RawTreeMove
  Future(Byte)
} derive(Show, Eq)

///|
pub fn LoroOpValueKind::from_u8(kind : Byte) -> LoroOpValueKind {
  let raw = (kind.to_uint() & 0x7FU).to_byte()
  match raw.to_int() {
    0 => LoroOpValueKind::Null
    1 => LoroOpValueKind::True
    2 => LoroOpValueKind::False
    3 => LoroOpValueKind::I64
    4 => LoroOpValueKind::F64
    5 => LoroOpValueKind::Str
    6 => LoroOpValueKind::Binary
    7 => LoroOpValueKind::ContainerType
    8 => LoroOpValueKind::DeleteOnce
    9 => LoroOpValueKind::DeleteSeq
    10 => LoroOpValueKind::DeltaInt
    11 => LoroOpValueKind::LoroValue
    12 => LoroOpValueKind::MarkStart
    13 => LoroOpValueKind::TreeMove
    14 => LoroOpValueKind::ListMove
    15 => LoroOpValueKind::ListSet
    16 => LoroOpValueKind::RawTreeMove
    _ => LoroOpValueKind::Future(raw)
  }
}

///|
pub fn LoroOpValueKind::to_u8(self : LoroOpValueKind) -> Byte {
  match self {
    LoroOpValueKind::Null => 0
    LoroOpValueKind::True => 1
    LoroOpValueKind::False => 2
    LoroOpValueKind::I64 => 3
    LoroOpValueKind::F64 => 4
    LoroOpValueKind::Str => 5
    LoroOpValueKind::Binary => 6
    LoroOpValueKind::ContainerType => 7
    LoroOpValueKind::DeleteOnce => 8
    LoroOpValueKind::DeleteSeq => 9
    LoroOpValueKind::DeltaInt => 10
    LoroOpValueKind::LoroValue => 11
    LoroOpValueKind::MarkStart => 12
    LoroOpValueKind::TreeMove => 13
    LoroOpValueKind::ListMove => 14
    LoroOpValueKind::ListSet => 15
    LoroOpValueKind::RawTreeMove => 16
    LoroOpValueKind::Future(raw) => raw
  }
}

///|
pub struct LoroMarkStart {
  len : Int
  key : String
  value : @types.LoroValue
  info : Byte
} derive(Show)

///|
pub struct LoroRawTreeMove {
  subject_peer_idx : Int
  subject_cnt : Int
  position_idx : Int
  is_parent_null : Bool
  parent_peer_idx : Int
  parent_cnt : Int
} derive(Show)

///|
pub struct LoroEncodedTreeMove {
  target_idx : Int
  is_parent_null : Bool
  parent_idx : Int
  position_idx : Int
} derive(Show)

///|
pub enum LoroOpValue {
  Null
  True
  False
  I64(Int64)
  F64(Double)
  Str(String)
  Binary(Bytes)
  ContainerIdx(Int)
  DeleteOnce
  DeleteSeq
  DeltaInt(Int)
  LoroValue(@types.LoroValue)
  MarkStart(LoroMarkStart)
  TreeMove(LoroEncodedTreeMove)
  RawTreeMove(LoroRawTreeMove)
  ListMove(from~ : Int, from_idx~ : Int, lamport~ : UInt)
  ListSet(peer_idx~ : Int, lamport~ : UInt, value~ : @types.LoroValue)
  Future(kind~ : Byte, data~ : Bytes)
} derive(Show)

///|
pub struct LoroValueReader {
  bytes : Bytes
  mut pos : Int
}

///|
pub fn LoroValueReader::new(bytes : Bytes) -> LoroValueReader {
  LoroValueReader::{ bytes, pos: 0 }
}

///|
pub fn LoroValueReader::remaining(self : LoroValueReader) -> Int {
  self.bytes.length() - self.pos
}

///|
pub fn LoroValueReader::remaining_bytes(self : LoroValueReader) -> Bytes {
  self.bytes.sub(start=self.pos, end=self.bytes.length()).to_bytes()
}

///|
fn LoroValueReader::read_byte(
  self : LoroValueReader,
) -> Result[Byte, @types.LoroError] {
  if self.pos >= self.bytes.length() {
    return Err(@types.LoroError::DecodeError("unexpected EOF"))
  }
  let b = self.bytes[self.pos]
  self.pos = self.pos + 1
  Ok(b)
}

///|
fn LoroValueReader::read_bytes(
  self : LoroValueReader,
  len : Int,
) -> Result[Bytes, @types.LoroError] {
  let end = self.pos + len
  if len < 0 || end > self.bytes.length() {
    return Err(@types.LoroError::DecodeError("unexpected EOF"))
  }
  let out = self.bytes.sub(start=self.pos, end~).to_bytes()
  self.pos = end
  Ok(out)
}

///|
pub fn LoroValueReader::read_raw_bytes(
  self : LoroValueReader,
  len : Int,
) -> Result[Bytes, @types.LoroError] {
  self.read_bytes(len)
}

///|
fn LoroValueReader::read_leb128_u64(
  self : LoroValueReader,
) -> Result[UInt64, @types.LoroError] {
  let mut shift = 0
  let mut out : UInt64 = 0
  while true {
    if shift >= 64 {
      return Err(@types.LoroError::DecodeError("leb128 overflow"))
    }
    let b = match self.read_byte() {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    let chunk = (b.to_uint64() & 0x7FUL) << shift
    out = out | chunk
    if (b.to_uint() & 0x80) == 0 {
      break
    }
    shift = shift + 7
  }
  Ok(out)
}

///|
fn LoroValueReader::read_leb128_i64(
  self : LoroValueReader,
) -> Result[Int64, @types.LoroError] {
  let mut shift = 0
  let mut out : UInt64 = 0
  let mut last : UInt64 = 0
  while true {
    if shift >= 64 {
      return Err(@types.LoroError::DecodeError("leb128 overflow"))
    }
    let b = match self.read_byte() {
      Ok(v) => v.to_uint64()
      Err(err) => return Err(err)
    }
    last = b
    let chunk = (b & 0x7FUL) << shift
    out = out | chunk
    shift = shift + 7
    if (b & 0x80UL) == 0 {
      break
    }
  }
  if shift < 64 && (last & 0x40UL) != 0 {
    out = out | (0xFFFF_FFFF_FFFF_FFFFUL << shift)
  }
  Ok(out.reinterpret_as_int64())
}

///|
pub fn LoroValueReader::read_u8(
  self : LoroValueReader,
) -> Result[Byte, @types.LoroError] {
  self.read_byte()
}

///|
pub fn LoroValueReader::read_i64(
  self : LoroValueReader,
) -> Result[Int64, @types.LoroError] {
  self.read_leb128_i64()
}

///|
pub fn LoroValueReader::read_i32(
  self : LoroValueReader,
) -> Result[Int, @types.LoroError] {
  match self.read_leb128_i64() {
    Ok(v) => Ok(v.to_int())
    Err(err) => Err(err)
  }
}

///|
pub fn LoroValueReader::read_usize(
  self : LoroValueReader,
) -> Result[Int, @types.LoroError] {
  match self.read_leb128_u64() {
    Ok(v) => Ok(v.to_int())
    Err(err) => Err(err)
  }
}

///|
pub fn LoroValueReader::read_f64(
  self : LoroValueReader,
) -> Result[Double, @types.LoroError] {
  let bytes = match self.read_bytes(8) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let bits = (bytes[0].to_uint64() << 56) |
    (bytes[1].to_uint64() << 48) |
    (bytes[2].to_uint64() << 40) |
    (bytes[3].to_uint64() << 32) |
    (bytes[4].to_uint64() << 24) |
    (bytes[5].to_uint64() << 16) |
    (bytes[6].to_uint64() << 8) |
    bytes[7].to_uint64()
  Ok(bits.reinterpret_as_double())
}

///|
pub fn LoroValueReader::read_binary(
  self : LoroValueReader,
) -> Result[Bytes, @types.LoroError] {
  let len = match self.read_usize() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  self.read_bytes(len)
}

///|
pub fn LoroValueReader::read_str(
  self : LoroValueReader,
) -> Result[String, @types.LoroError] {
  let bytes = match self.read_binary() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let view = bytes[:]
  Ok(@encoding/utf8.decode(view)) catch {
    _ => Err(@types.LoroError::DecodeError("invalid utf8"))
  }
}

///|
pub fn loro_container_type_from_u8(kind : Byte) -> @types.ContainerType {
  match kind.to_int() {
    0 => @types.ContainerType::Map
    1 => @types.ContainerType::List
    2 => @types.ContainerType::Text
    3 => @types.ContainerType::Tree
    4 => @types.ContainerType::MovableList
    5 => @types.ContainerType::Counter
    _ => @types.ContainerType::Unknown(kind)
  }
}

///|
fn loro_container_type_to_u8(container_type : @types.ContainerType) -> Byte {
  match container_type {
    @types.ContainerType::Map => 0
    @types.ContainerType::List => 1
    @types.ContainerType::Text => 2
    @types.ContainerType::Tree => 3
    @types.ContainerType::MovableList => 4
    @types.ContainerType::Counter => 5
    @types.ContainerType::Unknown(tag) => tag
    _ => 0
  }
}

///|
pub fn LoroValueReader::read_value_type_and_content(
  self : LoroValueReader,
  keys : Array[String],
  id : @types.ID,
) -> Result[@types.LoroValue, @types.LoroError] {
  let kind = match self.read_u8() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let value_kind = match LoroValueKind::from_u8(kind) {
    Some(v) => v
    None => return Err(@types.LoroError::DecodeError("invalid value kind"))
  }
  self.read_value_content(value_kind, keys, id)
}

///|
pub fn LoroValueReader::read_value_content(
  self : LoroValueReader,
  kind : LoroValueKind,
  keys : Array[String],
  id : @types.ID,
) -> Result[@types.LoroValue, @types.LoroError] {
  match kind {
    LoroValueKind::Null => Ok(@types.LoroValue::Null)
    LoroValueKind::True => Ok(@types.LoroValue::Bool(true))
    LoroValueKind::False => Ok(@types.LoroValue::Bool(false))
    LoroValueKind::I64 =>
      match self.read_i64() {
        Ok(v) => Ok(@types.LoroValue::I64(v))
        Err(err) => Err(err)
      }
    LoroValueKind::F64 =>
      match self.read_f64() {
        Ok(v) => Ok(@types.LoroValue::F64(v))
        Err(err) => Err(err)
      }
    LoroValueKind::Str =>
      match self.read_str() {
        Ok(v) => Ok(@types.LoroValue::String(v))
        Err(err) => Err(err)
      }
    LoroValueKind::Binary =>
      match self.read_binary() {
        Ok(v) => Ok(@types.LoroValue::Bytes(v))
        Err(err) => Err(err)
      }
    LoroValueKind::List => {
      let len = match self.read_usize() {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      if len > MAX_COLLECTION_SIZE {
        return Err(@types.LoroError::DecodeError("collection too large"))
      }
      let out : Array[@types.LoroValue] = []
      for i = 0; i < len; i = i + 1 {
        let item = match self.read_value_type_and_content(keys, id.inc(i)) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        out.push(item)
      }
      Ok(@types.LoroValue::List(out))
    }
    LoroValueKind::Map => {
      let len = match self.read_usize() {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      if len > MAX_COLLECTION_SIZE {
        return Err(@types.LoroError::DecodeError("collection too large"))
      }
      let out : Map[String, @types.LoroValue] = {}
      for _i = 0; _i < len; _i = _i + 1 {
        let key_idx = match self.read_usize() {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        if key_idx < 0 || key_idx >= keys.length() {
          return Err(@types.LoroError::DecodeError("invalid key index"))
        }
        let key = keys[key_idx]
        let value = match self.read_value_type_and_content(keys, id) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        out[key] = value
      }
      Ok(@types.LoroValue::Map(out))
    }
    LoroValueKind::ContainerType => {
      let kind = match self.read_u8() {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      let container_type = loro_container_type_from_u8(kind)
      Ok(
        @types.LoroValue::Container(
          @types.ContainerID::normal(id.peer, id.counter, container_type),
        ),
      )
    }
  }
}

///|
pub fn LoroValueReader::read_mark(
  self : LoroValueReader,
  keys : Array[String],
  id : @types.ID,
) -> Result[LoroMarkStart, @types.LoroError] {
  let info = match self.read_u8() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let len = match self.read_usize() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let key_idx = match self.read_usize() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if key_idx < 0 || key_idx >= keys.length() {
    return Err(@types.LoroError::DecodeError("invalid key index"))
  }
  let value = match self.read_value_type_and_content(keys, id) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(LoroMarkStart::{ len, key: keys[key_idx], value, info })
}

///|
pub fn LoroValueReader::read_tree_move(
  self : LoroValueReader,
) -> Result[LoroEncodedTreeMove, @types.LoroError] {
  let target_idx = match self.read_usize() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let is_parent_null = match self.read_u8() {
    Ok(v) => v != 0
    Err(err) => return Err(err)
  }
  let position_idx = match self.read_usize() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let mut parent_idx = 0
  if !is_parent_null {
    parent_idx = match self.read_usize() {
      Ok(v) => v
      Err(err) => return Err(err)
    }
  }
  Ok(LoroEncodedTreeMove::{
    target_idx,
    is_parent_null,
    parent_idx,
    position_idx,
  })
}

///|
pub fn LoroValueReader::read_raw_tree_move(
  self : LoroValueReader,
) -> Result[LoroRawTreeMove, @types.LoroError] {
  let subject_peer_idx = match self.read_usize() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let subject_cnt = match self.read_usize() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let position_idx = match self.read_usize() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let is_parent_null = match self.read_u8() {
    Ok(v) => v != 0
    Err(err) => return Err(err)
  }
  let mut parent_peer_idx = 0
  let mut parent_cnt = 0
  if !is_parent_null {
    parent_peer_idx = match self.read_usize() {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    parent_cnt = match self.read_usize() {
      Ok(v) => v
      Err(err) => return Err(err)
    }
  }
  Ok(LoroRawTreeMove::{
    subject_peer_idx,
    subject_cnt,
    position_idx,
    is_parent_null,
    parent_peer_idx,
    parent_cnt,
  })
}

///|
pub fn LoroValueReader::read_op_value(
  self : LoroValueReader,
  kind : LoroOpValueKind,
  keys : Array[String],
  id : @types.ID,
) -> Result[LoroOpValue, @types.LoroError] {
  match kind {
    LoroOpValueKind::Null => Ok(LoroOpValue::Null)
    LoroOpValueKind::True => Ok(LoroOpValue::True)
    LoroOpValueKind::False => Ok(LoroOpValue::False)
    LoroOpValueKind::I64 =>
      match self.read_i64() {
        Ok(v) => Ok(LoroOpValue::I64(v))
        Err(err) => Err(err)
      }
    LoroOpValueKind::F64 =>
      match self.read_f64() {
        Ok(v) => Ok(LoroOpValue::F64(v))
        Err(err) => Err(err)
      }
    LoroOpValueKind::Str =>
      match self.read_str() {
        Ok(v) => Ok(LoroOpValue::Str(v))
        Err(err) => Err(err)
      }
    LoroOpValueKind::Binary =>
      match self.read_binary() {
        Ok(v) => Ok(LoroOpValue::Binary(v))
        Err(err) => Err(err)
      }
    LoroOpValueKind::ContainerType =>
      match self.read_usize() {
        Ok(v) => Ok(LoroOpValue::ContainerIdx(v))
        Err(err) => Err(err)
      }
    LoroOpValueKind::DeleteOnce => Ok(LoroOpValue::DeleteOnce)
    LoroOpValueKind::DeleteSeq => Ok(LoroOpValue::DeleteSeq)
    LoroOpValueKind::DeltaInt =>
      match self.read_i32() {
        Ok(v) => Ok(LoroOpValue::DeltaInt(v))
        Err(err) => Err(err)
      }
    LoroOpValueKind::LoroValue =>
      match self.read_value_type_and_content(keys, id) {
        Ok(v) => Ok(LoroOpValue::LoroValue(v))
        Err(err) => Err(err)
      }
    LoroOpValueKind::MarkStart =>
      match self.read_mark(keys, id) {
        Ok(v) => Ok(LoroOpValue::MarkStart(v))
        Err(err) => Err(err)
      }
    LoroOpValueKind::TreeMove =>
      match self.read_tree_move() {
        Ok(v) => Ok(LoroOpValue::TreeMove(v))
        Err(err) => Err(err)
      }
    LoroOpValueKind::RawTreeMove =>
      match self.read_raw_tree_move() {
        Ok(v) => Ok(LoroOpValue::RawTreeMove(v))
        Err(err) => Err(err)
      }
    LoroOpValueKind::ListMove => {
      let from = match self.read_usize() {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      let from_idx = match self.read_usize() {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      let lamport = match self.read_usize() {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      Ok(
        LoroOpValue::ListMove(
          from~,
          from_idx~,
          lamport=lamport.reinterpret_as_uint(),
        ),
      )
    }
    LoroOpValueKind::ListSet => {
      let peer_idx = match self.read_usize() {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      let lamport = match self.read_usize() {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      let value = match self.read_value_type_and_content(keys, id) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      Ok(
        LoroOpValue::ListSet(
          peer_idx~,
          lamport=lamport.reinterpret_as_uint(),
          value~,
        ),
      )
    }
    LoroOpValueKind::Future(kind) => {
      let data = match self.read_binary() {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      Ok(LoroOpValue::Future(kind~, data~))
    }
  }
}

///|
pub struct LoroValueWriter {
  buf : @buffer.Buffer
}

///|
pub fn LoroValueWriter::new() -> LoroValueWriter {
  LoroValueWriter::{ buf: @buffer.new() }
}

///|
pub fn LoroValueWriter::to_bytes(self : LoroValueWriter) -> Bytes {
  self.buf.to_bytes()
}

///|
fn LoroValueWriter::write_leb128_u64(
  self : LoroValueWriter,
  value : UInt64,
) -> Unit {
  let mut v = value
  while v >= 0x80UL {
    let byte = ((v & 0x7FUL) | 0x80UL).to_int().to_byte()
    self.buf.write_byte(byte)
    v = v >> 7
  }
  self.buf.write_byte((v & 0x7FUL).to_int().to_byte())
}

///|
fn LoroValueWriter::write_leb128_i64(
  self : LoroValueWriter,
  value : Int64,
) -> Unit {
  let mut v = value
  let neg_one : Int64 = -1
  while true {
    let byte = (v & 0x7F).reinterpret_as_uint64()
    v = v >> 7
    let sign_bit = (byte & 0x40UL) != 0UL
    let done = (v == 0 && !sign_bit) || (v == neg_one && sign_bit)
    let out = if done { byte } else { byte | 0x80UL }
    self.buf.write_byte(out.to_int().to_byte())
    if done {
      break
    }
  }
}

///|
pub fn LoroValueWriter::write_u8(self : LoroValueWriter, value : Byte) -> Unit {
  self.buf.write_byte(value)
}

///|
pub fn LoroValueWriter::write_raw_bytes(
  self : LoroValueWriter,
  value : Bytes,
) -> Unit {
  self.buf.write_bytes(value)
}

///|
pub fn LoroValueWriter::write_i64(
  self : LoroValueWriter,
  value : Int64,
) -> Unit {
  self.write_leb128_i64(value)
}

///|
pub fn LoroValueWriter::write_i32(self : LoroValueWriter, value : Int) -> Unit {
  self.write_leb128_i64(value.to_int64())
}

///|
pub fn LoroValueWriter::write_usize(
  self : LoroValueWriter,
  value : Int,
) -> Unit {
  self.write_leb128_u64(value.to_uint64())
}

///|
pub fn LoroValueWriter::write_f64(
  self : LoroValueWriter,
  value : Double,
) -> Unit {
  let bits = value.reinterpret_as_uint64()
  let bytes : Array[Byte] = [
    ((bits >> 56) & 0xFFUL).to_int().to_byte(),
    ((bits >> 48) & 0xFFUL).to_int().to_byte(),
    ((bits >> 40) & 0xFFUL).to_int().to_byte(),
    ((bits >> 32) & 0xFFUL).to_int().to_byte(),
    ((bits >> 24) & 0xFFUL).to_int().to_byte(),
    ((bits >> 16) & 0xFFUL).to_int().to_byte(),
    ((bits >> 8) & 0xFFUL).to_int().to_byte(),
    (bits & 0xFFUL).to_int().to_byte(),
  ]
  self.buf.write_bytes(Bytes::from_array(bytes))
}

///|
pub fn LoroValueWriter::write_binary(
  self : LoroValueWriter,
  value : Bytes,
) -> Unit {
  self.write_usize(value.length())
  self.buf.write_bytes(value)
}

///|
pub fn LoroValueWriter::write_str(
  self : LoroValueWriter,
  value : String,
) -> Unit {
  let bytes = @encoding/utf8.encode(value)
  self.write_binary(bytes)
}

///|
fn key_index(
  keys : Array[String],
  key : String,
) -> Result[Int, @types.LoroError] {
  for i = 0; i < keys.length(); i = i + 1 {
    if keys[i] == key {
      return Ok(i)
    }
  }
  Err(@types.LoroError::EncodeError("missing key index"))
}

///|
pub fn LoroValueWriter::write_value_type_and_content(
  self : LoroValueWriter,
  value : @types.LoroValue,
  keys : Array[String],
  id : @types.ID,
) -> Result[Unit, @types.LoroError] {
  let kind = match value {
    @types.LoroValue::Null => LoroValueKind::Null
    @types.LoroValue::Bool(true) => LoroValueKind::True
    @types.LoroValue::Bool(false) => LoroValueKind::False
    @types.LoroValue::I64(_) => LoroValueKind::I64
    @types.LoroValue::F64(_) => LoroValueKind::F64
    @types.LoroValue::String(_) => LoroValueKind::Str
    @types.LoroValue::Bytes(_) => LoroValueKind::Binary
    @types.LoroValue::List(_) => LoroValueKind::List
    @types.LoroValue::Map(_) => LoroValueKind::Map
    @types.LoroValue::Container(_) => LoroValueKind::ContainerType
  }
  self.write_u8(kind.to_u8())
  self.write_value_content(value, kind, keys, id)
}

///|
pub fn LoroValueWriter::write_value_content(
  self : LoroValueWriter,
  value : @types.LoroValue,
  kind : LoroValueKind,
  keys : Array[String],
  id : @types.ID,
) -> Result[Unit, @types.LoroError] {
  match kind {
    LoroValueKind::Null => Ok(())
    LoroValueKind::True => Ok(())
    LoroValueKind::False => Ok(())
    LoroValueKind::I64 =>
      match value {
        @types.LoroValue::I64(v) => {
          self.write_i64(v)
          Ok(())
        }
        _ => Err(@types.LoroError::EncodeError("invalid i64 value"))
      }
    LoroValueKind::F64 =>
      match value {
        @types.LoroValue::F64(v) => {
          self.write_f64(v)
          Ok(())
        }
        _ => Err(@types.LoroError::EncodeError("invalid f64 value"))
      }
    LoroValueKind::Str =>
      match value {
        @types.LoroValue::String(v) => {
          self.write_str(v)
          Ok(())
        }
        _ => Err(@types.LoroError::EncodeError("invalid string value"))
      }
    LoroValueKind::Binary =>
      match value {
        @types.LoroValue::Bytes(v) => {
          self.write_binary(v)
          Ok(())
        }
        _ => Err(@types.LoroError::EncodeError("invalid binary value"))
      }
    LoroValueKind::List =>
      match value {
        @types.LoroValue::List(items) => {
          self.write_usize(items.length())
          for i = 0; i < items.length(); i = i + 1 {
            match self.write_value_type_and_content(items[i], keys, id.inc(i)) {
              Ok(_) => ()
              Err(err) => return Err(err)
            }
          }
          Ok(())
        }
        _ => Err(@types.LoroError::EncodeError("invalid list value"))
      }
    LoroValueKind::Map =>
      match value {
        @types.LoroValue::Map(map) => {
          self.write_usize(map.length())
          for entry in map {
            let (key, item) = entry
            let key_idx = match key_index(keys, key) {
              Ok(v) => v
              Err(err) => return Err(err)
            }
            self.write_usize(key_idx)
            match self.write_value_type_and_content(item, keys, id) {
              Ok(_) => ()
              Err(err) => return Err(err)
            }
          }
          Ok(())
        }
        _ => Err(@types.LoroError::EncodeError("invalid map value"))
      }
    LoroValueKind::ContainerType =>
      match value {
        @types.LoroValue::Container(container_id) => {
          let tag = loro_container_type_to_u8(container_id.container_type())
          self.write_u8(tag)
          Ok(())
        }
        _ => Err(@types.LoroError::EncodeError("invalid container value"))
      }
  }
}

///|
pub fn LoroValueWriter::write_mark(
  self : LoroValueWriter,
  mark : LoroMarkStart,
  keys : Array[String],
  id : @types.ID,
) -> Result[Unit, @types.LoroError] {
  self.write_u8(mark.info)
  self.write_usize(mark.len)
  let key_idx = match key_index(keys, mark.key) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  self.write_usize(key_idx)
  self.write_value_type_and_content(mark.value, keys, id)
}

///|
pub fn LoroValueWriter::write_tree_move(
  self : LoroValueWriter,
  tree_move : LoroEncodedTreeMove,
) -> Unit {
  self.write_usize(tree_move.target_idx)
  self.write_u8((if tree_move.is_parent_null { 1 } else { 0 }).to_byte())
  if !tree_move.is_parent_null {
    self.write_usize(tree_move.parent_idx)
  }
  self.write_usize(tree_move.position_idx)
}

///|
pub fn LoroValueWriter::write_raw_tree_move(
  self : LoroValueWriter,
  raw_move : LoroRawTreeMove,
) -> Unit {
  self.write_usize(raw_move.subject_peer_idx)
  self.write_usize(raw_move.subject_cnt)
  self.write_usize(raw_move.position_idx)
  self.write_u8((if raw_move.is_parent_null { 1 } else { 0 }).to_byte())
  if !raw_move.is_parent_null {
    self.write_usize(raw_move.parent_peer_idx)
    self.write_usize(raw_move.parent_cnt)
  }
}

///|
pub fn LoroValueWriter::write_op_value(
  self : LoroValueWriter,
  value : LoroOpValue,
  keys : Array[String],
  id : @types.ID,
) -> Result[Byte, @types.LoroError] {
  match value {
    LoroOpValue::Null => Ok(LoroOpValueKind::Null.to_u8())
    LoroOpValue::True => Ok(LoroOpValueKind::True.to_u8())
    LoroOpValue::False => Ok(LoroOpValueKind::False.to_u8())
    LoroOpValue::I64(v) => {
      self.write_i64(v)
      Ok(LoroOpValueKind::I64.to_u8())
    }
    LoroOpValue::F64(v) => {
      self.write_f64(v)
      Ok(LoroOpValueKind::F64.to_u8())
    }
    LoroOpValue::Str(v) => {
      self.write_str(v)
      Ok(LoroOpValueKind::Str.to_u8())
    }
    LoroOpValue::Binary(v) => {
      self.write_binary(v)
      Ok(LoroOpValueKind::Binary.to_u8())
    }
    LoroOpValue::ContainerIdx(idx) => {
      self.write_usize(idx)
      Ok(LoroOpValueKind::ContainerType.to_u8())
    }
    LoroOpValue::DeleteOnce => Ok(LoroOpValueKind::DeleteOnce.to_u8())
    LoroOpValue::DeleteSeq => Ok(LoroOpValueKind::DeleteSeq.to_u8())
    LoroOpValue::DeltaInt(v) => {
      self.write_i32(v)
      Ok(LoroOpValueKind::DeltaInt.to_u8())
    }
    LoroOpValue::LoroValue(v) =>
      match self.write_value_type_and_content(v, keys, id) {
        Ok(_) => Ok(LoroOpValueKind::LoroValue.to_u8())
        Err(err) => Err(err)
      }
    LoroOpValue::MarkStart(mark) =>
      match self.write_mark(mark, keys, id) {
        Ok(_) => Ok(LoroOpValueKind::MarkStart.to_u8())
        Err(err) => Err(err)
      }
    LoroOpValue::TreeMove(tree_move) => {
      self.write_tree_move(tree_move)
      Ok(LoroOpValueKind::TreeMove.to_u8())
    }
    LoroOpValue::RawTreeMove(raw_move) => {
      self.write_raw_tree_move(raw_move)
      Ok(LoroOpValueKind::RawTreeMove.to_u8())
    }
    LoroOpValue::ListMove(from~, from_idx~, lamport~) => {
      self.write_usize(from)
      self.write_usize(from_idx)
      self.write_usize(lamport.reinterpret_as_int())
      Ok(LoroOpValueKind::ListMove.to_u8())
    }
    LoroOpValue::ListSet(peer_idx~, lamport~, value~) => {
      self.write_usize(peer_idx)
      self.write_usize(lamport.reinterpret_as_int())
      match self.write_value_type_and_content(value, keys, id) {
        Ok(_) => Ok(LoroOpValueKind::ListSet.to_u8())
        Err(err) => Err(err)
      }
    }
    LoroOpValue::Future(kind~, data~) => {
      self.write_binary(data)
      Ok(kind)
    }
  }
}
