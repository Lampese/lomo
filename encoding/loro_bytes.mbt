///|
pub struct ByteReader {
  bytes : Bytes
  mut pos : Int
}

///|
pub fn ByteReader::new(bytes : Bytes) -> ByteReader {
  ByteReader::{ bytes, pos: 0 }
}

///|
pub fn ByteReader::remaining(self : ByteReader) -> Int {
  self.bytes.length() - self.pos
}

///|
pub fn ByteReader::read_u8(self : ByteReader) -> Result[Byte, @types.LoroError] {
  if self.pos >= self.bytes.length() {
    return Err(@types.LoroError::DecodeError("unexpected EOF"))
  }
  let b = self.bytes[self.pos]
  self.pos = self.pos + 1
  Ok(b)
}

///|
pub fn ByteReader::read_bytes(
  self : ByteReader,
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
pub fn ByteReader::read_u16_le(
  self : ByteReader,
) -> Result[Int, @types.LoroError] {
  let bytes = match self.read_bytes(2) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let v = bytes[0].to_uint() | (bytes[1].to_uint() << 8)
  Ok(v.reinterpret_as_int())
}

///|
pub fn ByteReader::read_u32_le(
  self : ByteReader,
) -> Result[UInt, @types.LoroError] {
  let bytes = match self.read_bytes(4) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let v = bytes[0].to_uint() |
    (bytes[1].to_uint() << 8) |
    (bytes[2].to_uint() << 16) |
    (bytes[3].to_uint() << 24)
  Ok(v)
}

///|
pub fn ByteReader::read_u64_le(
  self : ByteReader,
) -> Result[UInt64, @types.LoroError] {
  let bytes = match self.read_bytes(8) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let v = bytes[0].to_uint64() |
    (bytes[1].to_uint64() << 8) |
    (bytes[2].to_uint64() << 16) |
    (bytes[3].to_uint64() << 24) |
    (bytes[4].to_uint64() << 32) |
    (bytes[5].to_uint64() << 40) |
    (bytes[6].to_uint64() << 48) |
    (bytes[7].to_uint64() << 56)
  Ok(v)
}

///|
pub fn read_u16_le_at(
  bytes : Bytes,
  offset : Int,
) -> Result[Int, @types.LoroError] {
  if offset < 0 || offset + 2 > bytes.length() {
    return Err(@types.LoroError::DecodeError("unexpected EOF"))
  }
  let v = bytes[offset].to_uint() | (bytes[offset + 1].to_uint() << 8)
  Ok(v.reinterpret_as_int())
}

///|
pub fn read_u32_le_at(
  bytes : Bytes,
  offset : Int,
) -> Result[UInt, @types.LoroError] {
  if offset < 0 || offset + 4 > bytes.length() {
    return Err(@types.LoroError::DecodeError("unexpected EOF"))
  }
  let v = bytes[offset].to_uint() |
    (bytes[offset + 1].to_uint() << 8) |
    (bytes[offset + 2].to_uint() << 16) |
    (bytes[offset + 3].to_uint() << 24)
  Ok(v)
}

///|
pub fn read_i32_le_at(
  bytes : Bytes,
  offset : Int,
) -> Result[Int, @types.LoroError] {
  let raw = match read_u32_le_at(bytes, offset) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(raw.reinterpret_as_int())
}

///|
pub fn read_u64_le_at(
  bytes : Bytes,
  offset : Int,
) -> Result[UInt64, @types.LoroError] {
  if offset < 0 || offset + 8 > bytes.length() {
    return Err(@types.LoroError::DecodeError("unexpected EOF"))
  }
  let v = bytes[offset].to_uint64() |
    (bytes[offset + 1].to_uint64() << 8) |
    (bytes[offset + 2].to_uint64() << 16) |
    (bytes[offset + 3].to_uint64() << 24) |
    (bytes[offset + 4].to_uint64() << 32) |
    (bytes[offset + 5].to_uint64() << 40) |
    (bytes[offset + 6].to_uint64() << 48) |
    (bytes[offset + 7].to_uint64() << 56)
  Ok(v)
}
