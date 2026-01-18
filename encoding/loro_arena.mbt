///|
pub fn decode_keys(bytes : Bytes) -> Result[Array[String], @types.LoroError] {
  let reader = LoroValueReader::new(bytes)
  let out : Array[String] = []
  while reader.remaining() > 0 {
    match reader.read_str() {
      Ok(key) => out.push(key)
      Err(err) => return Err(err)
    }
  }
  Ok(out)
}

///|
pub fn encode_keys(keys : Array[String]) -> Bytes {
  let writer = LoroValueWriter::new()
  for key in keys {
    writer.write_str(key)
  }
  writer.to_bytes()
}

///|
pub fn decode_container_arena(
  bytes : Bytes,
  keys : Array[String],
  peers : Array[@types.PeerID],
) -> Result[Array[@types.ContainerID], @types.LoroError] {
  if bytes.length() == 0 {
    return Ok([])
  }
  let reader = PostcardReader::new(bytes)
  let out : Array[@types.ContainerID] = []
  let count = match reader.read_varint_usize() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  for _i = 0; _i < count; _i = _i + 1 {
    let field_len = match reader.read_varint_usize() {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    if field_len != 4 {
      return Err(
        @types.LoroError::DecodeError("container arena field count mismatch"),
      )
    }
    let is_root = match reader.read_bool() {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    let kind = match reader.read_u8() {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    let peer_index = match reader.read_varint_usize() {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    let key_or_ctr = match reader.read_varint_i32() {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    let container_type = loro_container_type_from_u8(kind)
    if is_root {
      let key_index = key_or_ctr
      if key_index < 0 || key_index >= keys.length() {
        return Err(@types.LoroError::DecodeError("invalid container key index"))
      }
      out.push(@types.ContainerID::root(keys[key_index], container_type))
    } else {
      if peer_index < 0 || peer_index >= peers.length() {
        return Err(
          @types.LoroError::DecodeError("invalid container peer index"),
        )
      }
      out.push(
        @types.ContainerID::normal(
          peers[peer_index],
          key_or_ctr,
          container_type,
        ),
      )
    }
  }
  if reader.remaining() != 0 {
    return Err(@types.LoroError::DecodeError("container arena trailing bytes"))
  }
  Ok(out)
}

///|
pub fn encode_container_arena(
  ids : Array[@types.ContainerID],
  keys : Array[String],
  peers : Array[@types.PeerID],
) -> Result[Bytes, @types.LoroError] {
  let writer = PostcardWriter::new()
  writer.write_varint_usize(ids.length())
  for id in ids {
    writer.write_varint_usize(4)
    match id {
      @types.ContainerID::Root(name~, container_type~) => {
        writer.write_bool(true)
        writer.write_u8(loro_container_type_to_u8(container_type))
        writer.write_varint_usize(0)
        let mut key_idx = -1
        for i = 0; i < keys.length(); i = i + 1 {
          if keys[i] == name {
            key_idx = i
            break
          }
        }
        if key_idx < 0 {
          return Err(@types.LoroError::EncodeError("missing root key index"))
        }
        writer.write_varint_i32(key_idx)
      }
      @types.ContainerID::Normal(peer~, counter~, container_type~) => {
        writer.write_bool(false)
        writer.write_u8(loro_container_type_to_u8(container_type))
        let mut peer_idx = -1
        for i = 0; i < peers.length(); i = i + 1 {
          if peers[i] == peer {
            peer_idx = i
            break
          }
        }
        if peer_idx < 0 {
          return Err(
            @types.LoroError::EncodeError("missing container peer index"),
          )
        }
        writer.write_varint_usize(peer_idx)
        writer.write_varint_i32(counter)
      }
    }
  }
  Ok(writer.to_bytes())
}

///|
pub fn decode_positions(
  bytes : Bytes,
) -> Result[Array[Bytes], @types.LoroError] {
  if bytes.length() == 0 {
    return Ok([])
  }
  let columns = match decode_columnar_vec_columns(bytes, 2) {
    Ok(v) => v
    Err(_) => return decode_positions_legacy(bytes)
  }
  let common = match decode_rle_u32(columns[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let rest_reader = PostcardReader::new(columns[1])
  let rest = match rest_reader.read_vec_bytes() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if rest_reader.remaining() != 0 {
    return Err(@types.LoroError::DecodeError("position arena trailing bytes"))
  }
  decode_positions_from_parts(common, rest)
}

///|
pub fn encode_positions(positions : Array[Bytes]) -> Bytes {
  if positions.length() == 0 {
    return b""
  }
  let (common, rest) = collect_position_parts(positions)
  let prefix_bytes = encode_rle_u32(common)
  let rest_writer = PostcardWriter::new()
  rest_writer.write_vec_bytes(rest)
  let rest_bytes = rest_writer.to_bytes()
  encode_columnar_vec_columns([prefix_bytes, rest_bytes])
}

///|
fn decode_positions_legacy(
  bytes : Bytes,
) -> Result[Array[Bytes], @types.LoroError] {
  let reader = PostcardReader::new(bytes)
  let prefix_bytes = match reader.read_bytes_with_len() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let second_bytes = match reader.read_bytes_with_len() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let (common, rest) = if reader.remaining() == 0 {
    let common = match decode_rle_u32(prefix_bytes) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    let rest_reader = PostcardReader::new(second_bytes)
    let rest = match rest_reader.read_vec_bytes() {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    (common, rest)
  } else {
    let third_bytes = match reader.read_bytes_with_len() {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    if reader.remaining() != 0 {
      return Err(@types.LoroError::DecodeError("position arena trailing bytes"))
    }
    let base_reader = PostcardReader::new(prefix_bytes)
    let base = match base_reader.read_varint_u32() {
      Ok(v) => v.reinterpret_as_int()
      Err(err) => return Err(err)
    }
    if base_reader.remaining() != 0 {
      return Err(
        @types.LoroError::DecodeError("position arena base trailing bytes"),
      )
    }
    let deltas = match decode_rle_u32(second_bytes) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    let rest_reader = PostcardReader::new(third_bytes)
    let rest = match rest_reader.read_vec_bytes() {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    let common : Array[Int] = []
    for d in deltas {
      common.push(base + d)
    }
    (common, rest)
  }
  decode_positions_from_parts(common, rest)
}

///|
fn decode_positions_from_parts(
  common : Array[Int],
  rest : Array[Bytes],
) -> Result[Array[Bytes], @types.LoroError] {
  let count = common.length()
  if rest.length() != count {
    return Err(@types.LoroError::DecodeError("position arena length mismatch"))
  }
  let positions : Array[Bytes] = []
  for i = 0; i < count; i = i + 1 {
    let prefix_len = common[i]
    if prefix_len < 0 {
      return Err(@types.LoroError::DecodeError("invalid prefix length"))
    }
    let buf = @buffer.new()
    if i > 0 {
      let prev = positions[i - 1]
      if prefix_len > prev.length() {
        return Err(@types.LoroError::DecodeError("prefix out of range"))
      }
      buf.write_bytes(prev.sub(start=0, end=prefix_len).to_bytes())
    }
    buf.write_bytes(rest[i])
    positions.push(buf.to_bytes())
  }
  Ok(positions)
}

///|
fn collect_position_parts(
  positions : Array[Bytes],
) -> (Array[Int], Array[Bytes]) {
  let prefixes : Array[Int] = []
  let rests : Array[Bytes] = []
  for i = 0; i < positions.length(); i = i + 1 {
    let current = positions[i]
    let mut prefix = 0
    if i > 0 {
      let prev = positions[i - 1]
      let max = if prev.length() < current.length() {
        prev.length()
      } else {
        current.length()
      }
      while prefix < max && prev[prefix] == current[prefix] {
        prefix = prefix + 1
      }
    }
    prefixes.push(prefix)
    let rest = current.sub(start=prefix, end=current.length()).to_bytes()
    rests.push(rest)
  }
  (prefixes, rests)
}
