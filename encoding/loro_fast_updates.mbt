///|
pub struct LoroChangesHeader {
  peer : @types.PeerID
  counter : Int
  n_changes : Int
  peers : Array[@types.PeerID]
  counters : Array[Int]
  lamports : Array[@types.Lamport]
  deps_groups : Array[@types.Frontiers]
} derive(Show)

///|
pub fn decode_loro_updates(
  bytes : Bytes,
) -> Result[Array[DecodedChange], @types.LoroError] {
  let (mode, body) = match parse_loro_header(bytes, true) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if mode != LoroEncodeMode::FastUpdates {
    return Err(@types.LoroError::DecodeError("unsupported loro updates mode"))
  }
  decode_loro_updates_body(body)
}

///|
struct LoroEncodedBlock {
  counter_start : Int
  counter_len : Int
  lamport_start : @types.Lamport
  lamport_len : @types.Lamport
  n_changes : Int
  header : Bytes
  change_meta : Bytes
  cids : Bytes
  keys : Bytes
  positions : Bytes
  ops : Bytes
  delete_start_ids : Bytes
  values : Bytes
} derive(Show)

///|
struct LoroEncodedOp {
  container_index : Int
  prop : Int
  value_type : Byte
  len : Int
} derive(Show)

///|
struct LoroDeleteStartId {
  peer_idx : Int
  counter : Int
  len : Int
} derive(Show)

///|
pub fn decode_loro_updates_body(
  body : Bytes,
) -> Result[Array[DecodedChange], @types.LoroError] {
  let reader = LoroValueReader::new(body)
  let changes : Array[DecodedChange] = []
  while reader.remaining() > 0 {
    let len = match reader.read_usize() {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    if len < 0 || len > reader.remaining() {
      return Err(@types.LoroError::DecodeError("invalid block length"))
    }
    let block_bytes = match reader.read_raw_bytes(len) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    let block_changes = match decode_loro_block(block_bytes) {
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
pub fn decode_loro_block_bytes(
  bytes : Bytes,
) -> Result[Array[DecodedChange], @types.LoroError] {
  decode_loro_block(bytes)
}

///|
fn decode_loro_block(
  bytes : Bytes,
) -> Result[Array[DecodedChange], @types.LoroError] {
  let block = match read_encoded_block(bytes) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let header = match
    decode_changes_header(
      block.header,
      block.n_changes,
      block.counter_start,
      block.counter_len,
      block.lamport_start,
      block.lamport_len,
    ) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let (timestamps, commit_msgs) = match
    decode_change_meta(block.change_meta, block.n_changes) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let keys = match decode_keys(block.keys) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let positions = match decode_positions(block.positions) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let cids = match decode_container_arena(block.cids, keys, header.peers) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let encoded_ops = match decode_encoded_ops(block.ops) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let delete_ids = match decode_delete_start_ids(block.delete_start_ids) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let value_reader = LoroValueReader::new(block.values)
  let changes : Array[DecodedChange] = []
  for i = 0; i < header.n_changes; i = i + 1 {
    let ops : Array[DecodedOp] = []
    let commit_msg = commit_msgs[i]
    let change = DecodedChange::{
      id: @types.ID::new(header.peer, header.counters[i]),
      lamport: header.lamports[i],
      deps: header.deps_groups[i],
      timestamp: timestamps[i],
      commit_msg,
      origin: None,
      ops,
    }
    changes.push(change)
  }
  let mut counter = block.counter_start
  let mut change_index = 0
  let mut delete_index = 0
  for encoded in encoded_ops {
    let op_id = @types.ID::new(header.peer, counter)
    let value_kind = LoroOpValueKind::from_u8(encoded.value_type)
    let op_value = match value_reader.read_op_value(value_kind, keys, op_id) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    let container_id = cids[encoded.container_index]
    let content = match
      decode_loro_op(
        container_id,
        encoded.prop,
        op_value,
        delete_ids,
        delete_index,
        keys,
        header.peers,
        positions,
        op_id,
      ) {
      Ok((c, used)) => {
        delete_index = used
        c
      }
      Err(err) => return Err(err)
    }
    changes[change_index].ops.push(DecodedOp::{
      container: container_id,
      content,
    })
    counter = counter + encoded.len
    if counter >= header.counters[change_index + 1] {
      change_index = change_index + 1
    }
  }
  Ok(changes)
}

///|
fn decode_loro_op(
  container_id : @types.ContainerID,
  prop : Int,
  value : LoroOpValue,
  delete_ids : Array[LoroDeleteStartId],
  delete_index : Int,
  keys : Array[String],
  peers : Array[@types.PeerID],
  positions : Array[Bytes],
  op_id : @types.ID,
) -> Result[(@op.RawOpContent, Int), @types.LoroError] {
  let container_type = container_id.container_type()
  if container_type == @types.ContainerType::Map {
    let key_index = prop
    match value {
      LoroOpValue::DeleteOnce => {
        if key_index < 0 {
          return Err(@types.LoroError::DecodeError("invalid map key index"))
        }
        if key_index >= keys.length() {
          return Err(@types.LoroError::DecodeError("invalid map key index"))
        }
        let key = keys[key_index]
        let map_set = @op.MapSet::new(key, None)
        Ok((@op.RawOpContent::Map(map_set), delete_index))
      }
      LoroOpValue::LoroValue(v) => {
        if key_index < 0 {
          return Err(@types.LoroError::DecodeError("invalid map key index"))
        }
        if key_index >= keys.length() {
          return Err(@types.LoroError::DecodeError("invalid map key index"))
        }
        let key = keys[key_index]
        let map_set = @op.MapSet::new(key, Some(v))
        Ok((@op.RawOpContent::Map(map_set), delete_index))
      }
      _ => Err(@types.LoroError::DecodeError("invalid map op value"))
    }
  } else if container_type == @types.ContainerType::List {
    decode_list_like(prop, value, delete_ids, delete_index, peers)
  } else if container_type == @types.ContainerType::MovableList {
    decode_movable_list(prop, value, delete_ids, delete_index, peers)
  } else if container_type == @types.ContainerType::Text {
    decode_text_op(prop, value, delete_ids, delete_index, peers)
  } else if container_type == @types.ContainerType::Tree {
    decode_tree_op(container_id, value, peers, positions, op_id, delete_index)
  } else if container_type == @types.ContainerType::Counter {
    decode_counter_op(value, delete_index)
  } else {
    Err(@types.LoroError::DecodeError("unsupported container type"))
  }
}

///|
fn decode_counter_op(
  value : LoroOpValue,
  delete_index : Int,
) -> Result[(@op.RawOpContent, Int), @types.LoroError] {
  let delta = match value {
    LoroOpValue::I64(v) => v.to_double()
    LoroOpValue::F64(v) => v
    _ => return Err(@types.LoroError::DecodeError("invalid counter op"))
  }
  Ok((@op.RawOpContent::Counter(@op.CounterOp::new(delta)), delete_index))
}

///|
fn decode_list_like(
  prop : Int,
  value : LoroOpValue,
  delete_ids : Array[LoroDeleteStartId],
  delete_index : Int,
  peers : Array[@types.PeerID],
) -> Result[(@op.RawOpContent, Int), @types.LoroError] {
  let pos = prop
  match value {
    LoroOpValue::LoroValue(v) =>
      match v {
        @types.LoroValue::List(items) => {
          let slice = @op.ListSlice::RawData(items)
          let op = @op.ListOp::Insert(slice~, pos~)
          Ok((@op.RawOpContent::List(op), delete_index))
        }
        _ => Err(@types.LoroError::DecodeError("invalid list insert value"))
      }
    LoroOpValue::DeleteSeq => {
      if delete_index >= delete_ids.length() {
        return Err(@types.LoroError::DecodeError("delete id underrun"))
      }
      let entry = delete_ids[delete_index]
      let peer_index = entry.peer_idx
      if peer_index < 0 || peer_index >= peers.length() {
        return Err(@types.LoroError::DecodeError("invalid delete peer index"))
      }
      let id_start = @types.ID::new(peers[peer_index], entry.counter)
      let span = @op.DeleteSpanWithId::new(id_start, pos, entry.len)
      Ok((@op.RawOpContent::List(@op.ListOp::Delete(span)), delete_index + 1))
    }
    LoroOpValue::ListMove(from~, from_idx~, lamport~) => {
      if from_idx < 0 || from_idx >= peers.length() {
        return Err(@types.LoroError::DecodeError("invalid move peer index"))
      }
      let elem_id = @types.IdLp::new(peers[from_idx], lamport)
      let op = @op.ListOp::Move(from~, to=pos, elem_id~)
      Ok((@op.RawOpContent::List(op), delete_index))
    }
    LoroOpValue::ListSet(peer_idx~, lamport~, value~) => {
      if peer_idx < 0 || peer_idx >= peers.length() {
        return Err(@types.LoroError::DecodeError("invalid set peer index"))
      }
      let elem_id = @types.IdLp::new(peers[peer_idx], lamport)
      let op = @op.ListOp::Set(elem_id~, value~)
      Ok((@op.RawOpContent::List(op), delete_index))
    }
    _ => Err(@types.LoroError::DecodeError("invalid list op value"))
  }
}

///|
fn decode_movable_list(
  prop : Int,
  value : LoroOpValue,
  delete_ids : Array[LoroDeleteStartId],
  delete_index : Int,
  peers : Array[@types.PeerID],
) -> Result[(@op.RawOpContent, Int), @types.LoroError] {
  let pos = prop
  match value {
    LoroOpValue::LoroValue(v) =>
      match v {
        @types.LoroValue::List(items) => {
          let slice = @op.ListSlice::RawData(items)
          let op = @op.ListOp::Insert(slice~, pos~)
          Ok((@op.RawOpContent::List(op), delete_index))
        }
        _ =>
          Err(
            @types.LoroError::DecodeError("invalid movable list insert value"),
          )
      }
    LoroOpValue::DeleteSeq => {
      if delete_index >= delete_ids.length() {
        return Err(@types.LoroError::DecodeError("delete id underrun"))
      }
      let entry = delete_ids[delete_index]
      let peer_index = entry.peer_idx
      if peer_index < 0 || peer_index >= peers.length() {
        return Err(@types.LoroError::DecodeError("invalid delete peer index"))
      }
      let id_start = @types.ID::new(peers[peer_index], entry.counter)
      let span = @op.DeleteSpanWithId::new(id_start, pos, entry.len)
      Ok((@op.RawOpContent::List(@op.ListOp::Delete(span)), delete_index + 1))
    }
    LoroOpValue::ListMove(from~, from_idx~, lamport~) => {
      if from_idx < 0 || from_idx >= peers.length() {
        return Err(@types.LoroError::DecodeError("invalid move peer index"))
      }
      let elem_id = @types.IdLp::new(peers[from_idx], lamport)
      let op = @op.ListOp::Move(from~, to=pos, elem_id~)
      Ok((@op.RawOpContent::List(op), delete_index))
    }
    LoroOpValue::ListSet(peer_idx~, lamport~, value~) => {
      if peer_idx < 0 || peer_idx >= peers.length() {
        return Err(@types.LoroError::DecodeError("invalid set peer index"))
      }
      let elem_id = @types.IdLp::new(peers[peer_idx], lamport)
      let op = @op.ListOp::Set(elem_id~, value~)
      Ok((@op.RawOpContent::List(op), delete_index))
    }
    _ => Err(@types.LoroError::DecodeError("invalid movable list op value"))
  }
}

///|
fn decode_text_op(
  prop : Int,
  value : LoroOpValue,
  delete_ids : Array[LoroDeleteStartId],
  delete_index : Int,
  peers : Array[@types.PeerID],
) -> Result[(@op.RawOpContent, Int), @types.LoroError] {
  let pos = prop
  match value {
    LoroOpValue::Str(text) => {
      let slice = @op.ListSlice::from_str(text)
      let op = @op.ListOp::Insert(slice~, pos~)
      Ok((@op.RawOpContent::List(op), delete_index))
    }
    LoroOpValue::DeleteSeq => {
      if delete_index >= delete_ids.length() {
        return Err(@types.LoroError::DecodeError("delete id underrun"))
      }
      let entry = delete_ids[delete_index]
      let peer_index = entry.peer_idx
      if peer_index < 0 || peer_index >= peers.length() {
        return Err(@types.LoroError::DecodeError("invalid delete peer index"))
      }
      let id_start = @types.ID::new(peers[peer_index], entry.counter)
      let span = @op.DeleteSpanWithId::new(id_start, pos, entry.len)
      Ok((@op.RawOpContent::List(@op.ListOp::Delete(span)), delete_index + 1))
    }
    LoroOpValue::MarkStart(mark) => {
      let op = @op.ListOp::StyleStart(
        start=pos,
        end=pos + mark.len,
        key=mark.key,
        info=mark.info.to_int(),
        value=mark.value,
      )
      Ok((@op.RawOpContent::List(op), delete_index))
    }
    LoroOpValue::Null =>
      Ok((@op.RawOpContent::List(@op.ListOp::StyleEnd), delete_index))
    _ => Err(@types.LoroError::DecodeError("invalid text op value"))
  }
}

///|
fn decode_tree_op(
  _container_id : @types.ContainerID,
  value : LoroOpValue,
  peers : Array[@types.PeerID],
  positions : Array[Bytes],
  op_id : @types.ID,
  delete_index : Int,
) -> Result[(@op.RawOpContent, Int), @types.LoroError] {
  match value {
    LoroOpValue::RawTreeMove(tree_move) => {
      if tree_move.subject_peer_idx < 0 ||
        tree_move.subject_peer_idx >= peers.length() {
        return Err(@types.LoroError::DecodeError("invalid tree peer index"))
      }
      let subject = @types.TreeID::new(
        peers[tree_move.subject_peer_idx],
        tree_move.subject_cnt,
      )
      let parent = if tree_move.is_parent_null {
        None
      } else {
        if tree_move.parent_peer_idx < 0 ||
          tree_move.parent_peer_idx >= peers.length() {
          return Err(@types.LoroError::DecodeError("invalid tree parent index"))
        }
        Some(
          @types.TreeID::new(
            peers[tree_move.parent_peer_idx],
            tree_move.parent_cnt,
          ),
        )
      }
      if parent is Some(p) && p.is_deleted_root() {
        let op = @op.TreeOp::Delete(target=subject)
        return Ok((@op.RawOpContent::Tree(op), delete_index))
      }
      if tree_move.position_idx < 0 ||
        tree_move.position_idx >= positions.length() {
        return Err(@types.LoroError::DecodeError("invalid tree position index"))
      }
      let position = @types.FractionalIndex::from_bytes(
        positions[tree_move.position_idx],
      )
      let op = if subject.id() == op_id {
        @op.TreeOp::Create(
          target=subject,
          parent=@types.TreeParentId::from_option(parent),
          position~,
        )
      } else {
        @op.TreeOp::Move(
          target=subject,
          parent=@types.TreeParentId::from_option(parent),
          position~,
        )
      }
      Ok((@op.RawOpContent::Tree(op), delete_index))
    }
    _ => Err(@types.LoroError::DecodeError("invalid tree op value"))
  }
}

///|
fn read_encoded_block(
  bytes : Bytes,
) -> Result[LoroEncodedBlock, @types.LoroError] {
  let reader = PostcardReader::new(bytes)
  let counter_start = match reader.read_varint_u32() {
    Ok(v) => v.reinterpret_as_int()
    Err(err) => return Err(err)
  }
  let counter_len = match reader.read_varint_u32() {
    Ok(v) => v.reinterpret_as_int()
    Err(err) => return Err(err)
  }
  let lamport_start = match reader.read_varint_u32() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let lamport_len = match reader.read_varint_u32() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let n_changes = match reader.read_varint_u32() {
    Ok(v) => v.reinterpret_as_int()
    Err(err) => return Err(err)
  }
  let header = match reader.read_bytes_with_len() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let change_meta = match reader.read_bytes_with_len() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let cids = match reader.read_bytes_with_len() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let keys = match reader.read_bytes_with_len() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let positions = match reader.read_bytes_with_len() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let ops = match reader.read_bytes_with_len() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let delete_start_ids = match reader.read_bytes_with_len() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let values = match reader.read_bytes_with_len() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if reader.remaining() != 0 {
    return Err(@types.LoroError::DecodeError("encoded block trailing bytes"))
  }
  Ok(LoroEncodedBlock::{
    counter_start,
    counter_len,
    lamport_start,
    lamport_len,
    n_changes,
    header,
    change_meta,
    cids,
    keys,
    positions,
    ops,
    delete_start_ids,
    values,
  })
}

///|
fn decode_changes_header(
  bytes : Bytes,
  n_changes : Int,
  counter_start : Int,
  counter_len : Int,
  lamport_start : @types.Lamport,
  lamport_len : @types.Lamport,
) -> Result[LoroChangesHeader, @types.LoroError] {
  let reader = LoroValueReader::new(bytes)
  let peer_num = match reader.read_usize() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if peer_num <= 0 {
    return Err(@types.LoroError::DecodeError("empty peer list"))
  }
  let peers : Array[@types.PeerID] = []
  for i = 0; i < peer_num; i = i + 1 {
    let peer_bytes = match reader.read_raw_bytes(8) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    let peer = peer_bytes[0].to_uint64() |
      (peer_bytes[1].to_uint64() << 8) |
      (peer_bytes[2].to_uint64() << 16) |
      (peer_bytes[3].to_uint64() << 24) |
      (peer_bytes[4].to_uint64() << 32) |
      (peer_bytes[5].to_uint64() << 40) |
      (peer_bytes[6].to_uint64() << 48) |
      (peer_bytes[7].to_uint64() << 56)
    peers.push(peer)
  }
  let lengths : Array[Int] = []
  let mut sum = 0
  if n_changes > 1 {
    for _i = 0; _i < n_changes - 1; _i = _i + 1 {
      let len = match reader.read_usize() {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      lengths.push(len)
      sum = sum + len
    }
  }
  lengths.push(counter_len - sum)
  let rest = reader.remaining_bytes()
  let (dep_self, rest) = match take_n_bool_rle(rest, n_changes) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let (deps_len, rest) = match take_n_any_rle_usize(rest, n_changes) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let mut other_dep_num = 0
  for len in deps_len {
    if len < 0 {
      return Err(@types.LoroError::DecodeError("invalid dep length"))
    }
    other_dep_num = other_dep_num + len
  }
  let (dep_peers, rest) = match take_n_any_rle_usize(rest, other_dep_num) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let (dep_counters, rest) = match
    take_n_delta_of_delta_u32(rest, other_dep_num) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let (lamports_raw, rest) = match
    take_n_delta_of_delta_u32(
      rest,
      if n_changes > 0 {
        n_changes - 1
      } else {
        0
      },
    ) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if rest.length() != 0 {
    return Err(@types.LoroError::DecodeError("header trailing bytes"))
  }
  let deps_groups : Array[@types.Frontiers] = []
  let mut dep_peer_index = 0
  let mut dep_counter_index = 0
  let mut current_counter = counter_start
  for i = 0; i < n_changes; i = i + 1 {
    let f = @types.Frontiers::new()
    if dep_self[i] {
      f.push(@types.ID::new(peers[0], current_counter - 1))
    }
    let len = deps_len[i]
    for _j = 0; _j < len; _j = _j + 1 {
      let peer_idx = dep_peers[dep_peer_index]
      dep_peer_index = dep_peer_index + 1
      if peer_idx < 0 || peer_idx >= peers.length() {
        return Err(@types.LoroError::DecodeError("invalid dep peer index"))
      }
      let counter = dep_counters[dep_counter_index]
      dep_counter_index = dep_counter_index + 1
      f.push(@types.ID::new(peers[peer_idx], counter))
    }
    deps_groups.push(f)
    current_counter = current_counter + lengths[i]
  }
  let counters : Array[Int] = []
  let mut last = counter_start
  for len in lengths {
    counters.push(last)
    last = last + len
  }
  counters.push(counter_start + counter_len)
  let lamports : Array[@types.Lamport] = []
  for val in lamports_raw {
    lamports.push(val.reinterpret_as_uint())
  }
  if n_changes > 0 {
    let last_len = lengths[lengths.length() - 1]
    let last_lamport = lamport_start +
      lamport_len -
      last_len.reinterpret_as_uint()
    lamports.push(last_lamport)
  }
  Ok(LoroChangesHeader::{
    peer: peers[0],
    counter: counter_start,
    n_changes,
    peers,
    counters,
    lamports,
    deps_groups,
  })
}

///|
fn decode_change_meta(
  bytes : Bytes,
  n_changes : Int,
) -> Result[(Array[Int64], Array[String?]), @types.LoroError] {
  let (timestamps, rest) = match take_n_delta_of_delta_i64(bytes, n_changes) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let (msg_lens, rest) = match take_n_any_rle_u32(rest, n_changes) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let messages : Array[String?] = []
  let mut idx = 0
  for len in msg_lens {
    if len == 0 {
      messages.push(None)
    } else {
      let end = idx + len
      if end > rest.length() {
        return Err(@types.LoroError::DecodeError("commit msg overrun"))
      }
      let bytes = rest.sub(start=idx, end~).to_bytes()
      let view = bytes[:]
      let msg = @encoding/utf8.decode(view) catch {
        _ =>
          return Err(@types.LoroError::DecodeError("invalid commit msg utf8"))
      }
      messages.push(Some(msg))
      idx = end
    }
  }
  Ok((timestamps, messages))
}

///|
fn decode_columnar_vec_columns(
  bytes : Bytes,
  expected_cols : Int,
) -> Result[Array[Bytes], @types.LoroError] {
  let reader = PostcardReader::new(bytes)
  let field_len = match reader.read_varint_usize() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if field_len != 1 {
    return Err(
      @types.LoroError::DecodeError("columnar vec field count mismatch"),
    )
  }
  let col_count = match reader.read_varint_usize() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if col_count != expected_cols {
    return Err(@types.LoroError::DecodeError("columnar column count mismatch"))
  }
  let columns : Array[Bytes] = []
  for _i = 0; _i < col_count; _i = _i + 1 {
    let col = match reader.read_bytes_with_len() {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    columns.push(col)
  }
  if reader.remaining() != 0 {
    return Err(@types.LoroError::DecodeError("columnar trailing bytes"))
  }
  Ok(columns)
}

///|
fn decode_encoded_ops(
  bytes : Bytes,
) -> Result[Array[LoroEncodedOp], @types.LoroError] {
  if bytes.length() == 0 {
    return Ok([])
  }
  let columns = match decode_columnar_vec_columns(bytes, 4) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let container_index = match decode_delta_rle_u32(columns[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let props = match decode_delta_rle_i32(columns[1]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let value_types = match decode_rle_u8(columns[2]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let lens = match decode_rle_u32(columns[3]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let count = container_index.length()
  if props.length() != count ||
    value_types.length() != count ||
    lens.length() != count {
    return Err(@types.LoroError::DecodeError("encoded ops length mismatch"))
  }
  let out : Array[LoroEncodedOp] = []
  for i = 0; i < count; i = i + 1 {
    out.push(LoroEncodedOp::{
      container_index: container_index[i],
      prop: props[i],
      value_type: value_types[i],
      len: lens[i],
    })
  }
  Ok(out)
}

///|
fn decode_delete_start_ids(
  bytes : Bytes,
) -> Result[Array[LoroDeleteStartId], @types.LoroError] {
  if bytes.length() == 0 {
    return Ok([])
  }
  let columns = match decode_columnar_vec_columns(bytes, 3) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let peer_idx = match decode_delta_rle_usize(columns[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let counters = match decode_delta_rle_i32(columns[1]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let lens = match decode_delta_rle_i32(columns[2]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let count = peer_idx.length()
  if counters.length() != count || lens.length() != count {
    return Err(@types.LoroError::DecodeError("delete ids length mismatch"))
  }
  let out : Array[LoroDeleteStartId] = []
  for i = 0; i < count; i = i + 1 {
    out.push(LoroDeleteStartId::{
      peer_idx: peer_idx[i],
      counter: counters[i],
      len: lens[i],
    })
  }
  Ok(out)
}

///|
