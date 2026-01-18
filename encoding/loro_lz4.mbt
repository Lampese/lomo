///|
const LZ4_FRAME_MAGIC : UInt = 0x184D2204U

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
