///|
const FRONTIERS_KEY : Bytes = b"fr"

///|
priv struct DecodedTextSpan {
  peer_idx : Int
  counter : Int
  lamport_sub : Int
  len : Int
}

///|
priv struct DecodedMark {
  key_idx : Int
  value : @types.LoroValue
  info : Int
}

///|
priv struct DecodedListIds {
  peer_idx : Array[Int]
  counter : Array[Int]
  lamport_sub : Array[Int]
}

///|
priv struct DecodedTextData {
  spans : Array[DecodedTextSpan]
  keys : Array[String]
  marks : Array[DecodedMark]
}

///|
priv struct DecodedTreeNodeId {
  peer_idx : Int
  counter : Int
}

///|
priv struct DecodedTreeNode {
  parent_idx_plus_two : Int
  last_set_peer_idx : Int
  last_set_counter : Int
  last_set_lamport_sub : Int
  fractional_index_idx : Int
}

///|
priv struct DecodedTreeData {
  node_ids : Array[DecodedTreeNodeId]
  nodes : Array[DecodedTreeNode]
  positions : Array[@types.FractionalIndex]
}

///|
priv struct MovableListItem {
  invisible_list_item : Int
  _pos_id_eq_elem_id : Bool
  _elem_id_eq_last_set_id : Bool
}

///|
priv struct MovableListId {
  peer_idx : Int
  counter : Int
  lamport_sub : Int
}

///|
priv struct MovableListElemId {
  peer_idx : Int
  lamport : Int
}

///|
priv struct MovableListSnapshot {
  items : Array[MovableListItem]
  list_item_ids : Array[MovableListId]
  elem_ids : Array[MovableListElemId]
  last_set_ids : Array[MovableListElemId]
}

///|
fn read_columnar_vec_columns(
  reader : PostcardReader,
  expected_cols : Int,
) -> Result[Array[Bytes], @types.LoroError] {
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
  Ok(columns)
}

///|

///|
pub fn decode_loro_doc_state(
  state_bytes : Bytes?,
  shallow_bytes : Bytes,
) -> Result[@state.DocState, @types.LoroError] {
  if shallow_bytes.length() > 0 {
    let base = match decode_container_store_bytes(shallow_bytes) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    match state_bytes {
      Some(bytes) => {
        let overlay = match decode_container_store_bytes(bytes) {
          Ok(v) => v
          Err(err) => return Err(err)
        }
        Ok(merge_doc_states(base, overlay))
      }
      None => Ok(base)
    }
  } else {
    match state_bytes {
      Some(bytes) => decode_container_store_bytes(bytes)
      None => Ok(@state.DocState::new())
    }
  }
}

///|
fn merge_doc_states(
  base : @state.DocState,
  overlay : @state.DocState,
) -> @state.DocState {
  for entry in overlay.container_items() {
    match entry {
      (id, state) => base.set_container_state(id, state)
    }
  }
  base
}

///|
fn decode_container_store_bytes(
  bytes : Bytes,
) -> Result[@state.DocState, @types.LoroError] {
  let entries = match decode_kv_store(bytes) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let state = @state.DocState::new()
  for entry in entries {
    if entry.key == FRONTIERS_KEY {
      continue
    }
    let id = match decode_container_id_key(entry.key) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    match decode_container_entry(state, id, entry.value) {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
  }
  Ok(state)
}

///|
fn decode_container_id_key(
  bytes : Bytes,
) -> Result[@types.ContainerID, @types.LoroError] {
  if bytes.length() == 0 {
    return Err(@types.LoroError::DecodeError("empty container id"))
  }
  let reader = LoroValueReader::new(bytes)
  let first = match reader.read_u8() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let is_root = (first.to_uint() & 0x80U) != 0U
  let kind = (first.to_uint() & 0x7FU).to_byte()
  let container_type = loro_container_type_from_u8(kind)
  if is_root {
    let name_len = match reader.read_usize() {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    let name_bytes = match reader.read_raw_bytes(name_len) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    let view = name_bytes[:]
    let name = @encoding/utf8.decode(view) catch {
      _ => return Err(@types.LoroError::DecodeError("invalid container name"))
    }
    Ok(@types.ContainerID::root(name, container_type))
  } else {
    let peer_bytes = match reader.read_raw_bytes(8) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    let counter_bytes = match reader.read_raw_bytes(4) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    let peer = match read_u64_le_at(peer_bytes, 0) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    let counter = match read_i32_le_at(counter_bytes, 0) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    Ok(@types.ContainerID::normal(peer, counter, container_type))
  }
}

///|
fn decode_container_entry(
  state : @state.DocState,
  id : @types.ContainerID,
  bytes : Bytes,
) -> Result[Unit, @types.LoroError] {
  let reader = PostcardReader::new(bytes)
  let _kind = match reader.read_u8() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let _depth = match reader.read_varint_usize() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let _parent = match reader.read_option_container_id() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let state_bytes = reader.remaining_bytes()
  let container_type = id.container_type()
  match container_type {
    @types.ContainerType::Map => {
      let map_state = match decode_map_state_snapshot(state_bytes) {
        Ok(v) => v
        Err(err) =>
          return Err(
            @types.LoroError::DecodeError("map \{id} decode failed: \{err}"),
          )
      }
      state.set_map_state(id, map_state)
      Ok(())
    }
    @types.ContainerType::List => {
      let list_state = match decode_list_state_snapshot(state_bytes) {
        Ok(v) => v
        Err(err) =>
          return Err(
            @types.LoroError::DecodeError("list \{id} decode failed: \{err}"),
          )
      }
      state.set_list_state(id, list_state)
      Ok(())
    }
    @types.ContainerType::Text => {
      let text_state = match decode_text_state_snapshot(state_bytes) {
        Ok(v) => v
        Err(err) =>
          return Err(
            @types.LoroError::DecodeError("text \{id} decode failed: \{err}"),
          )
      }
      state.set_text_state(id, text_state)
      Ok(())
    }
    @types.ContainerType::MovableList => {
      let list_state = match decode_movable_list_state_snapshot(state_bytes) {
        Ok(v) => v
        Err(err) =>
          return Err(
            @types.LoroError::DecodeError(
              "movable list \{id} decode failed: \{err}",
            ),
          )
      }
      state.set_movable_list_state(id, list_state)
      Ok(())
    }
    @types.ContainerType::Tree => {
      let tree_state = match decode_tree_state_snapshot(state_bytes) {
        Ok(v) => v
        Err(err) =>
          return Err(
            @types.LoroError::DecodeError("tree \{id} decode failed: \{err}"),
          )
      }
      state.set_tree_state(id, tree_state)
      Ok(())
    }
    @types.ContainerType::Counter => {
      let counter_state = match decode_counter_state_snapshot(state_bytes) {
        Ok(v) => v
        Err(err) =>
          return Err(
            @types.LoroError::DecodeError("counter \{id} decode failed: \{err}"),
          )
      }
      state.set_counter_state(id, counter_state)
      Ok(())
    }
    _ => Err(@types.LoroError::DecodeError("unsupported container type"))
  }
}

///|
fn decode_map_state_snapshot(
  bytes : Bytes,
) -> Result[@state.MapState, @types.LoroError] {
  let reader = PostcardReader::new(bytes)
  let map_value = match reader.read_map_loro_value() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let keys_with_none = match reader.read_vec_string() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let peer_count = match reader.read_varint_usize() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let peers = match read_peers(reader, peer_count) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let none_map : Map[String, Bool] = {}
  for key in keys_with_none {
    none_map[key] = true
  }
  let keys : Array[String] = []
  for key, _value in map_value {
    keys.push(key)
  }
  for key, _flag in none_map {
    keys.push(key)
  }
  keys.sort_by((a, b) => if a < b { -1 } else if a > b { 1 } else { 0 })
  let state = @state.MapState::new()
  for key in keys {
    let peer_idx = match reader.read_varint_usize() {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    if peer_idx < 0 || peer_idx >= peers.length() {
      return Err(@types.LoroError::DecodeError("invalid map peer index"))
    }
    let lamport = match reader.read_varint_u32() {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    if none_map.get(key) is Some(true) {
      state.insert_entry(
        key,
        @state.MapValue::new(None, lamport, peers[peer_idx]),
      )
    } else {
      match map_value.get(key) {
        Some(value) =>
          state.insert_entry(
            key,
            @state.MapValue::new(Some(value), lamport, peers[peer_idx]),
          )
        None => return Err(@types.LoroError::DecodeError("missing map value"))
      }
    }
  }
  Ok(state)
}

///|
fn decode_list_state_snapshot(
  bytes : Bytes,
) -> Result[@state.ListState, @types.LoroError] {
  let reader = PostcardReader::new(bytes)
  let values = match reader.read_vec_loro_value() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let peer_count = match reader.read_varint_usize() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let peers = match read_peers(reader, peer_count) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let ids = match decode_list_ids(reader.remaining_bytes()) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if ids.peer_idx.length() != values.length() {
    return Err(@types.LoroError::DecodeError("list id length mismatch"))
  }
  let state = @state.ListState::new()
  for i = 0; i < values.length(); i = i + 1 {
    let peer_idx = ids.peer_idx[i]
    let counter = ids.counter[i]
    let lamport_sub = ids.lamport_sub[i]
    if peer_idx < 0 || peer_idx >= peers.length() {
      return Err(@types.LoroError::DecodeError("invalid list peer index"))
    }
    let lamport = lamport_sub + counter
    if lamport < 0 {
      return Err(@types.LoroError::DecodeError("invalid list lamport"))
    }
    let id = @types.IdFull::new(
      peers[peer_idx],
      counter,
      lamport.reinterpret_as_uint(),
    )
    state.append_elem(values[i], id)
  }
  Ok(state)
}

///|
fn decode_text_state_snapshot(
  bytes : Bytes,
) -> Result[@state.TextState, @types.LoroError] {
  let reader = PostcardReader::new(bytes)
  let text = match reader.read_string() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let peer_count = match reader.read_varint_usize() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let peers = match read_peers(reader, peer_count) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let encoded = match decode_encoded_text(reader.remaining_bytes()) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let chars : Array[Char] = []
  for ch in text {
    chars.push(ch)
  }
  let state = @state.TextState::new()
  let mut pos = 0
  let mut mark_idx = 0
  let open : Map[@types.ID, @state.StyleOp] = {}
  for span in encoded.spans {
    if span.peer_idx < 0 || span.peer_idx >= peers.length() {
      return Err(@types.LoroError::DecodeError("invalid text peer index"))
    }
    let peer = peers[span.peer_idx]
    let counter = span.counter
    let lamport = span.lamport_sub + counter
    if lamport < 0 {
      return Err(@types.LoroError::DecodeError("invalid text lamport"))
    }
    if span.len > 0 {
      if pos + span.len > chars.length() {
        return Err(@types.LoroError::DecodeError("text length overrun"))
      }
      for i = 0; i < span.len; i = i + 1 {
        let id = @types.IdFull::new(
          peer,
          counter + i,
          (lamport + i).reinterpret_as_uint(),
        )
        state.append_elem(chars[pos], id)
        pos = pos + 1
      }
    } else if span.len == 0 {
      if mark_idx >= encoded.marks.length() {
        return Err(@types.LoroError::DecodeError("mark underrun"))
      }
      let mark = encoded.marks[mark_idx]
      mark_idx = mark_idx + 1
      if mark.key_idx < 0 || mark.key_idx >= encoded.keys.length() {
        return Err(@types.LoroError::DecodeError("invalid mark key index"))
      }
      let key = encoded.keys[mark.key_idx]
      let info = mark.info
      let style = @state.StyleOp::{
        id: @types.IdFull::new(peer, counter, lamport.reinterpret_as_uint()),
        key,
        value: mark.value,
        info,
      }
      open[@types.ID::new(peer, counter)] = style
      state.append_anchor(style, @state.AnchorType::Start)
    } else if span.len == -1 {
      let start_id = @types.ID::new(peer, counter - 1)
      match open.get(start_id) {
        Some(style) => {
          state.append_anchor(style, @state.AnchorType::End)
          open.remove(start_id)
        }
        None => return Err(@types.LoroError::DecodeError("missing mark start"))
      }
    } else {
      return Err(@types.LoroError::DecodeError("invalid text span"))
    }
  }
  Ok(state)
}

///|
fn decode_movable_list_state_snapshot(
  bytes : Bytes,
) -> Result[@state.MovableListState, @types.LoroError] {
  let reader = PostcardReader::new(bytes)
  let values = match reader.read_vec_loro_value() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let peer_count = match reader.read_varint_usize() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let peers = match read_peers(reader, peer_count) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let snapshot = match
    decode_movable_list_snapshot(reader.remaining_bytes(), values.length() + 1) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let state = @state.MovableListState::new()
  let mut list_item_idx = 0
  let mut elem_idx = 0
  let mut last_set_idx = 0
  let mut value_idx = 0
  let mut is_first = true
  for item in snapshot.items {
    if !is_first {
      if list_item_idx >= snapshot.list_item_ids.length() {
        return Err(@types.LoroError::DecodeError("movable list id underrun"))
      }
      if value_idx >= values.length() {
        return Err(@types.LoroError::DecodeError("movable list underrun"))
      }
      let entry = snapshot.list_item_ids[list_item_idx]
      list_item_idx = list_item_idx + 1
      if entry.peer_idx < 0 || entry.peer_idx >= peers.length() {
        return Err(@types.LoroError::DecodeError("invalid movable list peer"))
      }
      let lamport = entry.lamport_sub + entry.counter
      if lamport < 0 {
        return Err(
          @types.LoroError::DecodeError("invalid movable list lamport"),
        )
      }
      let id_full = @types.IdFull::new(
        peers[entry.peer_idx],
        entry.counter,
        lamport.reinterpret_as_uint(),
      )
      let elem_id = if item._pos_id_eq_elem_id {
        id_full.to_id_lp()
      } else {
        if elem_idx >= snapshot.elem_ids.length() {
          return Err(
            @types.LoroError::DecodeError("movable list elem id underrun"),
          )
        }
        let elem_entry = snapshot.elem_ids[elem_idx]
        elem_idx = elem_idx + 1
        if elem_entry.peer_idx < 0 || elem_entry.peer_idx >= peers.length() {
          return Err(@types.LoroError::DecodeError("invalid movable elem peer"))
        }
        if elem_entry.lamport < 0 {
          return Err(
            @types.LoroError::DecodeError("invalid movable elem lamport"),
          )
        }
        @types.IdLp::new(
          peers[elem_entry.peer_idx],
          elem_entry.lamport.reinterpret_as_uint(),
        )
      }
      let last_set_id = if item._elem_id_eq_last_set_id {
        elem_id
      } else {
        if last_set_idx >= snapshot.last_set_ids.length() {
          return Err(
            @types.LoroError::DecodeError("movable list last set underrun"),
          )
        }
        let last_entry = snapshot.last_set_ids[last_set_idx]
        last_set_idx = last_set_idx + 1
        if last_entry.peer_idx < 0 || last_entry.peer_idx >= peers.length() {
          return Err(
            @types.LoroError::DecodeError("invalid movable last set peer"),
          )
        }
        if last_entry.lamport < 0 {
          return Err(
            @types.LoroError::DecodeError("invalid movable last set lamport"),
          )
        }
        @types.IdLp::new(
          peers[last_entry.peer_idx],
          last_entry.lamport.reinterpret_as_uint(),
        )
      }
      state.append_elem_full(values[value_idx], id_full, elem_id, last_set_id)
      value_idx = value_idx + 1
    }
    is_first = false
    for _i = 0; _i < item.invisible_list_item; _i = _i + 1 {
      list_item_idx = list_item_idx + 1
      if list_item_idx > snapshot.list_item_ids.length() {
        return Err(@types.LoroError::DecodeError("movable list id overrun"))
      }
    }
  }
  Ok(state)
}

///|
fn decode_tree_state_snapshot(
  bytes : Bytes,
) -> Result[@state.TreeState, @types.LoroError] {
  let reader = PostcardReader::new(bytes)
  let peer_count = match reader.read_varint_usize() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let peers = match read_peers(reader, peer_count) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let encoded = match decode_encoded_tree(reader.remaining_bytes()) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if encoded.node_ids.length() != encoded.nodes.length() {
    return Err(@types.LoroError::DecodeError("tree node length mismatch"))
  }
  let state = @state.TreeState::new()
  let ids : Array[@types.TreeID] = []
  for id in encoded.node_ids {
    if id.peer_idx < 0 || id.peer_idx >= peers.length() {
      return Err(@types.LoroError::DecodeError("invalid tree peer index"))
    }
    ids.push(@types.TreeID::new(peers[id.peer_idx], id.counter))
  }
  let positions = encoded.positions
  for i = 0; i < encoded.nodes.length(); i = i + 1 {
    let node = encoded.nodes[i]
    let id = ids[i]
    let parent = if node.parent_idx_plus_two == 0 {
      @types.TreeParentId::Root
    } else if node.parent_idx_plus_two == 1 {
      @types.TreeParentId::Deleted
    } else {
      let idx = node.parent_idx_plus_two - 2
      if idx < 0 || idx >= ids.length() {
        return Err(@types.LoroError::DecodeError("invalid tree parent"))
      }
      @types.TreeParentId::Node(ids[idx])
    }
    if node.last_set_peer_idx < 0 || node.last_set_peer_idx >= peers.length() {
      return Err(@types.LoroError::DecodeError("invalid tree last set peer"))
    }
    let lamport = node.last_set_lamport_sub + node.last_set_counter
    if lamport < 0 {
      return Err(@types.LoroError::DecodeError("invalid tree lamport"))
    }
    if node.fractional_index_idx < 0 ||
      node.fractional_index_idx >= positions.length() {
      return Err(@types.LoroError::DecodeError("invalid tree position index"))
    }
    let last_id = @types.IdLp::new(
      peers[node.last_set_peer_idx],
      lamport.reinterpret_as_uint(),
    )
    let position = positions[node.fractional_index_idx]
    state.set_node(@state.TreeNode::new(id, parent, position, last_id))
  }
  Ok(state)
}

///|
fn decode_counter_state_snapshot(
  bytes : Bytes,
) -> Result[@state.CounterState, @types.LoroError] {
  let reader = ByteReader::new(bytes)
  let raw = match reader.read_bytes(8) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let bits = raw[0].to_uint64() |
    (raw[1].to_uint64() << 8) |
    (raw[2].to_uint64() << 16) |
    (raw[3].to_uint64() << 24) |
    (raw[4].to_uint64() << 32) |
    (raw[5].to_uint64() << 40) |
    (raw[6].to_uint64() << 48) |
    (raw[7].to_uint64() << 56)
  let value = bits.reinterpret_as_double()
  let state = @state.CounterState::new()
  state.apply(value)
  Ok(state)
}

///|
fn decode_list_ids(bytes : Bytes) -> Result[DecodedListIds, @types.LoroError] {
  let columns = match decode_columnar_vec_columns(bytes, 3) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let peer_idx = match decode_delta_rle_u32(columns[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let counter = match decode_delta_rle_i32(columns[1]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let lamport_sub = match decode_delta_rle_i32(columns[2]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(DecodedListIds::{ peer_idx, counter, lamport_sub })
}

///|
fn decode_encoded_text(
  bytes : Bytes,
) -> Result[DecodedTextData, @types.LoroError] {
  let reader = PostcardReader::new(bytes)
  let field_len = match reader.read_varint_usize() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if field_len != 3 {
    return Err(@types.LoroError::DecodeError("encoded text field mismatch"))
  }
  let span_columns = match read_columnar_vec_columns(reader, 4) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let spans = match decode_text_spans(span_columns) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let keys = match reader.read_vec_string() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let marks = match decode_marks(reader.remaining_bytes()) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(DecodedTextData::{ spans, keys, marks })
}

///|
fn decode_text_spans(
  columns : Array[Bytes],
) -> Result[Array[DecodedTextSpan], @types.LoroError] {
  if columns.length() != 4 {
    return Err(@types.LoroError::DecodeError("text spans column mismatch"))
  }
  let peer_idx = match decode_delta_rle_u32(columns[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let counter = match decode_delta_rle_i32(columns[1]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let lamport_sub = match decode_delta_rle_i32(columns[2]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let lens = match decode_delta_rle_i32(columns[3]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let count = peer_idx.length()
  if counter.length() != count ||
    lamport_sub.length() != count ||
    lens.length() != count {
    return Err(@types.LoroError::DecodeError("text span length mismatch"))
  }
  let spans : Array[DecodedTextSpan] = []
  for i = 0; i < count; i = i + 1 {
    spans.push(DecodedTextSpan::{
      peer_idx: peer_idx[i],
      counter: counter[i],
      lamport_sub: lamport_sub[i],
      len: lens[i],
    })
  }
  Ok(spans)
}

///|
fn decode_marks(bytes : Bytes) -> Result[Array[DecodedMark], @types.LoroError] {
  let reader = PostcardReader::new(bytes)
  let count = match reader.read_varint_usize() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let marks : Array[DecodedMark] = []
  for _i = 0; _i < count; _i = _i + 1 {
    let field_len = match reader.read_varint_usize() {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    if field_len != 3 {
      return Err(@types.LoroError::DecodeError("mark field count mismatch"))
    }
    let key_idx = match reader.read_varint_usize() {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    let value = match reader.read_loro_value() {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    let info = match reader.read_u8() {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    marks.push(DecodedMark::{ key_idx, value, info: info.to_int() })
  }
  if reader.remaining() != 0 {
    return Err(@types.LoroError::DecodeError("marks trailing bytes"))
  }
  Ok(marks)
}

///|
fn decode_encoded_tree(
  bytes : Bytes,
) -> Result[DecodedTreeData, @types.LoroError] {
  let reader = PostcardReader::new(bytes)
  let field_len = match reader.read_varint_usize() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if field_len != 4 {
    return Err(@types.LoroError::DecodeError("tree field mismatch"))
  }
  let node_id_columns = match read_columnar_vec_columns(reader, 2) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let node_columns = match read_columnar_vec_columns(reader, 5) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let positions_bytes = match reader.read_bytes_with_len() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let _reserved = match reader.read_bytes_with_len() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if reader.remaining() != 0 {
    return Err(@types.LoroError::DecodeError("tree trailing bytes"))
  }
  let node_ids = match decode_tree_node_ids(node_id_columns) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let nodes = match decode_tree_nodes(node_columns) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let positions = match decode_positions(positions_bytes) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let fractional : Array[@types.FractionalIndex] = []
  for pos in positions {
    fractional.push(@types.FractionalIndex::from_bytes(pos))
  }
  Ok(DecodedTreeData::{ node_ids, nodes, positions: fractional })
}

///|
fn decode_tree_node_ids(
  columns : Array[Bytes],
) -> Result[Array[DecodedTreeNodeId], @types.LoroError] {
  if columns.length() != 2 {
    return Err(@types.LoroError::DecodeError("tree id column mismatch"))
  }
  let peer_idx = match decode_delta_rle_u32(columns[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let counter = match decode_delta_rle_i32(columns[1]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let count = peer_idx.length()
  if counter.length() != count {
    return Err(@types.LoroError::DecodeError("tree id length mismatch"))
  }
  let out : Array[DecodedTreeNodeId] = []
  for i = 0; i < count; i = i + 1 {
    out.push(DecodedTreeNodeId::{ peer_idx: peer_idx[i], counter: counter[i] })
  }
  Ok(out)
}

///|
fn decode_tree_nodes(
  columns : Array[Bytes],
) -> Result[Array[DecodedTreeNode], @types.LoroError] {
  if columns.length() != 5 {
    return Err(@types.LoroError::DecodeError("tree node column mismatch"))
  }
  let parent_idx_plus_two = match decode_delta_rle_u32(columns[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let last_set_peer_idx = match decode_delta_rle_u32(columns[1]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let last_set_counter = match decode_delta_rle_i32(columns[2]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let last_set_lamport_sub = match decode_delta_rle_i32(columns[3]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let fractional_index_idx = match decode_postcard_vec_usize(columns[4]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let count = parent_idx_plus_two.length()
  if last_set_peer_idx.length() != count ||
    last_set_counter.length() != count ||
    last_set_lamport_sub.length() != count ||
    fractional_index_idx.length() != count {
    return Err(@types.LoroError::DecodeError("tree node length mismatch"))
  }
  let out : Array[DecodedTreeNode] = []
  for i = 0; i < count; i = i + 1 {
    out.push(DecodedTreeNode::{
      parent_idx_plus_two: parent_idx_plus_two[i],
      last_set_peer_idx: last_set_peer_idx[i],
      last_set_counter: last_set_counter[i],
      last_set_lamport_sub: last_set_lamport_sub[i],
      fractional_index_idx: fractional_index_idx[i],
    })
  }
  Ok(out)
}

///|
fn decode_postcard_vec_usize(
  bytes : Bytes,
) -> Result[Array[Int], @types.LoroError] {
  let reader = PostcardReader::new(bytes)
  let len = match reader.read_varint_usize() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let out : Array[Int] = []
  for _i = 0; _i < len; _i = _i + 1 {
    let value = match reader.read_varint_usize() {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    out.push(value)
  }
  if reader.remaining() != 0 {
    return Err(@types.LoroError::DecodeError("postcard vec trailing bytes"))
  }
  Ok(out)
}

///|
fn count_bool_rle(bytes : Bytes) -> Result[Int, @types.LoroError] {
  let reader = PostcardReader::new(bytes)
  let mut count = 0
  let mut remaining = 0
  while true {
    if remaining == 0 {
      let next = match reader.try_read_varint_usize() {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      match next {
        None => break
        Some(value) => {
          if value > 1000000000 {
            return Err(@types.LoroError::DecodeError("bool rle too large"))
          }
          remaining = value
        }
      }
    }
    if remaining == 0 {
      continue
    }
    remaining = remaining - 1
    count = count + 1
  }
  Ok(count)
}

///|
fn decode_movable_list_snapshot(
  bytes : Bytes,
  expected_items : Int,
) -> Result[MovableListSnapshot, @types.LoroError] {
  let reader = PostcardReader::new(bytes)
  let field_len = match reader.read_varint_usize() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if field_len != 4 {
    return Err(@types.LoroError::DecodeError("movable list field mismatch"))
  }
  let items_columns = match read_columnar_vec_columns(reader, 3) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let list_item_columns = match read_columnar_vec_columns(reader, 3) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let elem_columns = match read_columnar_vec_columns(reader, 2) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let last_set_columns = match read_columnar_vec_columns(reader, 2) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if reader.remaining() != 0 {
    return Err(@types.LoroError::DecodeError("movable list trailing bytes"))
  }
  let items = match decode_movable_list_items(items_columns, expected_items) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let ids = match decode_movable_list_ids(list_item_columns) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let elem_ids = match decode_movable_list_elem_ids(elem_columns) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let last_set_ids = match decode_movable_list_elem_ids(last_set_columns) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(MovableListSnapshot::{ items, list_item_ids: ids, elem_ids, last_set_ids })
}

///|
fn decode_movable_list_items(
  columns : Array[Bytes],
  expected_items : Int,
) -> Result[Array[MovableListItem], @types.LoroError] {
  if columns.length() != 3 {
    return Err(
      @types.LoroError::DecodeError("movable list item column mismatch"),
    )
  }
  let (invisibles, invis_rest) = match
    take_n_delta_rle_u32(columns[0], expected_items) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if invis_rest.length() != 0 {
    return Err(
      @types.LoroError::DecodeError("movable list invisibles trailing bytes"),
    )
  }
  let count = expected_items
  let (pos_flags, pos_rest) = match take_n_bool_rle(columns[1], count) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if pos_rest.length() != 0 {
    let actual = match count_bool_rle(columns[1]) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    return Err(
      @types.LoroError::DecodeError(
        "movable list pos flags trailing bytes (expected \{count}, got \{actual})",
      ),
    )
  }
  let (elem_flags, elem_rest) = match take_n_bool_rle(columns[2], count) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if elem_rest.length() != 0 {
    let actual = match count_bool_rle(columns[2]) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    return Err(
      @types.LoroError::DecodeError(
        "movable list elem flags trailing bytes (expected \{count}, got \{actual})",
      ),
    )
  }
  if pos_flags.length() != count || elem_flags.length() != count {
    return Err(
      @types.LoroError::DecodeError("movable list item length mismatch"),
    )
  }
  let items : Array[MovableListItem] = []
  for i = 0; i < count; i = i + 1 {
    items.push(MovableListItem::{
      invisible_list_item: invisibles[i],
      _pos_id_eq_elem_id: pos_flags[i],
      _elem_id_eq_last_set_id: elem_flags[i],
    })
  }
  Ok(items)
}

///|
fn decode_movable_list_ids(
  columns : Array[Bytes],
) -> Result[Array[MovableListId], @types.LoroError] {
  if columns.length() != 3 {
    return Err(
      @types.LoroError::DecodeError("movable list ids column mismatch"),
    )
  }
  let peer_idx = match decode_delta_rle_u32(columns[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let counter = match decode_delta_rle_i32(columns[1]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let lamport_sub = match decode_delta_rle_i32(columns[2]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let count = peer_idx.length()
  if counter.length() != count || lamport_sub.length() != count {
    return Err(
      @types.LoroError::DecodeError("movable list ids length mismatch"),
    )
  }
  let ids : Array[MovableListId] = []
  for i = 0; i < count; i = i + 1 {
    ids.push(MovableListId::{
      peer_idx: peer_idx[i],
      counter: counter[i],
      lamport_sub: lamport_sub[i],
    })
  }
  Ok(ids)
}

///|
fn decode_movable_list_elem_ids(
  columns : Array[Bytes],
) -> Result[Array[MovableListElemId], @types.LoroError] {
  if columns.length() != 2 {
    return Err(
      @types.LoroError::DecodeError("movable list elem ids column mismatch"),
    )
  }
  let peer_idx = match decode_delta_rle_u32(columns[0]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let lamport = match decode_delta_rle_u32(columns[1]) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let count = peer_idx.length()
  if lamport.length() != count {
    return Err(
      @types.LoroError::DecodeError("movable list elem ids length mismatch"),
    )
  }
  let ids : Array[MovableListElemId] = []
  for i = 0; i < count; i = i + 1 {
    ids.push(MovableListElemId::{ peer_idx: peer_idx[i], lamport: lamport[i] })
  }
  Ok(ids)
}

///|
fn read_peers(
  reader : PostcardReader,
  count : Int,
) -> Result[Array[@types.PeerID], @types.LoroError] {
  let peers : Array[@types.PeerID] = []
  for _i = 0; _i < count; _i = _i + 1 {
    let b = match reader.read_bytes(8) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    let peer = match read_u64_le_at(b, 0) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    peers.push(peer)
  }
  Ok(peers)
}

///|
fn write_peers(writer : PostcardWriter, peers : Array[@types.PeerID]) -> Unit {
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
    writer.write_bytes(Bytes::from_array(bytes))
  }
}

///|
fn encode_container_id_key(id : @types.ContainerID) -> Bytes {
  let writer = LoroValueWriter::new()
  let kind = loro_container_type_to_u8(id.container_type())
  match id {
    @types.ContainerID::Root(name~, container_type=_) => {
      let tag = (kind.to_uint() | 0x80U).to_byte()
      writer.write_u8(tag)
      let name_bytes = @encoding/utf8.encode(name)
      writer.write_usize(name_bytes.length())
      writer.write_raw_bytes(name_bytes)
    }
    @types.ContainerID::Normal(peer~, counter~, container_type=_) => {
      writer.write_u8(kind)
      let peer_bytes : Array[Byte] = [
        (peer & 0xFFUL).to_int().to_byte(),
        ((peer >> 8) & 0xFFUL).to_int().to_byte(),
        ((peer >> 16) & 0xFFUL).to_int().to_byte(),
        ((peer >> 24) & 0xFFUL).to_int().to_byte(),
        ((peer >> 32) & 0xFFUL).to_int().to_byte(),
        ((peer >> 40) & 0xFFUL).to_int().to_byte(),
        ((peer >> 48) & 0xFFUL).to_int().to_byte(),
        ((peer >> 56) & 0xFFUL).to_int().to_byte(),
      ]
      let counter_u = counter.reinterpret_as_uint()
      let counter_bytes : Array[Byte] = [
        (counter_u & 0xFFU).reinterpret_as_int().to_byte(),
        ((counter_u >> 8) & 0xFFU).reinterpret_as_int().to_byte(),
        ((counter_u >> 16) & 0xFFU).reinterpret_as_int().to_byte(),
        ((counter_u >> 24) & 0xFFU).reinterpret_as_int().to_byte(),
      ]
      writer.write_raw_bytes(Bytes::from_array(peer_bytes))
      writer.write_raw_bytes(Bytes::from_array(counter_bytes))
    }
  }
  writer.to_bytes()
}

///|
fn encode_columnar_vec_columns_simple(columns : Array[Bytes]) -> Bytes {
  let writer = PostcardWriter::new()
  writer.write_varint_usize(columns.length())
  for col in columns {
    writer.write_bytes_with_len(col)
  }
  writer.to_bytes()
}

///|
fn encode_postcard_vec_usize(values : Array[Int]) -> Bytes {
  let writer = PostcardWriter::new()
  writer.write_varint_usize(values.length())
  for v in values {
    writer.write_varint_usize(v)
  }
  writer.to_bytes()
}

///|
pub fn encode_loro_doc_state(
  state : @state.DocState,
) -> Result[Bytes, @types.LoroError] {
  let entries : Array[KvEntry] = []
  for entry in state.container_items() {
    let (id, container_state) = entry
    let key = encode_container_id_key(id)
    let value = match encode_container_entry(id, container_state) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    entries.push(KvEntry::{ key, value })
  }
  Ok(encode_kv_store(entries))
}

///|
fn encode_container_entry(
  id : @types.ContainerID,
  state : @state.ContainerState,
) -> Result[Bytes, @types.LoroError] {
  let container_type = id.container_type()
  let state_bytes = match (container_type, state) {
    (@types.ContainerType::Map, @state.ContainerState::MapState(map_state)) =>
      encode_map_state_snapshot(map_state)
    (@types.ContainerType::List, @state.ContainerState::ListState(list_state)) =>
      encode_list_state_snapshot(list_state)
    (@types.ContainerType::Text, @state.ContainerState::TextState(text_state)) =>
      encode_text_state_snapshot(text_state)
    (
      @types.ContainerType::RichText,
      @state.ContainerState::TextState(text_state),
    ) => encode_text_state_snapshot(text_state)
    (
      @types.ContainerType::MovableList,
      @state.ContainerState::MovableListState(list_state),
    ) => encode_movable_list_state_snapshot(list_state)
    (@types.ContainerType::Tree, @state.ContainerState::TreeState(tree_state)) =>
      encode_tree_state_snapshot(tree_state)
    (
      @types.ContainerType::Counter,
      @state.ContainerState::CounterState(counter_state),
    ) => encode_counter_state_snapshot(counter_state)
    _ => return Err(@types.LoroError::EncodeError("container type mismatch"))
  }
  let writer = PostcardWriter::new()
  let kind = loro_container_type_to_u8(container_type)
  writer.write_u8(kind)
  writer.write_varint_usize(0)
  writer.write_option_container_id(None)
  writer.write_bytes(state_bytes)
  Ok(writer.to_bytes())
}

///|
fn encode_map_state_snapshot(map_state : @state.MapState) -> Bytes {
  let entries = map_state.entry_items()
  let map_value : Map[String, @types.LoroValue] = {}
  let keys_with_none : Array[String] = []
  let peers_map : Map[@types.PeerID, Bool] = {}
  let entry_map : Map[String, @state.MapValue] = {}
  for entry in entries {
    let (key, value) = entry
    entry_map[key] = value
    peers_map[value.peer] = true
    match value.value {
      Some(v) => map_value[key] = v
      None => keys_with_none.push(key)
    }
  }
  keys_with_none.sort_by((a, b) => if a < b {
    -1
  } else if a > b {
    1
  } else {
    0
  })
  let peers : Array[@types.PeerID] = []
  for p, _ in peers_map {
    peers.push(p)
  }
  peers.sort_by((a, b) => if a < b { -1 } else if a > b { 1 } else { 0 })
  let peer_index : Map[@types.PeerID, Int] = {}
  for i = 0; i < peers.length(); i = i + 1 {
    peer_index[peers[i]] = i
  }
  let keys : Array[String] = []
  for key, _ in entry_map {
    keys.push(key)
  }
  keys.sort_by((a, b) => if a < b { -1 } else if a > b { 1 } else { 0 })
  let writer = PostcardWriter::new()
  writer.write_map_loro_value(map_value)
  writer.write_vec_string(keys_with_none)
  writer.write_varint_usize(peers.length())
  write_peers(writer, peers)
  for key in keys {
    match entry_map.get(key) {
      Some(value) => {
        let idx = match peer_index.get(value.peer) {
          Some(v) => v
          None => 0
        }
        writer.write_varint_usize(idx)
        writer.write_varint_u32(value.lamport)
      }
      None => ()
    }
  }
  writer.to_bytes()
}

///|
fn encode_list_state_snapshot(list_state : @state.ListState) -> Bytes {
  let elems = list_state.elems()
  let values : Array[@types.LoroValue] = []
  let peers_map : Map[@types.PeerID, Bool] = {}
  for elem in elems {
    values.push(elem.v)
    peers_map[elem.id.peer] = true
  }
  let peers : Array[@types.PeerID] = []
  for p, _ in peers_map {
    peers.push(p)
  }
  peers.sort_by((a, b) => if a < b { -1 } else if a > b { 1 } else { 0 })
  let peer_index : Map[@types.PeerID, Int] = {}
  for i = 0; i < peers.length(); i = i + 1 {
    peer_index[peers[i]] = i
  }
  let peer_idx_col : Array[Int] = []
  let counter_col : Array[Int] = []
  let lamport_sub_col : Array[Int] = []
  for elem in elems {
    let idx = match peer_index.get(elem.id.peer) {
      Some(v) => v
      None => 0
    }
    peer_idx_col.push(idx)
    counter_col.push(elem.id.counter)
    let lamport = elem.id.lamport.reinterpret_as_int()
    lamport_sub_col.push(lamport - elem.id.counter)
  }
  let list_ids = encode_columnar_vec_columns([
    encode_delta_rle_u32(peer_idx_col),
    encode_delta_rle_i32(counter_col),
    encode_delta_rle_i32(lamport_sub_col),
  ])
  let writer = PostcardWriter::new()
  writer.write_vec_loro_value(values)
  writer.write_varint_usize(peers.length())
  write_peers(writer, peers)
  writer.write_bytes(list_ids)
  writer.to_bytes()
}

///|
fn encode_text_state_snapshot(text_state : @state.TextState) -> Bytes {
  let elems = text_state.raw_elems()
  let text = text_state.plain_text()
  let peers : Array[@types.PeerID] = []
  let peer_index : Map[@types.PeerID, Int] = {}
  for elem in elems {
    let peer = match elem {
      @state.RichtextElem::Text(text_elem) => text_elem.id.peer
      @state.RichtextElem::Anchor(style~, anchor=_anchor) => style.id.peer
    }
    if peer_index.get(peer) is None {
      peer_index[peer] = peers.length()
      peers.push(peer)
    }
  }
  let keys : Array[String] = []
  let key_map : Map[String, Int] = {}
  for elem in elems {
    match elem {
      @state.RichtextElem::Anchor(style~, anchor=_anchor) =>
        if key_map.get(style.key) is None {
          key_map[style.key] = keys.length()
          keys.push(style.key)
        }
      _ => ()
    }
  }
  let spans : Array[DecodedTextSpan] = []
  let marks : Array[DecodedMark] = []
  let mut i = 0
  while i < elems.length() {
    match elems[i] {
      @state.RichtextElem::Text(text_elem) => {
        let start_id = text_elem.id
        let start_peer = start_id.peer
        let peer_idx = match peer_index.get(start_peer) {
          Some(v) => v
          None => 0
        }
        let start_counter = start_id.counter
        let start_lamport = start_id.lamport.reinterpret_as_int()
        let mut run = 1
        while i + run < elems.length() {
          match elems[i + run] {
            @state.RichtextElem::Text(next) => {
              if next.id.peer != start_peer {
                break
              }
              if next.id.counter != start_counter + run {
                break
              }
              if next.id.lamport.reinterpret_as_int() != start_lamport + run {
                break
              }
              run = run + 1
            }
            _ => break
          }
        }
        spans.push(DecodedTextSpan::{
          peer_idx,
          counter: start_counter,
          lamport_sub: start_lamport - start_counter,
          len: run,
        })
        i = i + run
      }
      @state.RichtextElem::Anchor(style~, anchor~) => {
        let peer_idx = match peer_index.get(style.id.peer) {
          Some(v) => v
          None => 0
        }
        let lamport_sub = style.id.lamport.reinterpret_as_int() -
          style.id.counter
        match anchor {
          @state.AnchorType::Start => {
            spans.push(DecodedTextSpan::{
              peer_idx,
              counter: style.id.counter,
              lamport_sub,
              len: 0,
            })
            let key_idx = match key_map.get(style.key) {
              Some(v) => v
              None => 0
            }
            marks.push(DecodedMark::{
              key_idx,
              value: style.value,
              info: style.info,
            })
          }
          @state.AnchorType::End =>
            spans.push(DecodedTextSpan::{
              peer_idx,
              counter: style.id.counter + 1,
              lamport_sub,
              len: -1,
            })
        }
        i = i + 1
      }
    }
  }
  let span_columns = encode_text_spans(spans)
  let marks_bytes = encode_marks(marks)
  let writer = PostcardWriter::new()
  writer.write_string(text)
  writer.write_varint_usize(peers.length())
  write_peers(writer, peers)
  writer.write_varint_usize(3)
  writer.write_bytes(span_columns)
  writer.write_vec_string(keys)
  writer.write_bytes(marks_bytes)
  writer.to_bytes()
}

///|
fn encode_text_spans(spans : Array[DecodedTextSpan]) -> Bytes {
  let peer_idx : Array[Int] = []
  let counter : Array[Int] = []
  let lamport_sub : Array[Int] = []
  let lens : Array[Int] = []
  for span in spans {
    peer_idx.push(span.peer_idx)
    counter.push(span.counter)
    lamport_sub.push(span.lamport_sub)
    lens.push(span.len)
  }
  encode_columnar_vec_columns_simple([
    encode_delta_rle_u32(peer_idx),
    encode_delta_rle_i32(counter),
    encode_delta_rle_i32(lamport_sub),
    encode_delta_rle_i32(lens),
  ])
}

///|
fn encode_marks(marks : Array[DecodedMark]) -> Bytes {
  let writer = PostcardWriter::new()
  writer.write_varint_usize(marks.length())
  for mark in marks {
    writer.write_varint_usize(3)
    writer.write_varint_usize(mark.key_idx)
    writer.write_loro_value(mark.value)
    writer.write_u8(mark.info.to_byte())
  }
  writer.to_bytes()
}

///|
fn encode_movable_list_state_snapshot(
  list_state : @state.MovableListState,
) -> Bytes {
  let elems = list_state.elems()
  let values : Array[@types.LoroValue] = []
  let peers_map : Map[@types.PeerID, Bool] = {}
  for elem in elems {
    values.push(elem.v)
    peers_map[elem.id.peer] = true
    peers_map[elem.elem_id.peer] = true
    peers_map[elem.last_set_id.peer] = true
  }
  let peers : Array[@types.PeerID] = []
  for p, _ in peers_map {
    peers.push(p)
  }
  peers.sort_by((a, b) => if a < b { -1 } else if a > b { 1 } else { 0 })
  let peer_index : Map[@types.PeerID, Int] = {}
  for i = 0; i < peers.length(); i = i + 1 {
    peer_index[peers[i]] = i
  }
  let items : Array[MovableListItem] = []
  items.push(MovableListItem::{
    invisible_list_item: 0,
    _pos_id_eq_elem_id: true,
    _elem_id_eq_last_set_id: true,
  })
  let list_item_ids : Array[MovableListId] = []
  let elem_ids : Array[MovableListElemId] = []
  let last_set_ids : Array[MovableListElemId] = []
  for elem in elems {
    let pos_eq = elem.elem_id == elem.id.to_id_lp()
    let last_eq = elem.last_set_id == elem.elem_id
    items.push(MovableListItem::{
      invisible_list_item: 0,
      _pos_id_eq_elem_id: pos_eq,
      _elem_id_eq_last_set_id: last_eq,
    })
    let peer_idx = match peer_index.get(elem.id.peer) {
      Some(v) => v
      None => 0
    }
    let counter = elem.id.counter
    let lamport = elem.id.lamport.reinterpret_as_int()
    list_item_ids.push(MovableListId::{
      peer_idx,
      counter,
      lamport_sub: lamport - counter,
    })
    if !pos_eq {
      let elem_idx = match peer_index.get(elem.elem_id.peer) {
        Some(v) => v
        None => 0
      }
      elem_ids.push(MovableListElemId::{
        peer_idx: elem_idx,
        lamport: elem.elem_id.lamport.reinterpret_as_int(),
      })
    }
    if !last_eq {
      let last_idx = match peer_index.get(elem.last_set_id.peer) {
        Some(v) => v
        None => 0
      }
      last_set_ids.push(MovableListElemId::{
        peer_idx: last_idx,
        lamport: elem.last_set_id.lamport.reinterpret_as_int(),
      })
    }
  }
  let item_cols = encode_columnar_vec_columns_simple([
    encode_delta_rle_u32(items.map(v => v.invisible_list_item)),
    encode_bool_rle(items.map(v => v._pos_id_eq_elem_id)),
    encode_bool_rle(items.map(v => v._elem_id_eq_last_set_id)),
  ])
  let list_item_cols = encode_columnar_vec_columns_simple([
    encode_delta_rle_u32(list_item_ids.map(v => v.peer_idx)),
    encode_delta_rle_i32(list_item_ids.map(v => v.counter)),
    encode_delta_rle_i32(list_item_ids.map(v => v.lamport_sub)),
  ])
  let elem_cols = encode_columnar_vec_columns_simple([
    encode_delta_rle_u32(elem_ids.map(v => v.peer_idx)),
    encode_delta_rle_u32(elem_ids.map(v => v.lamport)),
  ])
  let last_set_cols = encode_columnar_vec_columns_simple([
    encode_delta_rle_u32(last_set_ids.map(v => v.peer_idx)),
    encode_delta_rle_u32(last_set_ids.map(v => v.lamport)),
  ])
  let writer = PostcardWriter::new()
  writer.write_vec_loro_value(values)
  writer.write_varint_usize(peers.length())
  write_peers(writer, peers)
  writer.write_varint_usize(4)
  writer.write_bytes(item_cols)
  writer.write_bytes(list_item_cols)
  writer.write_bytes(elem_cols)
  writer.write_bytes(last_set_cols)
  writer.to_bytes()
}

///|
fn encode_tree_state_snapshot(tree_state : @state.TreeState) -> Bytes {
  let nodes = tree_state.nodes()
  nodes.sort_by((a, b) => if a.id.peer < b.id.peer {
    -1
  } else if a.id.peer > b.id.peer {
    1
  } else if a.id.counter < b.id.counter {
    -1
  } else if a.id.counter > b.id.counter {
    1
  } else {
    0
  })
  let peers_map : Map[@types.PeerID, Bool] = {}
  for node in nodes {
    peers_map[node.id.peer] = true
    peers_map[node.last_id.peer] = true
  }
  let peers : Array[@types.PeerID] = []
  for p, _ in peers_map {
    peers.push(p)
  }
  peers.sort_by((a, b) => if a < b { -1 } else if a > b { 1 } else { 0 })
  let peer_index : Map[@types.PeerID, Int] = {}
  for i = 0; i < peers.length(); i = i + 1 {
    peer_index[peers[i]] = i
  }
  let id_index : Map[@types.TreeID, Int] = {}
  for i = 0; i < nodes.length(); i = i + 1 {
    id_index[nodes[i].id] = i
  }
  let positions : Array[Bytes] = []
  let node_id_peer : Array[Int] = []
  let node_id_counter : Array[Int] = []
  let parent_idx : Array[Int] = []
  let last_peer_idx : Array[Int] = []
  let last_counter : Array[Int] = []
  let last_lamport_sub : Array[Int] = []
  let position_idx : Array[Int] = []
  for node in nodes {
    let peer_idx = match peer_index.get(node.id.peer) {
      Some(v) => v
      None => 0
    }
    node_id_peer.push(peer_idx)
    node_id_counter.push(node.id.counter)
    let parent_value = match node.parent {
      @types.TreeParentId::Root => 0
      @types.TreeParentId::Deleted => 1
      @types.TreeParentId::Node(pid) =>
        match id_index.get(pid) {
          Some(idx) => idx + 2
          None => 1
        }
    }
    parent_idx.push(parent_value)
    let last_peer = match peer_index.get(node.last_id.peer) {
      Some(v) => v
      None => 0
    }
    last_peer_idx.push(last_peer)
    last_counter.push(0)
    last_lamport_sub.push(node.last_id.lamport.reinterpret_as_int())
    let pos_bytes = node.position.bytes()
    let mut idx = -1
    for i = 0; i < positions.length(); i = i + 1 {
      if positions[i] == pos_bytes {
        idx = i
        break
      }
    }
    if idx < 0 {
      positions.push(pos_bytes)
      idx = positions.length() - 1
    }
    position_idx.push(idx)
  }
  let node_id_cols = encode_columnar_vec_columns_simple([
    encode_delta_rle_u32(node_id_peer),
    encode_delta_rle_i32(node_id_counter),
  ])
  let node_cols = encode_columnar_vec_columns_simple([
    encode_delta_rle_u32(parent_idx),
    encode_delta_rle_u32(last_peer_idx),
    encode_delta_rle_i32(last_counter),
    encode_delta_rle_i32(last_lamport_sub),
    encode_postcard_vec_usize(position_idx),
  ])
  let writer = PostcardWriter::new()
  writer.write_varint_usize(peers.length())
  write_peers(writer, peers)
  writer.write_varint_usize(4)
  writer.write_bytes(node_id_cols)
  writer.write_bytes(node_cols)
  writer.write_bytes_with_len(encode_positions(positions))
  writer.write_bytes_with_len(b"")
  writer.to_bytes()
}

///|
fn encode_counter_state_snapshot(counter_state : @state.CounterState) -> Bytes {
  let value = counter_state.value()
  let bits = value.reinterpret_as_uint64()
  let bytes : Array[Byte] = [
    (bits & 0xFFUL).to_int().to_byte(),
    ((bits >> 8) & 0xFFUL).to_int().to_byte(),
    ((bits >> 16) & 0xFFUL).to_int().to_byte(),
    ((bits >> 24) & 0xFFUL).to_int().to_byte(),
    ((bits >> 32) & 0xFFUL).to_int().to_byte(),
    ((bits >> 40) & 0xFFUL).to_int().to_byte(),
    ((bits >> 48) & 0xFFUL).to_int().to_byte(),
    ((bits >> 56) & 0xFFUL).to_int().to_byte(),
  ]
  Bytes::from_array(bytes)
}
