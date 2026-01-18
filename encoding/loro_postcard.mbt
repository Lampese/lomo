///|
pub struct PostcardReader {
  bytes : Bytes
  mut pos : Int
}

///|
pub struct PostcardWriter {
  buf : @buffer.Buffer
}

///|
pub fn PostcardReader::new(bytes : Bytes) -> PostcardReader {
  PostcardReader::{ bytes, pos: 0 }
}

///|
pub fn PostcardWriter::new() -> PostcardWriter {
  PostcardWriter::{ buf: @buffer.new() }
}

///|
pub fn PostcardWriter::to_bytes(self : PostcardWriter) -> Bytes {
  self.buf.to_bytes()
}

///|
pub fn PostcardWriter::write_byte(self : PostcardWriter, value : Byte) -> Unit {
  self.buf.write_byte(value)
}

///|
pub fn PostcardWriter::write_bytes(
  self : PostcardWriter,
  value : Bytes,
) -> Unit {
  self.buf.write_bytes(value)
}

///|
pub fn PostcardReader::remaining(self : PostcardReader) -> Int {
  self.bytes.length() - self.pos
}

///|
pub fn PostcardReader::remaining_bytes(self : PostcardReader) -> Bytes {
  self.bytes.sub(start=self.pos, end=self.bytes.length()).to_bytes()
}

///|
pub fn PostcardReader::read_byte(
  self : PostcardReader,
) -> Result[Byte, @types.LoroError] {
  if self.pos >= self.bytes.length() {
    return Err(@types.LoroError::DecodeError("unexpected EOF"))
  }
  let b = self.bytes[self.pos]
  self.pos = self.pos + 1
  Ok(b)
}

///|
pub fn PostcardReader::read_bytes(
  self : PostcardReader,
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
pub fn PostcardReader::read_u8(
  self : PostcardReader,
) -> Result[Byte, @types.LoroError] {
  self.read_byte()
}

///|
pub fn PostcardReader::read_bool(
  self : PostcardReader,
) -> Result[Bool, @types.LoroError] {
  let b = match self.read_byte() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if b == 0 {
    Ok(false)
  } else if b == 1 {
    Ok(true)
  } else {
    Err(@types.LoroError::DecodeError("invalid bool"))
  }
}

///|
pub fn PostcardReader::read_varint_u64(
  self : PostcardReader,
) -> Result[UInt64, @types.LoroError] {
  let mut shift = 0
  let mut out : UInt64 = 0
  while true {
    if shift >= 64 {
      return Err(@types.LoroError::DecodeError("varint overflow"))
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
pub fn PostcardReader::read_varint_u32(
  self : PostcardReader,
) -> Result[UInt, @types.LoroError] {
  let value = match self.read_varint_u64() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(value.to_uint())
}

///|
pub fn PostcardReader::read_varint_usize(
  self : PostcardReader,
) -> Result[Int, @types.LoroError] {
  let value = match self.read_varint_u64() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(value.to_int())
}

///|
pub fn PostcardReader::read_varint_i64(
  self : PostcardReader,
) -> Result[Int64, @types.LoroError] {
  let raw = match self.read_varint_u64() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(postcard_zigzag_decode_i64(raw))
}

///|
pub fn PostcardReader::read_varint_i32(
  self : PostcardReader,
) -> Result[Int, @types.LoroError] {
  let value = match self.read_varint_i64() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(value.to_int())
}

///|
pub fn PostcardReader::read_varint_isize(
  self : PostcardReader,
) -> Result[Int, @types.LoroError] {
  self.read_varint_i32()
}

///|
pub fn PostcardReader::read_f64(
  self : PostcardReader,
) -> Result[Double, @types.LoroError] {
  let bytes = match self.read_bytes(8) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let bits = bytes[0].to_uint64() |
    (bytes[1].to_uint64() << 8) |
    (bytes[2].to_uint64() << 16) |
    (bytes[3].to_uint64() << 24) |
    (bytes[4].to_uint64() << 32) |
    (bytes[5].to_uint64() << 40) |
    (bytes[6].to_uint64() << 48) |
    (bytes[7].to_uint64() << 56)
  Ok(bits.reinterpret_as_double())
}

///|
pub fn PostcardReader::read_bytes_with_len(
  self : PostcardReader,
) -> Result[Bytes, @types.LoroError] {
  let len = match self.read_varint_usize() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  self.read_bytes(len)
}

///|
pub fn PostcardReader::read_string(
  self : PostcardReader,
) -> Result[String, @types.LoroError] {
  let bytes = match self.read_bytes_with_len() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let view = bytes[:]
  Ok(@encoding/utf8.decode(view)) catch {
    _ => Err(@types.LoroError::DecodeError("invalid utf8"))
  }
}

///|
pub fn PostcardReader::read_vec_string(
  self : PostcardReader,
) -> Result[Array[String], @types.LoroError] {
  let len = match self.read_varint_usize() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let out : Array[String] = []
  for _i = 0; _i < len; _i = _i + 1 {
    match self.read_string() {
      Ok(s) => out.push(s)
      Err(err) => return Err(err)
    }
  }
  Ok(out)
}

///|
pub fn PostcardReader::read_loro_value(
  self : PostcardReader,
) -> Result[@types.LoroValue, @types.LoroError] {
  let tag = match self.read_varint_u32() {
    Ok(v) => v.reinterpret_as_int()
    Err(err) => return Err(err)
  }
  match tag {
    0 => Ok(@types.LoroValue::Null)
    1 =>
      match self.read_bool() {
        Ok(v) => Ok(@types.LoroValue::Bool(v))
        Err(err) => Err(err)
      }
    2 =>
      match self.read_f64() {
        Ok(v) => Ok(@types.LoroValue::F64(v))
        Err(err) => Err(err)
      }
    3 =>
      match self.read_varint_i64() {
        Ok(v) => Ok(@types.LoroValue::I64(v))
        Err(err) => Err(err)
      }
    4 =>
      match self.read_string() {
        Ok(v) => Ok(@types.LoroValue::String(v))
        Err(err) => Err(err)
      }
    5 =>
      match self.read_vec_loro_value() {
        Ok(v) => Ok(@types.LoroValue::List(v))
        Err(err) => Err(err)
      }
    6 =>
      match self.read_map_loro_value() {
        Ok(v) => Ok(@types.LoroValue::Map(v))
        Err(err) => Err(err)
      }
    7 =>
      match self.read_container_id() {
        Ok(v) => Ok(@types.LoroValue::Container(v))
        Err(err) => Err(err)
      }
    8 =>
      match self.read_bytes_with_len() {
        Ok(v) => Ok(@types.LoroValue::Bytes(v))
        Err(err) => Err(err)
      }
    _ => Err(@types.LoroError::DecodeError("invalid loro value tag"))
  }
}

///|
pub fn PostcardReader::read_vec_loro_value(
  self : PostcardReader,
) -> Result[Array[@types.LoroValue], @types.LoroError] {
  let len = match self.read_varint_usize() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let out : Array[@types.LoroValue] = []
  for _i = 0; _i < len; _i = _i + 1 {
    match self.read_loro_value() {
      Ok(v) => out.push(v)
      Err(err) => return Err(err)
    }
  }
  Ok(out)
}

///|
pub fn PostcardReader::read_map_loro_value(
  self : PostcardReader,
) -> Result[Map[String, @types.LoroValue], @types.LoroError] {
  let len = match self.read_varint_usize() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let out : Map[String, @types.LoroValue] = {}
  for _i = 0; _i < len; _i = _i + 1 {
    let key = match self.read_string() {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    let value = match self.read_loro_value() {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    out[key] = value
  }
  Ok(out)
}

///|
pub fn PostcardReader::read_container_id(
  self : PostcardReader,
) -> Result[@types.ContainerID, @types.LoroError] {
  let tag = match self.read_varint_u32() {
    Ok(v) => v.reinterpret_as_int()
    Err(err) => return Err(err)
  }
  if tag == 0 {
    let name = match self.read_string() {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    let container_type = match self.read_container_type() {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    Ok(@types.ContainerID::root(name, container_type))
  } else if tag == 1 {
    let peer = match self.read_varint_u64() {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    let counter = match self.read_varint_i32() {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    let container_type = match self.read_container_type() {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    Ok(@types.ContainerID::normal(peer, counter, container_type))
  } else {
    Err(@types.LoroError::DecodeError("invalid container id tag"))
  }
}

///|
pub fn PostcardReader::read_option_container_id(
  self : PostcardReader,
) -> Result[@types.ContainerID?, @types.LoroError] {
  let tag = match self.read_u8() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if tag == 0 {
    Ok(None)
  } else if tag == 1 {
    match self.read_container_id() {
      Ok(v) => Ok(Some(v))
      Err(err) => Err(err)
    }
  } else {
    Err(@types.LoroError::DecodeError("invalid option tag"))
  }
}

///|
pub fn PostcardReader::read_container_type(
  self : PostcardReader,
) -> Result[@types.ContainerType, @types.LoroError] {
  let tag = match self.read_u8() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  match tag.to_int() {
    0 => Ok(@types.ContainerType::Text)
    1 => Ok(@types.ContainerType::Map)
    2 => Ok(@types.ContainerType::List)
    3 => Ok(@types.ContainerType::MovableList)
    4 => Ok(@types.ContainerType::Tree)
    5 => Ok(@types.ContainerType::Counter)
    _ => Ok(@types.ContainerType::Unknown(tag))
  }
}

///|
pub fn PostcardReader::read_vec_bytes(
  self : PostcardReader,
) -> Result[Array[Bytes], @types.LoroError] {
  let len = match self.read_varint_usize() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let out : Array[Bytes] = []
  for i = 0; i < len; i = i + 1 {
    match self.read_bytes_with_len() {
      Ok(v) => out.push(v)
      Err(err) => return Err(err)
    }
  }
  Ok(out)
}

///|
pub fn PostcardReader::read_option_i64(
  self : PostcardReader,
) -> Result[Int64?, @types.LoroError] {
  let tag = match self.read_u8() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if tag == 0 {
    Ok(None)
  } else if tag == 1 {
    let value = match self.read_varint_i64() {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    Ok(Some(value))
  } else {
    Err(@types.LoroError::DecodeError("invalid option tag"))
  }
}

///|
pub fn PostcardReader::try_read_varint_usize(
  self : PostcardReader,
) -> Result[Int?, @types.LoroError] {
  if self.remaining() == 0 {
    return Ok(None)
  }
  match self.read_varint_usize() {
    Ok(v) => Ok(Some(v))
    Err(err) => Err(err)
  }
}

///|
pub fn PostcardReader::try_read_varint_isize(
  self : PostcardReader,
) -> Result[Int?, @types.LoroError] {
  if self.remaining() == 0 {
    return Ok(None)
  }
  match self.read_varint_isize() {
    Ok(v) => Ok(Some(v))
    Err(err) => Err(err)
  }
}

///|
fn postcard_zigzag_decode_i64(value : UInt64) -> Int64 {
  let signed = value.reinterpret_as_int64()
  let shifted = signed >> 1
  let sign = -(signed & 1)
  shifted ^ sign
}

///|
fn postcard_zigzag_encode_i64(value : Int64) -> UInt64 {
  let shifted = value << 1
  let sign = value >> 63
  (shifted ^ sign).reinterpret_as_uint64()
}

///|
pub fn PostcardWriter::write_u8(self : PostcardWriter, value : Byte) -> Unit {
  self.write_byte(value)
}

///|
pub fn PostcardWriter::write_bool(self : PostcardWriter, value : Bool) -> Unit {
  if value {
    self.write_byte(1)
  } else {
    self.write_byte(0)
  }
}

///|
pub fn PostcardWriter::write_varint_u64(
  self : PostcardWriter,
  value : UInt64,
) -> Unit {
  let mut v = value
  while v >= 0x80UL {
    let byte = ((v & 0x7FUL) | 0x80UL).to_int().to_byte()
    self.write_byte(byte)
    v = v >> 7
  }
  self.write_byte((v & 0x7FUL).to_int().to_byte())
}

///|
pub fn PostcardWriter::write_varint_u32(
  self : PostcardWriter,
  value : UInt,
) -> Unit {
  self.write_varint_u64(value.to_uint64())
}

///|
pub fn PostcardWriter::write_varint_usize(
  self : PostcardWriter,
  value : Int,
) -> Unit {
  self.write_varint_u64(value.to_uint64())
}

///|
pub fn PostcardWriter::write_varint_i64(
  self : PostcardWriter,
  value : Int64,
) -> Unit {
  self.write_varint_u64(postcard_zigzag_encode_i64(value))
}

///|
pub fn PostcardWriter::write_varint_i32(
  self : PostcardWriter,
  value : Int,
) -> Unit {
  self.write_varint_i64(value.to_int64())
}

///|
pub fn PostcardWriter::write_varint_isize(
  self : PostcardWriter,
  value : Int,
) -> Unit {
  self.write_varint_i32(value)
}

///|
pub fn PostcardWriter::write_f64(self : PostcardWriter, value : Double) -> Unit {
  let bits = value.reinterpret_as_uint64()
  let bytes : Array[Byte] = [
    (bits & 0xFFUL).to_int().to_byte(),
    ((bits >> 8) & 0xFFUL).to_int().to_byte(),
    ((bits >> 16) & 0xFFUL).to_int().to_byte(),
    ((bits >> 24) & 0xFFUL).to_int().to_byte(),
    ((bits >> 32) & 0xFFUL).to_int().to_byte(),
    ((bits >> 40) & 0xFFUL).to_int().to_byte(),
    ((bits >> 48) & 0xFFUL).to_int().to_byte(),
    ((bits >> 56) & 0xFFUL).to_int().to_byte(),
  ]
  self.write_bytes(Bytes::from_array(bytes))
}

///|
pub fn PostcardWriter::write_bytes_with_len(
  self : PostcardWriter,
  value : Bytes,
) -> Unit {
  self.write_varint_usize(value.length())
  self.write_bytes(value)
}

///|
pub fn PostcardWriter::write_string(
  self : PostcardWriter,
  value : String,
) -> Unit {
  let bytes = @encoding/utf8.encode(value)
  self.write_bytes_with_len(bytes)
}

///|
pub fn PostcardWriter::write_vec_bytes(
  self : PostcardWriter,
  values : Array[Bytes],
) -> Unit {
  self.write_varint_usize(values.length())
  for item in values {
    self.write_bytes_with_len(item)
  }
}

///|
pub fn PostcardWriter::write_vec_string(
  self : PostcardWriter,
  values : Array[String],
) -> Unit {
  self.write_varint_usize(values.length())
  for item in values {
    self.write_string(item)
  }
}

///|
pub fn PostcardWriter::write_container_type(
  self : PostcardWriter,
  value : @types.ContainerType,
) -> Unit {
  let tag = match value {
    @types.ContainerType::Text => 0
    @types.ContainerType::RichText => 0
    @types.ContainerType::Map => 1
    @types.ContainerType::List => 2
    @types.ContainerType::MovableList => 3
    @types.ContainerType::Tree => 4
    @types.ContainerType::Counter => 5
    @types.ContainerType::Unknown(tag) => tag.to_int()
  }
  self.write_u8(tag.to_byte())
}

///|
pub fn PostcardWriter::write_container_id(
  self : PostcardWriter,
  value : @types.ContainerID,
) -> Unit {
  match value {
    @types.ContainerID::Root(name~, container_type~) => {
      self.write_varint_u32(0U)
      self.write_string(name)
      self.write_container_type(container_type)
    }
    @types.ContainerID::Normal(peer~, counter~, container_type~) => {
      self.write_varint_u32(1U)
      self.write_varint_u64(peer)
      self.write_varint_i32(counter)
      self.write_container_type(container_type)
    }
  }
}

///|
pub fn PostcardWriter::write_option_container_id(
  self : PostcardWriter,
  value : @types.ContainerID?,
) -> Unit {
  match value {
    None => self.write_u8(0)
    Some(id) => {
      self.write_u8(1)
      self.write_container_id(id)
    }
  }
}

///|
pub fn PostcardWriter::write_loro_value(
  self : PostcardWriter,
  value : @types.LoroValue,
) -> Unit {
  match value {
    @types.LoroValue::Null => self.write_varint_u32(0U)
    @types.LoroValue::Bool(v) => {
      self.write_varint_u32(1U)
      self.write_bool(v)
    }
    @types.LoroValue::F64(v) => {
      self.write_varint_u32(2U)
      self.write_f64(v)
    }
    @types.LoroValue::I64(v) => {
      self.write_varint_u32(3U)
      self.write_varint_i64(v)
    }
    @types.LoroValue::String(v) => {
      self.write_varint_u32(4U)
      self.write_string(v)
    }
    @types.LoroValue::List(items) => {
      self.write_varint_u32(5U)
      self.write_vec_loro_value(items)
    }
    @types.LoroValue::Map(map) => {
      self.write_varint_u32(6U)
      self.write_map_loro_value(map)
    }
    @types.LoroValue::Container(id) => {
      self.write_varint_u32(7U)
      self.write_container_id(id)
    }
    @types.LoroValue::Bytes(bytes) => {
      self.write_varint_u32(8U)
      self.write_bytes_with_len(bytes)
    }
  }
}

///|
pub fn PostcardWriter::write_vec_loro_value(
  self : PostcardWriter,
  values : Array[@types.LoroValue],
) -> Unit {
  self.write_varint_usize(values.length())
  for item in values {
    self.write_loro_value(item)
  }
}

///|
pub fn PostcardWriter::write_map_loro_value(
  self : PostcardWriter,
  values : Map[String, @types.LoroValue],
) -> Unit {
  let keys : Array[String] = []
  for key, _ in values {
    keys.push(key)
  }
  keys.sort_by((a, b) => if a < b { -1 } else if a > b { 1 } else { 0 })
  self.write_varint_usize(keys.length())
  for key in keys {
    self.write_string(key)
    match values.get(key) {
      Some(value) => self.write_loro_value(value)
      None => self.write_loro_value(@types.LoroValue::Null)
    }
  }
}

///|
pub fn PostcardWriter::write_option_i64(
  self : PostcardWriter,
  value : Int64?,
) -> Unit {
  match value {
    None => self.write_u8(0)
    Some(v) => {
      self.write_u8(1)
      self.write_varint_i64(v)
    }
  }
}
