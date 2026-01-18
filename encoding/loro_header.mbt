///|
const LORO_MAGIC : Bytes = b"loro"

///|
const LORO_HEADER_LEN : Int = 22

///|
const XXH_SEED : UInt = 0x4F524F4CU

///|
const MASK32 : UInt = 0xFFFF_FFFFU

///|
const PRIME32_1 : UInt = 0x9E3779B1U

///|
const PRIME32_2 : UInt = 0x85EBCA77U

///|
const PRIME32_3 : UInt = 0xC2B2AE3DU

///|
const PRIME32_4 : UInt = 0x27D4EB2FU

///|
const PRIME32_5 : UInt = 0x165667B1U

///|
pub enum LoroEncodeMode {
  OutdatedRle
  OutdatedSnapshot
  FastSnapshot
  FastUpdates
} derive(Show, Eq)

///|
pub fn LoroEncodeMode::from_u16(value : UInt) -> LoroEncodeMode? {
  let v = value.reinterpret_as_int()
  if v == 1 {
    Some(LoroEncodeMode::OutdatedRle)
  } else if v == 2 {
    Some(LoroEncodeMode::OutdatedSnapshot)
  } else if v == 3 {
    Some(LoroEncodeMode::FastSnapshot)
  } else if v == 4 {
    Some(LoroEncodeMode::FastUpdates)
  } else {
    None
  }
}

///|
pub fn LoroEncodeMode::to_u16(self : LoroEncodeMode) -> UInt {
  match self {
    LoroEncodeMode::OutdatedRle => 1U
    LoroEncodeMode::OutdatedSnapshot => 2U
    LoroEncodeMode::FastSnapshot => 3U
    LoroEncodeMode::FastUpdates => 4U
  }
}

///|
pub fn LoroEncodeMode::is_snapshot(self : LoroEncodeMode) -> Bool {
  match self {
    LoroEncodeMode::OutdatedSnapshot => true
    LoroEncodeMode::FastSnapshot => true
    _ => false
  }
}

///|
pub fn parse_loro_header(
  bytes : Bytes,
  check_checksum : Bool,
) -> Result[(LoroEncodeMode, Bytes), @types.LoroError] {
  if bytes.length() < LORO_HEADER_LEN {
    return Err(@types.LoroError::DecodeError("invalid loro header length"))
  }
  let magic = bytes.sub(start=0, end=4).to_bytes()
  if magic != LORO_MAGIC {
    return Err(@types.LoroError::DecodeError("invalid loro magic"))
  }
  let mode_bytes = bytes.sub(start=20, end=22).to_bytes()
  let mode_raw = (mode_bytes[0].to_uint() << 8) | mode_bytes[1].to_uint()
  let mode = match LoroEncodeMode::from_u16(mode_raw) {
    Some(value) => value
    None =>
      return Err(@types.LoroError::DecodeError("unsupported loro encode mode"))
  }
  if check_checksum {
    match mode {
      LoroEncodeMode::FastSnapshot | LoroEncodeMode::FastUpdates => {
        let checksum_body = bytes.sub(start=20, end=bytes.length()).to_bytes()
        let expected = xxhash32(checksum_body, XXH_SEED)
        let actual = read_u32_le(bytes, 16)
        if expected != actual {
          return Err(@types.LoroError::DecodeError("loro checksum mismatch"))
        }
      }
      _ =>
        return Err(
          @types.LoroError::DecodeError("unsupported loro checksum mode"),
        )
    }
  }
  let body = bytes.sub(start=22, end=bytes.length()).to_bytes()
  Ok((mode, body))
}

///|
pub fn xxhash32(bytes : Bytes, seed : UInt) -> UInt {
  let len = bytes.length()
  let mut idx = 0
  let mut h32 : UInt = 0U
  if len >= 16 {
    let mut v1 = u32(seed + PRIME32_1 + PRIME32_2)
    let mut v2 = u32(seed + PRIME32_2)
    let mut v3 = u32(seed)
    let mut v4 = u32(seed - PRIME32_1)
    while idx <= len - 16 {
      v1 = round32(v1, read_u32_le(bytes, idx))
      v2 = round32(v2, read_u32_le(bytes, idx + 4))
      v3 = round32(v3, read_u32_le(bytes, idx + 8))
      v4 = round32(v4, read_u32_le(bytes, idx + 12))
      idx = idx + 16
    }
    h32 = u32(rotl32(v1, 1) + rotl32(v2, 7) + rotl32(v3, 12) + rotl32(v4, 18))
  } else {
    h32 = u32(seed + PRIME32_5)
  }
  h32 = u32(h32 + len.reinterpret_as_uint())
  while idx + 4 <= len {
    h32 = u32(h32 + read_u32_le(bytes, idx) * PRIME32_3)
    h32 = u32(rotl32(h32, 17) * PRIME32_4)
    idx = idx + 4
  }
  while idx < len {
    h32 = u32(h32 + bytes[idx].to_uint() * PRIME32_5)
    h32 = u32(rotl32(h32, 11) * PRIME32_1)
    idx = idx + 1
  }
  h32 = u32(h32 ^ (h32 >> 15))
  h32 = u32(h32 * PRIME32_2)
  h32 = u32(h32 ^ (h32 >> 13))
  h32 = u32(h32 * PRIME32_3)
  u32(h32 ^ (h32 >> 16))
}

///|
fn u32(value : UInt) -> UInt {
  value & MASK32
}

///|
fn rotl32(value : UInt, shift : Int) -> UInt {
  let s = shift % 32
  u32((value << s) | (value >> (32 - s)))
}

///|
fn round32(acc : UInt, input : UInt) -> UInt {
  let next = u32(acc + input * PRIME32_2)
  let rotated = rotl32(next, 13)
  u32(rotated * PRIME32_1)
}

///|
fn read_u32_le(bytes : Bytes, offset : Int) -> UInt {
  let b0 = bytes[offset].to_uint()
  let b1 = bytes[offset + 1].to_uint() << 8
  let b2 = bytes[offset + 2].to_uint() << 16
  let b3 = bytes[offset + 3].to_uint() << 24
  u32(b0 | b1 | b2 | b3)
}

///|
fn write_u32_le(buf : @buffer.Buffer, value : UInt) -> Unit {
  buf.write_byte((value & 0xFFU).reinterpret_as_int().to_byte())
  buf.write_byte(((value >> 8) & 0xFFU).reinterpret_as_int().to_byte())
  buf.write_byte(((value >> 16) & 0xFFU).reinterpret_as_int().to_byte())
  buf.write_byte(((value >> 24) & 0xFFU).reinterpret_as_int().to_byte())
}

///|
pub fn build_loro_payload(body : Bytes, mode : LoroEncodeMode) -> Bytes {
  let buf = @buffer.new()
  buf.write_bytes(LORO_MAGIC)
  for _i = 0; _i < 12; _i = _i + 1 {
    buf.write_byte(0)
  }
  let mode_u16 = mode.to_u16()
  let mode_bytes : Bytes = [
    ((mode_u16 >> 8) & 0xFFU).reinterpret_as_int().to_byte(),
    (mode_u16 & 0xFFU).reinterpret_as_int().to_byte(),
  ]
  let checksum_buf = @buffer.new()
  checksum_buf.write_bytes(mode_bytes)
  checksum_buf.write_bytes(body)
  let checksum = xxhash32(checksum_buf.to_bytes(), XXH_SEED)
  write_u32_le(buf, checksum)
  buf.write_bytes(mode_bytes)
  buf.write_bytes(body)
  buf.to_bytes()
}
