///|
const MAGIC : Bytes = b"LMO1"

///|
const MAGIC_SNAPSHOT : Bytes = b"LMS1"

///|
const VERSION_V1 : Byte = b'\x01'

///|
const VERSION : Byte = b'\x02'

///|
const TAG_CONTAINER_ROOT : Byte = b'\x00'

///|
const TAG_CONTAINER_NORMAL : Byte = b'\x01'

///|
const TAG_CONTAINER_MAP : Byte = b'\x00'

///|
const TAG_CONTAINER_LIST : Byte = b'\x01'

///|
const TAG_CONTAINER_TEXT : Byte = b'\x02'

///|
const TAG_CONTAINER_TREE : Byte = b'\x03'

///|
const TAG_CONTAINER_RICH_TEXT : Byte = b'\x04'

///|
const TAG_CONTAINER_MOVABLE_LIST : Byte = b'\x05'

///|
const TAG_CONTAINER_UNKNOWN : Byte = b'\x06'

///|
const TAG_CONTAINER_COUNTER : Byte = b'\x07'

///|
const TAG_VALUE_NULL : Byte = b'\x00'

///|
const TAG_VALUE_BOOL_FALSE : Byte = b'\x01'

///|
const TAG_VALUE_BOOL_TRUE : Byte = b'\x02'

///|
const TAG_VALUE_I64 : Byte = b'\x03'

///|
const TAG_VALUE_F64 : Byte = b'\x04'

///|
const TAG_VALUE_STRING : Byte = b'\x05'

///|
const TAG_VALUE_BYTES : Byte = b'\x06'

///|
const TAG_VALUE_LIST : Byte = b'\x07'

///|
const TAG_VALUE_MAP : Byte = b'\x08'

///|
const TAG_VALUE_CONTAINER : Byte = b'\x09'

///|
const TAG_OPTION_NONE : Byte = b'\x00'

///|
const TAG_OPTION_SOME : Byte = b'\x01'

///|
const TAG_LIST_INSERT : Byte = b'\x00'

///|
const TAG_LIST_DELETE : Byte = b'\x01'

///|
const TAG_LIST_MOVE : Byte = b'\x02'

///|
const TAG_LIST_SET : Byte = b'\x03'

///|
const TAG_LIST_STYLE_START : Byte = b'\x04'

///|
const TAG_LIST_STYLE_END : Byte = b'\x05'

///|
const TAG_SLICE_DATA : Byte = b'\x00'

///|
const TAG_SLICE_STR : Byte = b'\x01'

///|
const TAG_MAPSET_NONE : Byte = b'\x00'

///|
const TAG_MAPSET_SOME : Byte = b'\x01'

///|
const TAG_OP_MAP : Byte = b'\x00'

///|
const TAG_OP_LIST : Byte = b'\x01'

///|
const TAG_OP_TREE : Byte = b'\x02'

///|
const TAG_OP_COUNTER : Byte = b'\x03'

///|
const TAG_TREE_CREATE : Byte = b'\x00'

///|
const TAG_TREE_MOVE : Byte = b'\x01'

///|
const TAG_TREE_DELETE : Byte = b'\x02'

///|
const TAG_TREE_PARENT_ROOT : Byte = b'\x00'

///|
const TAG_TREE_PARENT_NODE : Byte = b'\x01'

///|
const TAG_TREE_PARENT_DELETED : Byte = b'\x02'

///|
pub struct Reader {
  bytes : Bytes
  mut pos : Int
}

///|
pub fn Reader::new(bytes : Bytes) -> Reader {
  Reader::{ bytes, pos: 0 }
}

///|
pub fn Reader::remaining(self : Reader) -> Int {
  self.bytes.length() - self.pos
}

///|
pub fn Reader::read_byte(self : Reader) -> Result[Byte, @types.LoroError] {
  if self.pos >= self.bytes.length() {
    return Err(@types.LoroError::DecodeError("unexpected EOF"))
  }
  let b = self.bytes[self.pos]
  self.pos = self.pos + 1
  Ok(b)
}

///|
pub fn Reader::read_bytes(
  self : Reader,
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
fn zigzag_encode_i64(value : Int64) -> UInt64 {
  let shifted = value << 1
  let sign = value >> 63
  (shifted ^ sign).reinterpret_as_uint64()
}

///|
fn zigzag_decode_i64(value : UInt64) -> Int64 {
  let signed = value.reinterpret_as_int64()
  let shifted = signed >> 1
  let sign = -(signed & 1)
  shifted ^ sign
}

///|
pub fn write_uvarint(buf : @buffer.Buffer, value : UInt64) -> Unit {
  let mut v = value
  while v >= 0x80UL {
    let byte = ((v & 0x7FUL) | 0x80UL).to_int().to_byte()
    buf.write_byte(byte)
    v = v >> 7
  }
  buf.write_byte((v & 0x7FUL).to_int().to_byte())
}

///|
pub fn write_ivarint(buf : @buffer.Buffer, value : Int64) -> Unit {
  write_uvarint(buf, zigzag_encode_i64(value))
}

///|
pub fn write_int(buf : @buffer.Buffer, value : Int) -> Unit {
  write_ivarint(buf, value.to_int64())
}

///|
pub fn write_uint(buf : @buffer.Buffer, value : UInt) -> Unit {
  write_uvarint(buf, value.to_uint64())
}

///|
pub fn write_bytes(buf : @buffer.Buffer, value : Bytes) -> Unit {
  write_uvarint(buf, value.length().to_uint64())
  buf.write_bytes(value)
}

///|
pub fn write_string(buf : @buffer.Buffer, value : String) -> Unit {
  let bytes = @encoding/utf8.encode(value)
  write_bytes(buf, bytes)
}

///|
pub fn read_uvarint(reader : Reader) -> Result[UInt64, @types.LoroError] {
  let mut shift = 0
  let mut out : UInt64 = 0
  while true {
    if shift >= 64 {
      return Err(@types.LoroError::DecodeError("varint overflow"))
    }
    let b = match reader.read_byte() {
      Ok(value) => value
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
pub fn read_ivarint(reader : Reader) -> Result[Int64, @types.LoroError] {
  match read_uvarint(reader) {
    Ok(raw) => Ok(zigzag_decode_i64(raw))
    Err(err) => Err(err)
  }
}

///|
pub fn read_int(reader : Reader) -> Result[Int, @types.LoroError] {
  match read_ivarint(reader) {
    Ok(raw) => Ok(raw.to_int())
    Err(err) => Err(err)
  }
}

///|
pub fn read_uint(reader : Reader) -> Result[UInt, @types.LoroError] {
  match read_uvarint(reader) {
    Ok(raw) => Ok(raw.to_uint())
    Err(err) => Err(err)
  }
}

///|
pub fn read_bytes(reader : Reader) -> Result[Bytes, @types.LoroError] {
  match read_uvarint(reader) {
    Ok(len) => reader.read_bytes(len.to_int())
    Err(err) => Err(err)
  }
}

///|
pub fn read_string(reader : Reader) -> Result[String, @types.LoroError] {
  let bytes = match read_bytes(reader) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let view = bytes[:]
  Ok(@encoding/utf8.decode(view)) catch {
    _ => Err(@types.LoroError::DecodeError("invalid utf8"))
  }
}
