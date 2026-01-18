///|
fn add_key(
  keys_map : Map[String, Int],
  keys : Array[String],
  key : String,
) -> Unit {
  match keys_map.get(key) {
    Some(_) => ()
    None => {
      keys_map[key] = keys.length()
      keys.push(key)
    }
  }
}

///|
fn collect_keys_from_value(
  keys_map : Map[String, Int],
  keys : Array[String],
  value : @types.LoroValue,
) -> Unit {
  match value {
    @types.LoroValue::Map(map) =>
      for key, item in map {
        add_key(keys_map, keys, key)
        collect_keys_from_value(keys_map, keys, item)
      }
    @types.LoroValue::List(items) =>
      for item in items {
        collect_keys_from_value(keys_map, keys, item)
      }
    _ => ()
  }
}

///|
fn add_peer(peers : Map[@types.PeerID, Bool], peer : @types.PeerID) -> Unit {
  peers[peer] = true
}

///|
fn ensure_container(
  containers_map : Map[@types.ContainerID, Int],
  containers : Array[@types.ContainerID],
  id : @types.ContainerID,
) -> Unit {
  match containers_map.get(id) {
    Some(_) => ()
    None => {
      containers_map[id] = containers.length()
      containers.push(id)
    }
  }
}

///|
fn ensure_position(
  positions : Array[Bytes],
  position : @types.FractionalIndex,
) -> Unit {
  let bytes = position.bytes()
  for existing in positions {
    if existing == bytes {
      return
    }
  }
  positions.push(bytes)
}

///|
fn key_index_from_map(
  keys_map : Map[String, Int],
  key : String,
) -> Result[Int, @types.LoroError] {
  match keys_map.get(key) {
    Some(v) => Ok(v)
    None => Err(@types.LoroError::EncodeError("missing key index"))
  }
}

///|
fn peer_index(
  peer_map : Map[@types.PeerID, Int],
  peer : @types.PeerID,
) -> Result[Int, @types.LoroError] {
  match peer_map.get(peer) {
    Some(v) => Ok(v)
    None => Err(@types.LoroError::EncodeError("missing peer index"))
  }
}

///|
fn collect_from_op(
  arena : @arena.SharedArena,
  op : @op.Op,
  keys_map : Map[String, Int],
  keys : Array[String],
  peers : Map[@types.PeerID, Bool],
  containers_map : Map[@types.ContainerID, Int],
  containers : Array[@types.ContainerID],
  positions : Array[Bytes],
) -> Result[Unit, @types.LoroError] {
  let container = op.container()
  ensure_container(containers_map, containers, container)
  match container {
    @types.ContainerID::Root(name~, container_type=_) =>
      add_key(keys_map, keys, name)
    _ => ()
  }
  match (container.container_type(), op.content()) {
    (@types.ContainerType::Map, @op.InnerContent::Map(map_set)) => {
      add_key(keys_map, keys, map_set.key())
      match map_set.value() {
        Some(value) => collect_keys_from_value(keys_map, keys, value)
        None => ()
      }
      Ok(())
    }
    (@types.ContainerType::List, @op.InnerContent::List(list_op)) =>
      match list_op {
        @op.InnerListOp::Insert(slice~, pos=_) => {
          if slice.is_unknown() {
            return Err(
              @types.LoroError::EncodeError("list slice missing values"),
            )
          }
          let values = arena.get_values(slice)
          for value in values {
            collect_keys_from_value(keys_map, keys, value)
          }
          Ok(())
        }
        @op.InnerListOp::Delete(span) => {
          add_peer(peers, span.id_start().peer)
          Ok(())
        }
        @op.InnerListOp::Move(from=_, elem_id~, to=_) => {
          add_peer(peers, elem_id.peer)
          Ok(())
        }
        @op.InnerListOp::Set(elem_id~, value~) => {
          add_peer(peers, elem_id.peer)
          collect_keys_from_value(keys_map, keys, value)
          Ok(())
        }
        _ => Ok(())
      }
    (@types.ContainerType::MovableList, @op.InnerContent::List(list_op)) =>
      match list_op {
        @op.InnerListOp::Insert(slice~, pos=_) => {
          if slice.is_unknown() {
            return Err(
              @types.LoroError::EncodeError("movable list slice missing values"),
            )
          }
          let values = arena.get_values(slice)
          for value in values {
            collect_keys_from_value(keys_map, keys, value)
          }
          Ok(())
        }
        @op.InnerListOp::Delete(span) => {
          add_peer(peers, span.id_start().peer)
          Ok(())
        }
        @op.InnerListOp::Move(from=_, elem_id~, to=_) => {
          add_peer(peers, elem_id.peer)
          Ok(())
        }
        @op.InnerListOp::Set(elem_id~, value~) => {
          add_peer(peers, elem_id.peer)
          collect_keys_from_value(keys_map, keys, value)
          Ok(())
        }
        _ => Ok(())
      }
    (
      @types.ContainerType::Text
      | @types.ContainerType::RichText,
      @op.InnerContent::List(list_op),
    ) =>
      match list_op {
        @op.InnerListOp::Delete(span) => {
          add_peer(peers, span.id_start().peer)
          Ok(())
        }
        @op.InnerListOp::StyleStart(start=_, end=_, key~, info=_, value~) => {
          add_key(keys_map, keys, key)
          collect_keys_from_value(keys_map, keys, value)
          Ok(())
        }
        _ => Ok(())
      }
    (@types.ContainerType::Tree, @op.InnerContent::Tree(tree_op)) =>
      match tree_op {
        @op.TreeOp::Create(target~, parent~, position~) => {
          add_peer(peers, target.peer)
          match parent {
            @types.TreeParentId::Root => ()
            @types.TreeParentId::Deleted =>
              add_peer(peers, @types.TreeID::delete_root().peer)
            @types.TreeParentId::Node(parent_id) =>
              add_peer(peers, parent_id.peer)
          }
          ensure_position(positions, position)
          Ok(())
        }
        @op.TreeOp::Move(target~, parent~, position~) => {
          add_peer(peers, target.peer)
          match parent {
            @types.TreeParentId::Root => ()
            @types.TreeParentId::Deleted =>
              add_peer(peers, @types.TreeID::delete_root().peer)
            @types.TreeParentId::Node(parent_id) =>
              add_peer(peers, parent_id.peer)
          }
          ensure_position(positions, position)
          Ok(())
        }
        @op.TreeOp::Delete(target~) => {
          add_peer(peers, target.peer)
          add_peer(peers, @types.TreeID::delete_root().peer)
          Ok(())
        }
      }
    _ => Ok(())
  }
}

///|
fn encode_columnar_vec_columns(columns : Array[Bytes]) -> Bytes {
  let writer = PostcardWriter::new()
  writer.write_varint_usize(1)
  writer.write_varint_usize(columns.length())
  for col in columns {
    writer.write_bytes_with_len(col)
  }
  writer.to_bytes()
}

///|
fn encode_change_meta(
  timestamps : Array[Int64],
  messages : Array[String?],
) -> Bytes {
  let buf = @buffer.new()
  buf.write_bytes(encode_delta_of_delta_i64(timestamps))
  let msg_lens : Array[Int] = []
  let msg_bytes = @buffer.new()
  for msg in messages {
    match msg {
      None => msg_lens.push(0)
      Some(text) => {
        let bytes = @encoding/utf8.encode(text)
        msg_lens.push(bytes.length())
        msg_bytes.write_bytes(bytes)
      }
    }
  }
  buf.write_bytes(encode_rle_u32(msg_lens))
  buf.write_bytes(msg_bytes.to_bytes())
  buf.to_bytes()
}

///|
fn encode_changes_header(
  peers : Array[@types.PeerID],
  lengths : Array[Int],
  dep_self : Array[Bool],
  deps_len : Array[Int],
  dep_peers : Array[Int],
  dep_counters : Array[Int],
  lamports : Array[@types.Lamport],
) -> Bytes {
  let header = LoroValueWriter::new()
  header.write_usize(peers.length())
  for peer in peers {
    let bytes : Array[Byte] = [
      (peer & 0xFFUL).to_int().to_byte(),
      ((peer >> 8) & 0xFFUL).to_int().to_byte(),
      ((peer >> 16) & 0xFFUL).to_int().to_byte(),
      ((peer >> 24) & 0xFFUL).to_int().to_byte(),
      ((peer >> 32) & 0xFFUL).to_int().to_byte(),
      ((peer >> 40) & 0xFFUL).to_int().to_byte(),
      ((peer >> 48) & 0xFFUL).to_int().to_byte(),
      ((peer >> 56) & 0xFFUL).to_int().to_byte(),
    ]
    header.write_raw_bytes(Bytes::from_array(bytes))
  }
  if lengths.length() > 1 {
    for i = 0; i < lengths.length() - 1; i = i + 1 {
      header.write_usize(lengths[i])
    }
  }
  let tail = @buffer.new()
  tail.write_bytes(encode_bool_rle(dep_self))
  tail.write_bytes(encode_rle_u32(deps_len))
  tail.write_bytes(encode_rle_u32(dep_peers))
  tail.write_bytes(encode_delta_of_delta_u32(dep_counters))
  let lamport_raw : Array[Int] = []
  if lamports.length() > 1 {
    for i = 0; i < lamports.length() - 1; i = i + 1 {
      lamport_raw.push(lamports[i].reinterpret_as_int())
    }
  }
  tail.write_bytes(encode_delta_of_delta_u32(lamport_raw))
  header.write_raw_bytes(tail.to_bytes())
  header.to_bytes()
}

///|
fn build_peer_index_map(
  peers : Array[@types.PeerID],
) -> Map[@types.PeerID, Int] {
  let out : Map[@types.PeerID, Int] = {}
  for i = 0; i < peers.length(); i = i + 1 {
    out[peers[i]] = i
  }
  out
}

///|
fn encode_block_for_peer(
  arena : @arena.SharedArena,
  peer : @types.PeerID,
  changes : Array[@oplog.Change],
) -> Result[Bytes, @types.LoroError] {
  let keys_map : Map[String, Int] = {}
  let keys : Array[String] = []
  let containers_map : Map[@types.ContainerID, Int] = {}
  let containers : Array[@types.ContainerID] = []
  let positions : Array[Bytes] = []
  let peers_set : Map[@types.PeerID, Bool] = {}
  peers_set[peer] = true
  for change in changes {
    for dep in change.deps().iter() {
      add_peer(peers_set, dep.peer)
    }
    for op in change.ops() {
      match
        collect_from_op(
          arena, op, keys_map, keys, peers_set, containers_map, containers, positions,
        ) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
    }
  }
  let other_peers : Array[@types.PeerID] = []
  for id, _ in peers_set {
    if id != peer {
      other_peers.push(id)
    }
  }
  other_peers.sort_by((a, b) => if a < b { -1 } else if a > b { 1 } else { 0 })
  let peers : Array[@types.PeerID] = [peer]
  for id in other_peers {
    peers.push(id)
  }
  let peer_map = build_peer_index_map(peers)
  let counter_start = changes[0].id().counter
  let lengths : Array[Int] = []
  let lamports : Array[@types.Lamport] = []
  let timestamps : Array[Int64] = []
  let commit_msgs : Array[String?] = []
  let mut expected_counter = counter_start
  for change in changes {
    if change.id().counter != expected_counter {
      return Err(
        @types.LoroError::EncodeError("non-contiguous change counters"),
      )
    }
    lengths.push(change.len())
    lamports.push(change.lamport())
    timestamps.push(change.timestamp())
    commit_msgs.push(change.commit_msg())
    expected_counter = expected_counter + change.len()
  }
  let mut counter_len = 0
  for len in lengths {
    counter_len = counter_len + len
  }
  let last_len = lengths[lengths.length() - 1]
  let lamport_start = lamports[0]
  let last_lamport = lamports[lamports.length() - 1]
  let lamport_end = last_lamport + last_len.reinterpret_as_uint()
  let lamport_len = lamport_end - lamport_start
  let dep_self : Array[Bool] = []
  let deps_len : Array[Int] = []
  let dep_peers : Array[Int] = []
  let dep_counters : Array[Int] = []
  let mut current_counter = counter_start
  for i = 0; i < changes.length(); i = i + 1 {
    let change = changes[i]
    let deps = change.deps().clone()
    let mut uses_self = false
    if current_counter > 0 {
      let prev_id = @types.ID::new(peer, current_counter - 1)
      if deps.contains(prev_id) {
        uses_self = true
        deps.remove(prev_id)
      }
    }
    dep_self.push(uses_self)
    let others : Array[@types.ID] = []
    for dep in deps.iter() {
      others.push(dep)
    }
    others.sort_by((a, b) => if a.peer < b.peer {
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
    deps_len.push(others.length())
    for dep in others {
      let idx = match peer_index(peer_map, dep.peer) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      dep_peers.push(idx)
      dep_counters.push(dep.counter)
    }
    current_counter = current_counter + lengths[i]
  }
  let header = encode_changes_header(
    peers, lengths, dep_self, deps_len, dep_peers, dep_counters, lamports,
  )
  let change_meta = encode_change_meta(timestamps, commit_msgs)
  let cids = match encode_container_arena(containers, keys, peers) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let keys_bytes = encode_keys(keys)
  let positions_bytes = encode_positions(positions)
  let values_writer = LoroValueWriter::new()
  let encoded_ops : Array[LoroEncodedOp] = []
  let delete_ids : Array[LoroDeleteStartId] = []
  for change in changes {
    for op in change.ops() {
      let container = op.container()
      let container_index = match containers_map.get(container) {
        Some(v) => v
        None =>
          return Err(@types.LoroError::EncodeError("missing container index"))
      }
      let op_len = op.content_len()
      let op_id = @types.ID::new(peer, op.counter)
      let (prop, value) = match (container.container_type(), op.content()) {
        (@types.ContainerType::Map, @op.InnerContent::Map(map_set)) => {
          let key_idx = match key_index_from_map(keys_map, map_set.key()) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          match map_set.value() {
            None => (key_idx, LoroOpValue::DeleteOnce)
            Some(val) => (key_idx, LoroOpValue::LoroValue(val))
          }
        }
        (@types.ContainerType::List, @op.InnerContent::List(list_op)) =>
          match list_op {
            @op.InnerListOp::Insert(slice~, pos~) => {
              if slice.is_unknown() {
                return Err(
                  @types.LoroError::EncodeError("list slice missing values"),
                )
              }
              let values = arena.get_values(slice)
              let value = @types.LoroValue::List(values)
              (pos, LoroOpValue::LoroValue(value))
            }
            @op.InnerListOp::Delete(span) => {
              let idx = match peer_index(peer_map, span.id_start().peer) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              delete_ids.push(LoroDeleteStartId::{
                peer_idx: idx,
                counter: span.id_start().counter,
                len: span.span().len(),
              })
              (span.span().pos(), LoroOpValue::DeleteSeq)
            }
            @op.InnerListOp::Set(elem_id~, value~) => {
              let idx = match peer_index(peer_map, elem_id.peer) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              (
                0,
                LoroOpValue::ListSet(
                  peer_idx=idx,
                  lamport=elem_id.lamport,
                  value~,
                ),
              )
            }
            _ =>
              return Err(@types.LoroError::EncodeError("unsupported list op"))
          }
        (@types.ContainerType::MovableList, @op.InnerContent::List(list_op)) =>
          match list_op {
            @op.InnerListOp::Insert(slice~, pos~) => {
              if slice.is_unknown() {
                return Err(
                  @types.LoroError::EncodeError(
                    "movable list slice missing values",
                  ),
                )
              }
              let values = arena.get_values(slice)
              let value = @types.LoroValue::List(values)
              (pos, LoroOpValue::LoroValue(value))
            }
            @op.InnerListOp::Delete(span) => {
              let idx = match peer_index(peer_map, span.id_start().peer) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              delete_ids.push(LoroDeleteStartId::{
                peer_idx: idx,
                counter: span.id_start().counter,
                len: span.span().len(),
              })
              (span.span().pos(), LoroOpValue::DeleteSeq)
            }
            @op.InnerListOp::Move(from~, elem_id~, to~) => {
              let idx = match peer_index(peer_map, elem_id.peer) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              (
                to,
                LoroOpValue::ListMove(
                  from~,
                  from_idx=idx,
                  lamport=elem_id.lamport,
                ),
              )
            }
            @op.InnerListOp::Set(elem_id~, value~) => {
              let idx = match peer_index(peer_map, elem_id.peer) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              (
                0,
                LoroOpValue::ListSet(
                  peer_idx=idx,
                  lamport=elem_id.lamport,
                  value~,
                ),
              )
            }
            _ =>
              return Err(
                @types.LoroError::EncodeError("unsupported movable list op"),
              )
          }
        (
          @types.ContainerType::Text
          | @types.ContainerType::RichText,
          @op.InnerContent::List(list_op),
        ) =>
          match list_op {
            @op.InnerListOp::InsertText(
              str~,
              unicode_len=_,
              pos~,
              unicode_start=_
            ) => (pos, LoroOpValue::Str(str))
            @op.InnerListOp::Delete(span) => {
              let idx = match peer_index(peer_map, span.id_start().peer) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              delete_ids.push(LoroDeleteStartId::{
                peer_idx: idx,
                counter: span.id_start().counter,
                len: span.span().len(),
              })
              (span.span().pos(), LoroOpValue::DeleteSeq)
            }
            @op.InnerListOp::StyleStart(start~, end~, key~, info~, value~) => {
              let mark = LoroMarkStart::{
                len: end - start,
                key,
                value,
                info: info.to_byte(),
              }
              (start, LoroOpValue::MarkStart(mark))
            }
            @op.InnerListOp::StyleEnd => (0, LoroOpValue::Null)
            _ =>
              return Err(@types.LoroError::EncodeError("unsupported text op"))
          }
        (@types.ContainerType::Tree, @op.InnerContent::Tree(tree_op)) => {
          let (parent_opt, position_opt) = match tree_op {
            @op.TreeOp::Create(target=_, parent~, position~) =>
              (parent, Some(position))
            @op.TreeOp::Move(target=_, parent~, position~) =>
              (parent, Some(position))
            @op.TreeOp::Delete(target=_) =>
              (@types.TreeParentId::deleted(), None)
          }
          let subject = tree_op.target()
          let subject_idx = match peer_index(peer_map, subject.peer) {
            Ok(v) => v
            Err(err) => return Err(err)
          }
          let (is_parent_null, parent_idx, parent_cnt) = match parent_opt {
            @types.TreeParentId::Root => (true, 0, 0)
            @types.TreeParentId::Deleted => {
              let deleted = @types.TreeID::delete_root()
              let idx = match peer_index(peer_map, deleted.peer) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              (false, idx, deleted.counter)
            }
            @types.TreeParentId::Node(parent_id) => {
              let idx = match peer_index(peer_map, parent_id.peer) {
                Ok(v) => v
                Err(err) => return Err(err)
              }
              (false, idx, parent_id.counter)
            }
          }
          let mut position_idx = 0
          match position_opt {
            Some(pos) => {
              let bytes = pos.bytes()
              let mut found = None
              for i = 0; i < positions.length(); i = i + 1 {
                if positions[i] == bytes {
                  found = Some(i)
                  break
                }
              }
              match found {
                Some(i) => position_idx = i
                None =>
                  return Err(
                    @types.LoroError::EncodeError("missing tree position"),
                  )
              }
            }
            None => ()
          }
          let raw_move = LoroRawTreeMove::{
            subject_peer_idx: subject_idx,
            subject_cnt: subject.counter,
            position_idx,
            is_parent_null,
            parent_peer_idx: parent_idx,
            parent_cnt,
          }
          (0, LoroOpValue::RawTreeMove(raw_move))
        }
        (@types.ContainerType::Counter, @op.InnerContent::Counter(counter_op)) =>
          (0, LoroOpValue::F64(counter_op.delta()))
        _ => return Err(@types.LoroError::EncodeError("unsupported op content"))
      }
      let value_type = match values_writer.write_op_value(value, keys, op_id) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      encoded_ops.push(LoroEncodedOp::{
        container_index,
        prop,
        value_type,
        len: op_len,
      })
    }
  }
  let container_col : Array[Int] = []
  let prop_col : Array[Int] = []
  let value_type_col : Array[Byte] = []
  let len_col : Array[Int] = []
  for op in encoded_ops {
    container_col.push(op.container_index)
    prop_col.push(op.prop)
    value_type_col.push(op.value_type)
    len_col.push(op.len)
  }
  let ops_bytes = encode_columnar_vec_columns([
    encode_delta_rle_u32(container_col),
    encode_delta_rle_i32(prop_col),
    encode_rle_u8(value_type_col),
    encode_rle_u32(len_col),
  ])
  let delete_bytes = if delete_ids.length() == 0 {
    b""
  } else {
    let peer_idx_col : Array[Int] = []
    let counter_col : Array[Int] = []
    let len_col2 : Array[Int] = []
    for entry in delete_ids {
      peer_idx_col.push(entry.peer_idx)
      counter_col.push(entry.counter)
      len_col2.push(entry.len)
    }
    encode_columnar_vec_columns([
      encode_delta_rle_usize(peer_idx_col),
      encode_delta_rle_i32(counter_col),
      encode_delta_rle_i32(len_col2),
    ])
  }
  let block = LoroEncodedBlock::{
    counter_start,
    counter_len,
    lamport_start,
    lamport_len,
    n_changes: changes.length(),
    header,
    change_meta,
    cids,
    keys: keys_bytes,
    positions: positions_bytes,
    ops: ops_bytes,
    delete_start_ids: delete_bytes,
    values: values_writer.to_bytes(),
  }
  let writer = PostcardWriter::new()
  writer.write_varint_u32(block.counter_start.reinterpret_as_uint())
  writer.write_varint_u32(block.counter_len.reinterpret_as_uint())
  writer.write_varint_u32(block.lamport_start)
  writer.write_varint_u32(block.lamport_len)
  writer.write_varint_u32(block.n_changes.reinterpret_as_uint())
  writer.write_bytes_with_len(block.header)
  writer.write_bytes_with_len(block.change_meta)
  writer.write_bytes_with_len(block.cids)
  writer.write_bytes_with_len(block.keys)
  writer.write_bytes_with_len(block.positions)
  writer.write_bytes_with_len(block.ops)
  writer.write_bytes_with_len(block.delete_start_ids)
  writer.write_bytes_with_len(block.values)
  Ok(writer.to_bytes())
}

///|
pub fn encode_loro_updates_body(
  arena : @arena.SharedArena,
  changes : Array[@oplog.Change],
) -> Result[Bytes, @types.LoroError] {
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
  let writer = LoroValueWriter::new()
  for p in peers {
    match by_peer.get(p) {
      Some(group) => {
        group.sort_by((a, b) => if a.id().counter < b.id().counter {
          -1
        } else if a.id().counter > b.id().counter {
          1
        } else {
          0
        })
        let block = match encode_block_for_peer(arena, p, group) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        writer.write_usize(block.length())
        writer.write_raw_bytes(block)
      }
      None => ()
    }
  }
  Ok(writer.to_bytes())
}

///|
pub fn encode_loro_updates(
  arena : @arena.SharedArena,
  changes : Array[@oplog.Change],
) -> Result[Bytes, @types.LoroError] {
  let body = match encode_loro_updates_body(arena, changes) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(build_loro_payload(body, LoroEncodeMode::FastUpdates))
}
