///|
const SST_MAGIC : UInt = 0x4F524F4CU

///|
priv struct BlockMeta {
  offset : Int
  is_large : Bool
  compression : Int
  first_key : Bytes
}

///|
pub struct KvEntry {
  key : Bytes
  value : Bytes
} derive(Show)

///|
priv struct EncodeMeta {
  offset : Int
  first_key : Bytes
  is_large : Bool
  compression : Int
  last_key : Bytes?
}

///|
fn kv_write_u16_le(buf : @buffer.Buffer, value : Int) -> Unit {
  let v = value.reinterpret_as_uint()
  buf.write_byte((v & 0xFFU).reinterpret_as_int().to_byte())
  buf.write_byte(((v >> 8) & 0xFFU).reinterpret_as_int().to_byte())
}

///|
fn kv_write_u32_le(buf : @buffer.Buffer, value : UInt) -> Unit {
  buf.write_byte((value & 0xFFU).reinterpret_as_int().to_byte())
  buf.write_byte(((value >> 8) & 0xFFU).reinterpret_as_int().to_byte())
  buf.write_byte(((value >> 16) & 0xFFU).reinterpret_as_int().to_byte())
  buf.write_byte(((value >> 24) & 0xFFU).reinterpret_as_int().to_byte())
}

///|
fn cmp_bytes(a : Bytes, b : Bytes) -> Int {
  let alen = a.length()
  let blen = b.length()
  let min = if alen < blen { alen } else { blen }
  for i = 0; i < min; i = i + 1 {
    let av = a[i].to_int()
    let bv = b[i].to_int()
    if av < bv {
      return -1
    } else if av > bv {
      return 1
    }
  }
  if alen < blen {
    -1
  } else if alen > blen {
    1
  } else {
    0
  }
}

///|
pub fn encode_kv_store(entries : Array[KvEntry]) -> Bytes {
  if entries.length() == 0 {
    return b""
  }
  let sorted : Array[KvEntry] = []
  for entry in entries {
    sorted.push(entry)
  }
  sorted.sort_by((a, b) => cmp_bytes(a.key, b.key))
  let buf = @buffer.new()
  kv_write_u32_le(buf, SST_MAGIC)
  buf.write_byte(0)
  let metas : Array[EncodeMeta] = []
  for entry in sorted {
    let offset = buf.length()
    buf.write_bytes(entry.value)
    let checksum = xxhash32(entry.value, XXH_SEED)
    kv_write_u32_le(buf, checksum)
    metas.push(EncodeMeta::{
      offset,
      first_key: entry.key,
      is_large: true,
      compression: 0,
      last_key: None,
    })
  }
  let meta_offset = buf.length()
  let meta_entries = @buffer.new()
  for m in metas {
    kv_write_u32_le(meta_entries, m.offset.reinterpret_as_uint())
    kv_write_u16_le(meta_entries, m.first_key.length())
    meta_entries.write_bytes(m.first_key)
    let flags = (if m.is_large { 0x80 } else { 0 }) | m.compression
    meta_entries.write_byte(flags.to_byte())
    if !m.is_large {
      match m.last_key {
        Some(last) => {
          kv_write_u16_le(meta_entries, last.length())
          meta_entries.write_bytes(last)
        }
        None => kv_write_u16_le(meta_entries, 0)
      }
    }
  }
  let meta = @buffer.new()
  kv_write_u32_le(meta, metas.length().reinterpret_as_uint())
  let meta_bytes = meta_entries.to_bytes()
  meta.write_bytes(meta_bytes)
  let meta_checksum = xxhash32(meta_bytes, XXH_SEED)
  kv_write_u32_le(meta, meta_checksum)
  buf.write_bytes(meta.to_bytes())
  kv_write_u32_le(buf, meta_offset.reinterpret_as_uint())
  buf.to_bytes()
}

///|
pub fn decode_kv_store(
  bytes : Bytes,
) -> Result[Array[KvEntry], @types.LoroError] {
  if bytes.length() == 0 {
    return Ok([])
  }
  if bytes.length() < 9 {
    return Err(@types.LoroError::DecodeError("invalid sstable bytes"))
  }
  let magic = match read_u32_le_at(bytes, 0) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if magic != SST_MAGIC {
    return Err(@types.LoroError::DecodeError("invalid sstable magic"))
  }
  let schema = bytes[4].to_int()
  if schema != 0 {
    return Err(@types.LoroError::DecodeError("unsupported sstable version"))
  }
  let meta_offset = match read_u32_le_at(bytes, bytes.length() - 4) {
    Ok(v) => v.reinterpret_as_int()
    Err(err) => return Err(err)
  }
  if meta_offset < 0 || meta_offset >= bytes.length() - 4 {
    return Err(@types.LoroError::DecodeError("invalid sstable meta offset"))
  }
  let meta_bytes = bytes
    .sub(start=meta_offset, end=bytes.length() - 4)
    .to_bytes()
  let meta = match decode_sstable_meta(meta_bytes) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let entries : Array[KvEntry] = []
  for i = 0; i < meta.length(); i = i + 1 {
    let m = meta[i]
    let offset = m.offset
    let end = if i + 1 < meta.length() {
      meta[i + 1].offset
    } else {
      meta_offset
    }
    if end < offset || end > bytes.length() {
      return Err(@types.LoroError::DecodeError("invalid block offset"))
    }
    let block = bytes.sub(start=offset, end~).to_bytes()
    let decoded = match decode_block_data(block, m.compression) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    if m.is_large {
      entries.push(KvEntry::{ key: m.first_key, value: decoded })
    } else {
      let block_entries = match decode_normal_block(decoded, m.first_key) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      for entry in block_entries {
        entries.push(entry)
      }
    }
  }
  Ok(entries)
}

///|
fn decode_sstable_meta(
  bytes : Bytes,
) -> Result[Array[BlockMeta], @types.LoroError] {
  let reader = ByteReader::new(bytes)
  let count = match reader.read_u32_le() {
    Ok(v) => v.reinterpret_as_int()
    Err(err) => return Err(err)
  }
  let metas : Array[BlockMeta] = []
  for _i = 0; _i < count; _i = _i + 1 {
    let offset = match reader.read_u32_le() {
      Ok(v) => v.reinterpret_as_int()
      Err(err) => return Err(err)
    }
    let key_len = match reader.read_u16_le() {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    let first_key = match reader.read_bytes(key_len) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    let flags = match reader.read_u8() {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    let is_large = (flags.to_uint() & 0x80U) != 0U
    let compression = (flags.to_uint() & 0x7FU).reinterpret_as_int()
    if !is_large {
      let last_len = match reader.read_u16_le() {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      ignore(reader.read_bytes(last_len))
    }
    metas.push(BlockMeta::{ offset, is_large, compression, first_key })
  }
  if reader.remaining() < 4 {
    return Err(@types.LoroError::DecodeError("invalid sstable meta"))
  }
  Ok(metas)
}

///|
fn decode_block_data(
  bytes : Bytes,
  compression : Int,
) -> Result[Bytes, @types.LoroError] {
  if bytes.length() < 4 {
    return Err(@types.LoroError::DecodeError("invalid sstable block"))
  }
  let raw = bytes.sub(start=0, end=bytes.length() - 4).to_bytes()
  if compression == 0 {
    Ok(raw)
  } else if compression == 1 {
    lz4_decode_frame(raw)
  } else {
    Err(@types.LoroError::DecodeError("unsupported sstable compression"))
  }
}

///|
fn decode_normal_block(
  bytes : Bytes,
  first_key : Bytes,
) -> Result[Array[KvEntry], @types.LoroError] {
  if bytes.length() < 2 {
    return Err(@types.LoroError::DecodeError("invalid normal block"))
  }
  let offsets_len = match read_u16_le_at(bytes, bytes.length() - 2) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let data_end = bytes.length() - 2 * (offsets_len + 1)
  if data_end < 0 {
    return Err(@types.LoroError::DecodeError("invalid offsets length"))
  }
  let entries : Array[KvEntry] = []
  let mut idx = 0
  let mut offset = 0
  let mut offset_next = 0
  while idx < offsets_len {
    offset = match read_u16_le_at(bytes, data_end + idx * 2) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    if idx + 1 < offsets_len {
      offset_next = match read_u16_le_at(bytes, data_end + (idx + 1) * 2) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
    } else {
      offset_next = data_end
    }
    if offset < 0 || offset_next < offset || offset_next > data_end {
      return Err(@types.LoroError::DecodeError("invalid block offset"))
    }
    if idx == 0 {
      let value = bytes.sub(start=offset, end=offset_next).to_bytes()
      entries.push(KvEntry::{ key: first_key, value })
    } else {
      if offset + 3 > data_end {
        return Err(@types.LoroError::DecodeError("invalid key header"))
      }
      let common = bytes[offset].to_int()
      let key_len = match read_u16_le_at(bytes, offset + 1) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      let key_start = offset + 3
      let key_end = key_start + key_len
      if key_end > offset_next || common < 0 || common > first_key.length() {
        return Err(@types.LoroError::DecodeError("invalid key length"))
      }
      let buf = @buffer.new()
      buf.write_bytes(first_key.sub(start=0, end=common).to_bytes())
      buf.write_bytes(bytes.sub(start=key_start, end=key_end).to_bytes())
      let key = buf.to_bytes()
      let value = bytes.sub(start=key_end, end=offset_next).to_bytes()
      entries.push(KvEntry::{ key, value })
    }
    idx = idx + 1
  }
  Ok(entries)
}
