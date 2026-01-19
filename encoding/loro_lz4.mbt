///|
const LZ4_FRAME_MAGIC : UInt = 0x184D2204U

///|
const LZ4_FRAME_FLG : Byte = b'\x60'

///|
const LZ4_FRAME_BD : Byte = b'\x70'

///|
const LZ4_MAX_BLOCK_SIZE : Int = 4 * 1024 * 1024

///|
const LZ4_MIN_MATCH : Int = 4

///|
const LZ4_HASH_SIZE : Int = 1 << 16

///|
const LZ4_HASH_SEED : UInt = 0x9E3779B1U

///|
fn lz4_write_u32_le(buf : @buffer.Buffer, value : UInt) -> Unit {
  buf.write_byte((value & 0xFFU).reinterpret_as_int().to_byte())
  buf.write_byte(((value >> 8) & 0xFFU).reinterpret_as_int().to_byte())
  buf.write_byte(((value >> 16) & 0xFFU).reinterpret_as_int().to_byte())
  buf.write_byte(((value >> 24) & 0xFFU).reinterpret_as_int().to_byte())
}

///|
fn lz4_hash4(bytes : Bytes, pos : Int) -> Int {
  let v = bytes[pos].to_uint() |
    (bytes[pos + 1].to_uint() << 8) |
    (bytes[pos + 2].to_uint() << 16) |
    (bytes[pos + 3].to_uint() << 24)
  let h = (v * LZ4_HASH_SEED) >> 16
  h.reinterpret_as_int()
}

///|
fn lz4_write_len(buf : @buffer.Buffer, len : Int) -> Unit {
  let mut v = len
  while v >= 255 {
    buf.write_byte((255).to_byte())
    v = v - 255
  }
  buf.write_byte(v.to_byte())
}

///|
fn lz4_encode_block(bytes : Bytes) -> Bytes {
  if bytes.length() == 0 {
    return b""
  }
  let len = bytes.length()
  let dict : Array[Int] = []
  for i = 0; i < LZ4_HASH_SIZE; i = i + 1 {
    dict.push(-1)
  }
  let buf = @buffer.new()
  let mut anchor = 0
  let mut idx = 0
  while idx + LZ4_MIN_MATCH <= len {
    let h = lz4_hash4(bytes, idx)
    let prev = dict[h]
    dict[h] = idx
    if prev >= 0 && idx - prev <= 0xFFFF {
      let mut match_len = 0
      while match_len < LZ4_MIN_MATCH {
        if bytes[prev + match_len] != bytes[idx + match_len] {
          break
        }
        match_len = match_len + 1
      }
      if match_len == LZ4_MIN_MATCH {
        while idx + match_len < len &&
              bytes[prev + match_len] == bytes[idx + match_len] {
          match_len = match_len + 1
        }
        let literal_len = idx - anchor
        let match_token = match_len - LZ4_MIN_MATCH
        let lit_token = if literal_len < 15 { literal_len } else { 15 }
        let match_token_n = if match_token < 15 { match_token } else { 15 }
        let token = ((lit_token << 4) | match_token_n).to_byte()
        buf.write_byte(token)
        if literal_len >= 15 {
          lz4_write_len(buf, literal_len - 15)
        }
        if literal_len > 0 {
          let literal_bytes = bytes.sub(start=anchor, end=idx).to_bytes()
          buf.write_bytes(literal_bytes)
        }
        let offset = idx - prev
        buf.write_byte((offset & 0xFF).to_byte())
        buf.write_byte(((offset >> 8) & 0xFF).to_byte())
        if match_token >= 15 {
          lz4_write_len(buf, match_token - 15)
        }
        idx = idx + match_len
        anchor = idx
        continue
      }
    }
    idx = idx + 1
  }
  let literal_len = len - anchor
  let lit_token = if literal_len < 15 { literal_len } else { 15 }
  let token = (lit_token << 4).to_byte()
  buf.write_byte(token)
  if literal_len >= 15 {
    lz4_write_len(buf, literal_len - 15)
  }
  if literal_len > 0 {
    let literal_bytes = bytes.sub(start=anchor, end=len).to_bytes()
    buf.write_bytes(literal_bytes)
  }
  buf.to_bytes()
}

///|
fn lz4_frame_header_checksum(flg : Byte, bd : Byte) -> Byte {
  let header_bytes : Bytes = [flg, bd]
  let hash = xxhash32(header_bytes, 0U)
  ((hash >> 8) & 0xFFU).reinterpret_as_int().to_byte()
}

///|
fn lz4_encode_frame(bytes : Bytes) -> Bytes {
  let buf = @buffer.new()
  lz4_write_u32_le(buf, LZ4_FRAME_MAGIC)
  buf.write_byte(LZ4_FRAME_FLG)
  buf.write_byte(LZ4_FRAME_BD)
  buf.write_byte(lz4_frame_header_checksum(LZ4_FRAME_FLG, LZ4_FRAME_BD))
  let mut pos = 0
  while pos < bytes.length() {
    let remain = bytes.length() - pos
    let chunk_len = if remain > LZ4_MAX_BLOCK_SIZE {
      LZ4_MAX_BLOCK_SIZE
    } else {
      remain
    }
    let chunk = bytes.sub(start=pos, end=pos + chunk_len).to_bytes()
    let compressed = lz4_encode_block(chunk)
    if compressed.length() < chunk.length() {
      lz4_write_u32_le(buf, compressed.length().reinterpret_as_uint())
      buf.write_bytes(compressed)
    } else {
      let size = chunk.length().reinterpret_as_uint() | 0x8000_0000U
      lz4_write_u32_le(buf, size)
      buf.write_bytes(chunk)
    }
    pos = pos + chunk_len
  }
  lz4_write_u32_le(buf, 0U)
  buf.to_bytes()
}

///|
pub fn lz4_decode_frame(bytes : Bytes) -> Result[Bytes, @types.LoroError] {
  let reader = ByteReader::new(bytes)
  let magic = match reader.read_u32_le() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if magic != LZ4_FRAME_MAGIC {
    return Err(@types.LoroError::DecodeError("invalid lz4 frame magic"))
  }
  let flg = match reader.read_u8() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let _bd = match reader.read_u8() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let version = (flg.to_uint() >> 6) & 0x3
  if version != 0x1 {
    return Err(@types.LoroError::DecodeError("unsupported lz4 frame version"))
  }
  let block_checksum = (flg.to_uint() & 0x10) != 0
  let content_size = (flg.to_uint() & 0x08) != 0
  let content_checksum = (flg.to_uint() & 0x04) != 0
  let dict_id = (flg.to_uint() & 0x01) != 0
  if content_size {
    ignore(reader.read_u64_le())
  }
  if dict_id {
    ignore(reader.read_u32_le())
  }
  // header checksum byte
  ignore(reader.read_u8())
  let out : Array[Byte] = []
  while true {
    let block_size_raw = match reader.read_u32_le() {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    if block_size_raw == 0U {
      break
    }
    let is_uncompressed = (block_size_raw & 0x8000_0000U) != 0U
    let block_size = (block_size_raw & 0x7FFF_FFFFU).reinterpret_as_int()
    let block_bytes = match reader.read_bytes(block_size) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    if is_uncompressed {
      for b in block_bytes[:] {
        out.push(b)
      }
    } else {
      let decoded = match lz4_decode_block(block_bytes) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      for b in decoded[:] {
        out.push(b)
      }
    }
    if block_checksum {
      ignore(reader.read_u32_le())
    }
  }
  if content_checksum {
    ignore(reader.read_u32_le())
  }
  Ok(@buffer.from_array(out).to_bytes())
}

///|
fn lz4_decode_block(bytes : Bytes) -> Result[Bytes, @types.LoroError] {
  let out : Array[Byte] = []
  let mut idx = 0
  let len = bytes.length()
  while idx < len {
    let token = bytes[idx]
    idx = idx + 1
    let mut literal_len = token.to_int() >> 4
    if literal_len == 15 {
      let (extra, next) = match lz4_read_len(bytes, idx) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      literal_len = literal_len + extra
      idx = next
    }
    if idx + literal_len > len {
      return Err(@types.LoroError::DecodeError("lz4 literal overrun"))
    }
    for i = 0; i < literal_len; i = i + 1 {
      out.push(bytes[idx + i])
    }
    idx = idx + literal_len
    if idx >= len {
      break
    }
    if idx + 2 > len {
      return Err(@types.LoroError::DecodeError("lz4 missing offset"))
    }
    let offset = bytes[idx].to_int() | (bytes[idx + 1].to_int() << 8)
    idx = idx + 2
    if offset <= 0 || offset > out.length() {
      return Err(@types.LoroError::DecodeError("lz4 invalid offset"))
    }
    let mut match_len = token.to_int() & 0x0F
    if match_len == 15 {
      let (extra, next) = match lz4_read_len(bytes, idx) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      match_len = match_len + extra
      idx = next
    }
    match_len = match_len + 4
    for _i = 0; _i < match_len; _i = _i + 1 {
      let src_index = out.length() - offset
      out.push(out[src_index])
    }
  }
  Ok(@buffer.from_array(out).to_bytes())
}

///|
fn lz4_read_len(
  bytes : Bytes,
  start : Int,
) -> Result[(Int, Int), @types.LoroError] {
  let mut idx = start
  let mut total = 0
  let len = bytes.length()
  while true {
    if idx >= len {
      return Err(@types.LoroError::DecodeError("lz4 length overflow"))
    }
    let b = bytes[idx].to_int()
    idx = idx + 1
    total = total + b
    if b != 255 {
      break
    }
  }
  Ok((total, idx))
}
