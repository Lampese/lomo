///|
const EMPTY_MARK : Bytes = b"E"

///|
pub fn decode_loro_snapshot(
  bytes : Bytes,
) -> Result[DecodedSnapshot, @types.LoroError] {
  let (mode, body) = match parse_loro_header(bytes, true) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if mode != LoroEncodeMode::FastSnapshot {
    return Err(@types.LoroError::DecodeError("unsupported loro snapshot mode"))
  }
  decode_loro_snapshot_body(body)
}

///|
pub fn decode_loro_snapshot_body(
  body : Bytes,
) -> Result[DecodedSnapshot, @types.LoroError] {
  let reader = ByteReader::new(body)
  let oplog_len = match reader.read_u32_le() {
    Ok(v) => v.reinterpret_as_int()
    Err(err) => return Err(err)
  }
  let oplog_bytes = match reader.read_bytes(oplog_len) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let state_len = match reader.read_u32_le() {
    Ok(v) => v.reinterpret_as_int()
    Err(err) => return Err(err)
  }
  let state_bytes = match reader.read_bytes(state_len) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let shallow_len = match reader.read_u32_le() {
    Ok(v) => v.reinterpret_as_int()
    Err(err) => return Err(err)
  }
  let shallow_bytes = match reader.read_bytes(shallow_len) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if reader.remaining() != 0 {
    return Err(@types.LoroError::DecodeError("snapshot trailing bytes"))
  }
  let state_opt = if state_len == 1 && state_bytes == EMPTY_MARK {
    None
  } else {
    Some(state_bytes)
  }
  let needs_replay = state_opt is None
  let changes = match decode_loro_change_store(oplog_bytes) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let state = match decode_loro_doc_state(state_opt, shallow_bytes) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(DecodedSnapshot::{ state, changes, needs_replay })
}

///|
pub fn encode_loro_snapshot_body(
  arena : @arena.SharedArena,
  state : @state.DocState,
  changes : Array[@oplog.Change],
) -> Result[Bytes, @types.LoroError] {
  let oplog_bytes = match encode_loro_change_store(arena, changes) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let state_bytes = match encode_loro_doc_state(state) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let shallow_bytes : Bytes = b""
  let buf = @buffer.new()
  write_u32_le(buf, oplog_bytes.length().reinterpret_as_uint())
  buf.write_bytes(oplog_bytes)
  write_u32_le(buf, state_bytes.length().reinterpret_as_uint())
  buf.write_bytes(state_bytes)
  write_u32_le(buf, shallow_bytes.length().reinterpret_as_uint())
  buf.write_bytes(shallow_bytes)
  Ok(buf.to_bytes())
}

///|
pub fn encode_loro_snapshot(
  arena : @arena.SharedArena,
  state : @state.DocState,
  changes : Array[@oplog.Change],
) -> Result[Bytes, @types.LoroError] {
  let body = match encode_loro_snapshot_body(arena, state, changes) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(build_loro_payload(body, LoroEncodeMode::FastSnapshot))
}

///|
fn encode_loro_change_store(
  arena : @arena.SharedArena,
  changes : Array[@oplog.Change],
) -> Result[Bytes, @types.LoroError] {
  let (vv, frontiers) = compute_change_store_meta(changes)
  let entries : Array[KvEntry] = [
    KvEntry::{ key: b"vv", value: encode_loro_version_vector(vv) },
    KvEntry::{ key: b"fr", value: encode_loro_frontiers(frontiers) },
  ]
  let by_peer : Map[@types.PeerID, Array[@oplog.Change]] = {}
  for change in changes {
    if change.is_empty() {
      continue
    }
    let peer = change.peer()
    match by_peer.get(peer) {
      Some(group) => group.push(change)
      None => by_peer[peer] = [change]
    }
  }
  let peers : Array[@types.PeerID] = []
  for id, _ in by_peer {
    peers.push(id)
  }
  peers.sort_by((a, b) => if a < b { -1 } else if a > b { 1 } else { 0 })
  for peer in peers {
    match by_peer.get(peer) {
      Some(group) => {
        group.sort_by((a, b) => if a.id().counter < b.id().counter {
          -1
        } else if a.id().counter > b.id().counter {
          1
        } else {
          0
        })
        let block = match encode_block_for_peer(arena, peer, group) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        let counter_start = group[0].id().counter
        let key = encode_change_store_key(peer, counter_start)
        entries.push(KvEntry::{ key, value: block })
      }
      None => ()
    }
  }
  Ok(encode_kv_store(entries))
}

///|
fn encode_change_store_key(peer : @types.PeerID, counter : Int) -> Bytes {
  let buf = @buffer.new()
  let peer_bytes : Array[Byte] = [
    ((peer >> 56) & 0xFFUL).to_int().to_byte(),
    ((peer >> 48) & 0xFFUL).to_int().to_byte(),
    ((peer >> 40) & 0xFFUL).to_int().to_byte(),
    ((peer >> 32) & 0xFFUL).to_int().to_byte(),
    ((peer >> 24) & 0xFFUL).to_int().to_byte(),
    ((peer >> 16) & 0xFFUL).to_int().to_byte(),
    ((peer >> 8) & 0xFFUL).to_int().to_byte(),
    (peer & 0xFFUL).to_int().to_byte(),
  ]
  let ctr = counter.reinterpret_as_uint()
  let counter_bytes : Array[Byte] = [
    ((ctr >> 24) & 0xFFU).reinterpret_as_int().to_byte(),
    ((ctr >> 16) & 0xFFU).reinterpret_as_int().to_byte(),
    ((ctr >> 8) & 0xFFU).reinterpret_as_int().to_byte(),
    (ctr & 0xFFU).reinterpret_as_int().to_byte(),
  ]
  buf.write_bytes(Bytes::from_array(peer_bytes))
  buf.write_bytes(Bytes::from_array(counter_bytes))
  buf.to_bytes()
}

///|
fn compute_change_store_meta(
  changes : Array[@oplog.Change],
) -> (@types.VersionVector, @types.Frontiers) {
  let vv = @types.VersionVector::new()
  let frontiers = @types.Frontiers::new()
  let ordered : Array[@oplog.Change] = []
  for change in changes {
    if change.is_empty() {
      continue
    }
    ordered.push(change)
    let last_id = change.id_last()
    vv.extend_to_include_last_id(last_id)
  }
  ordered.sort_by((a, b) => {
    let al = a.lamport()
    let bl = b.lamport()
    if al < bl {
      -1
    } else if al > bl {
      1
    } else {
      let a_id = a.id()
      let b_id = b.id()
      if a_id.peer < b_id.peer {
        -1
      } else if a_id.peer > b_id.peer {
        1
      } else if a_id.counter < b_id.counter {
        -1
      } else if a_id.counter > b_id.counter {
        1
      } else {
        0
      }
    }
  })
  for change in ordered {
    let last_id = change.id_last()
    frontiers.update_on_new_change(last_id, change.deps())
  }
  (vv, frontiers)
}

///|
fn encode_loro_version_vector(vv : @types.VersionVector) -> Bytes {
  let entries = vv.to_map()
  let peers : Array[@types.PeerID] = []
  for peer, _ in entries {
    peers.push(peer)
  }
  peers.sort_by((a, b) => if a < b { -1 } else if a > b { 1 } else { 0 })
  let writer = PostcardWriter::new()
  writer.write_varint_usize(peers.length())
  for peer in peers {
    let counter = match entries.get(peer) {
      Some(v) => v
      None => 0
    }
    writer.write_varint_u64(peer)
    writer.write_varint_i32(counter)
  }
  writer.to_bytes()
}

///|
fn encode_loro_frontiers(frontiers : @types.Frontiers) -> Bytes {
  let ids : Array[@types.ID] = []
  for id in frontiers.iter() {
    ids.push(id)
  }
  ids.sort_by((a, b) => if a.peer < b.peer {
    -1
  } else if a.peer > b.peer {
    1
  } else if a.counter < b.counter {
    -1
  } else if a.counter > b.counter {
    1
  } else {
    0
  })
  let writer = PostcardWriter::new()
  writer.write_varint_usize(ids.length())
  for id in ids {
    writer.write_varint_u64(id.peer)
    writer.write_varint_i32(id.counter)
  }
  writer.to_bytes()
}

///|

///|
fn decode_loro_change_store(
  bytes : Bytes,
) -> Result[Array[DecodedChange], @types.LoroError] {
  let entries = match decode_kv_store(bytes) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let changes : Array[DecodedChange] = []
  for entry in entries {
    if is_change_store_meta_key(entry.key) {
      continue
    }
    let block_changes = match decode_loro_block_bytes(entry.value) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    for change in block_changes {
      changes.push(change)
    }
  }
  changes.sort_by((a, b) => if a.lamport < b.lamport {
    -1
  } else if a.lamport > b.lamport {
    1
  } else {
    0
  })
  Ok(changes)
}

///|
fn is_change_store_meta_key(key : Bytes) -> Bool {
  key == b"vv" || key == b"fr" || key == b"sv" || key == b"sf"
}
