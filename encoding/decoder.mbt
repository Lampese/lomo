///|
pub fn decode_changes(
  bytes : Bytes,
) -> Result[Array[DecodedChange], @types.LoroError] {
  decode_changes_with_magic(bytes, MAGIC)
}

///|
pub fn decode_snapshot(
  bytes : Bytes,
) -> Result[DecodedSnapshot, @types.LoroError] {
  decode_snapshot_with_magic(bytes, MAGIC_SNAPSHOT)
}

///|
pub fn decode_payload(
  bytes : Bytes,
) -> Result[DecodedPayload, @types.LoroError] {
  let reader = Reader::new(bytes)
  let magic = match reader.read_bytes(4) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  if magic == MAGIC {
    match decode_changes_after_magic(reader) {
      Ok(changes) => Ok(DecodedPayload::Updates(changes))
      Err(err) => Err(err)
    }
  } else if magic == MAGIC_SNAPSHOT {
    match decode_snapshot_after_magic(reader) {
      Ok(snapshot) => Ok(DecodedPayload::Snapshot(snapshot))
      Err(err) => Err(err)
    }
  } else if magic == LORO_MAGIC {
    let (mode, body) = match parse_loro_header(bytes, true) {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    if mode == LoroEncodeMode::FastUpdates {
      match decode_loro_updates_body(body) {
        Ok(changes) => Ok(DecodedPayload::Updates(changes))
        Err(err) => Err(err)
      }
    } else if mode == LoroEncodeMode::FastSnapshot {
      match decode_loro_snapshot_body(body) {
        Ok(snapshot) => Ok(DecodedPayload::Snapshot(snapshot))
        Err(err) => Err(err)
      }
    } else {
      Err(@types.LoroError::DecodeError("unsupported loro payload"))
    }
  } else {
    Err(@types.LoroError::DecodeError("invalid magic"))
  }
}

///|
fn decode_changes_with_magic(
  bytes : Bytes,
  magic_expected : Bytes,
) -> Result[Array[DecodedChange], @types.LoroError] {
  let reader = Reader::new(bytes)
  let magic = match reader.read_bytes(4) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  if magic != magic_expected {
    return Err(@types.LoroError::DecodeError("invalid magic"))
  }
  decode_changes_after_magic(reader)
}

///|
fn decode_snapshot_with_magic(
  bytes : Bytes,
  magic_expected : Bytes,
) -> Result[DecodedSnapshot, @types.LoroError] {
  let reader = Reader::new(bytes)
  let magic = match reader.read_bytes(4) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  if magic != magic_expected {
    return Err(@types.LoroError::DecodeError("invalid magic"))
  }
  decode_snapshot_after_magic(reader)
}

///|
fn decode_changes_after_magic(
  reader : Reader,
) -> Result[Array[DecodedChange], @types.LoroError] {
  let version = match reader.read_byte() {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  if version != VERSION && version != VERSION_V1 {
    return Err(@types.LoroError::DecodeError("unsupported version"))
  }
  let has_commit_meta = version != VERSION_V1
  let count = match read_uvarint(reader) {
    Ok(value) => value.to_int()
    Err(err) => return Err(err)
  }
  let changes : Array[DecodedChange] = []
  for i = 0; i < count; i = i + 1 {
    match decode_change(reader, has_commit_meta) {
      Ok(change) => changes.push(change)
      Err(err) => return Err(err)
    }
  }
  Ok(changes)
}

///|
fn decode_snapshot_after_magic(
  reader : Reader,
) -> Result[DecodedSnapshot, @types.LoroError] {
  let version = match reader.read_byte() {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  if version != VERSION && version != VERSION_V1 {
    return Err(@types.LoroError::DecodeError("unsupported version"))
  }
  let has_commit_meta = version != VERSION_V1
  let container_count = match read_uvarint(reader) {
    Ok(value) => value.to_int()
    Err(err) => return Err(err)
  }
  let state = @state.DocState::new()
  for i = 0; i < container_count; i = i + 1 {
    let id = match read_container_id(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let container_type = id.container_type()
    if container_type == @types.ContainerType::Map {
      let map_state = match read_map_state(reader) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      state.set_map_state(id, map_state)
    } else if container_type == @types.ContainerType::List {
      let list_state = match read_list_state(reader) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      state.set_list_state(id, list_state)
    } else if container_type == @types.ContainerType::Text {
      let text_state = match read_text_state(reader) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      state.set_text_state(id, text_state)
    } else if container_type == @types.ContainerType::RichText {
      let text_state = match read_text_state(reader) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      state.set_text_state(id, text_state)
    } else if container_type == @types.ContainerType::MovableList {
      let list_state = match read_movable_list_state(reader) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      state.set_movable_list_state(id, list_state)
    } else if container_type == @types.ContainerType::Tree {
      let tree_state = match read_tree_state(reader) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      state.set_tree_state(id, tree_state)
    } else if container_type == @types.ContainerType::Counter {
      let counter_state = match read_counter_state(reader) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      state.set_counter_state(id, counter_state)
    } else {
      return Err(@types.LoroError::DecodeError("unsupported container type"))
    }
  }
  let change_count = match read_uvarint(reader) {
    Ok(value) => value.to_int()
    Err(err) => return Err(err)
  }
  let changes : Array[DecodedChange] = []
  for i = 0; i < change_count; i = i + 1 {
    match decode_change(reader, has_commit_meta) {
      Ok(change) => changes.push(change)
      Err(err) => return Err(err)
    }
  }
  Ok(DecodedSnapshot::{ state, changes, needs_replay: false })
}

///|
fn decode_change(
  reader : Reader,
  has_commit_meta : Bool,
) -> Result[DecodedChange, @types.LoroError] {
  let peer = match read_uvarint(reader) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let counter = match read_int(reader) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let lamport = match read_uint(reader) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let timestamp = match read_ivarint(reader) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let origin = if has_commit_meta {
    match read_opt_string(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
  } else {
    None
  }
  let commit_msg = if has_commit_meta {
    match read_opt_string(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
  } else {
    None
  }
  let dep_len = match read_uvarint(reader) {
    Ok(value) => value.to_int()
    Err(err) => return Err(err)
  }
  let deps = @types.Frontiers::new()
  for i = 0; i < dep_len; i = i + 1 {
    let dep_peer = match read_uvarint(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let dep_ctr = match read_int(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    deps.push(@types.ID::new(dep_peer, dep_ctr))
  }
  let op_len = match read_uvarint(reader) {
    Ok(value) => value.to_int()
    Err(err) => return Err(err)
  }
  let ops : Array[DecodedOp] = []
  for i = 0; i < op_len; i = i + 1 {
    match read_decoded_op(reader) {
      Ok(op) => ops.push(op)
      Err(err) => return Err(err)
    }
  }
  Ok(DecodedChange::{
    id: @types.ID::new(peer, counter),
    lamport,
    deps,
    timestamp,
    commit_msg,
    origin,
    ops,
  })
}

///|
fn read_opt_string(reader : Reader) -> Result[String?, @types.LoroError] {
  let tag = match reader.read_byte() {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  if tag == TAG_OPTION_NONE {
    Ok(None)
  } else if tag == TAG_OPTION_SOME {
    match read_string(reader) {
      Ok(value) => Ok(Some(value))
      Err(err) => Err(err)
    }
  } else {
    Err(@types.LoroError::DecodeError("invalid option tag"))
  }
}

///|
fn read_id_full(reader : Reader) -> Result[@types.IdFull, @types.LoroError] {
  let peer = match read_uvarint(reader) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let counter = match read_int(reader) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let lamport = match read_uint(reader) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  Ok(@types.IdFull::new(peer, counter, lamport))
}

///|
fn read_id_lp(reader : Reader) -> Result[@types.IdLp, @types.LoroError] {
  let peer = match read_uvarint(reader) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let lamport = match read_uint(reader) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  Ok(@types.IdLp::new(peer, lamport))
}

///|
fn read_char(reader : Reader) -> Result[Char, @types.LoroError] {
  let text = match read_string(reader) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let mut out = Char::default()
  let mut count = 0
  for ch in text {
    out = ch
    count = count + 1
  }
  if count != 1 {
    return Err(@types.LoroError::DecodeError("invalid char"))
  }
  Ok(out)
}

///|
fn read_map_state(reader : Reader) -> Result[@state.MapState, @types.LoroError] {
  let map_state = @state.MapState::new()
  let len = match read_uvarint(reader) {
    Ok(value) => value.to_int()
    Err(err) => return Err(err)
  }
  for i = 0; i < len; i = i + 1 {
    let key = match read_string(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let tag = match reader.read_byte() {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let value = if tag == TAG_MAPSET_NONE {
      None
    } else if tag == TAG_MAPSET_SOME {
      let decoded = match read_loro_value(reader) {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      Some(decoded)
    } else {
      return Err(@types.LoroError::DecodeError("invalid map entry tag"))
    }
    let lamport = match read_uint(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let peer = match read_uvarint(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    map_state.insert_entry(key, @state.MapValue::new(value, lamport, peer))
  }
  Ok(map_state)
}

///|
fn read_list_state(
  reader : Reader,
) -> Result[@state.ListState, @types.LoroError] {
  let list_state = @state.ListState::new()
  let len = match read_uvarint(reader) {
    Ok(value) => value.to_int()
    Err(err) => return Err(err)
  }
  for i = 0; i < len; i = i + 1 {
    let id = match read_id_full(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let value = match read_loro_value(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    list_state.append_elem(value, id)
  }
  Ok(list_state)
}

///|
fn read_movable_list_state(
  reader : Reader,
) -> Result[@state.MovableListState, @types.LoroError] {
  let list_state = @state.MovableListState::new()
  let len = match read_uvarint(reader) {
    Ok(value) => value.to_int()
    Err(err) => return Err(err)
  }
  for i = 0; i < len; i = i + 1 {
    let id = match read_id_full(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let elem_id = match read_id_lp(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let last_set_id = match read_id_lp(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let value = match read_loro_value(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    list_state.append_elem_full(value, id, elem_id, last_set_id)
  }
  Ok(list_state)
}

///|
fn read_text_state(
  reader : Reader,
) -> Result[@state.TextState, @types.LoroError] {
  let text_state = @state.TextState::new()
  let len = match read_uvarint(reader) {
    Ok(value) => value.to_int()
    Err(err) => return Err(err)
  }
  for i = 0; i < len; i = i + 1 {
    let id = match read_id_full(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let ch = match read_char(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    text_state.append_elem(ch, id)
  }
  let style_len = match read_uvarint(reader) {
    Ok(value) => value.to_int()
    Err(err) => return Err(err)
  }
  let mut style_counter = 0
  for i = 0; i < style_len; i = i + 1 {
    let start = match read_int(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let end = match read_int(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let key = match read_string(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let value = match read_loro_value(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let info = match read_int(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let list_start = text_state.text_pos_to_list_pos(start)
    let list_end = text_state.text_pos_to_list_pos(end)
    let base_id = @types.IdFull::new(
      0UL,
      style_counter,
      style_counter.reinterpret_as_uint(),
    )
    style_counter = style_counter + 2
    let op = @op.InnerListOp::StyleStart(
      start=list_start,
      end=list_end,
      key~,
      info~,
      value~,
    )
    match text_state.apply_inner_op(op, base_id) {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
  }
  Ok(text_state)
}

///|
fn read_tree_parent_snapshot(
  reader : Reader,
) -> Result[@types.TreeParentId, @types.LoroError] {
  let tag = match reader.read_byte() {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  if tag == TAG_TREE_PARENT_ROOT {
    Ok(@types.TreeParentId::Root)
  } else if tag == TAG_TREE_PARENT_NODE {
    let id = match read_tree_id(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    Ok(@types.TreeParentId::Node(id))
  } else if tag == TAG_TREE_PARENT_DELETED {
    Ok(@types.TreeParentId::Deleted)
  } else {
    Err(@types.LoroError::DecodeError("invalid tree parent tag"))
  }
}

///|
fn read_tree_state(
  reader : Reader,
) -> Result[@state.TreeState, @types.LoroError] {
  let tree_state = @state.TreeState::new()
  let len = match read_uvarint(reader) {
    Ok(value) => value.to_int()
    Err(err) => return Err(err)
  }
  for i = 0; i < len; i = i + 1 {
    let id = match read_tree_id(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let parent = match read_tree_parent_snapshot(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let bytes = match read_bytes(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let position = @types.FractionalIndex::from_bytes(bytes)
    let last_id = match read_id_lp(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    tree_state.set_node(@state.TreeNode::new(id, parent, position, last_id))
  }
  Ok(tree_state)
}

///|
fn read_decoded_op(reader : Reader) -> Result[DecodedOp, @types.LoroError] {
  let container = match read_container_id(reader) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let tag = match reader.read_byte() {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let content = if tag == TAG_OP_MAP {
    let map_set = match read_map_set(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    @op.RawOpContent::Map(map_set)
  } else if tag == TAG_OP_LIST {
    let list_op = match read_list_op(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    @op.RawOpContent::List(list_op)
  } else if tag == TAG_OP_TREE {
    let tree_op = match read_tree_op(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    @op.RawOpContent::Tree(tree_op)
  } else if tag == TAG_OP_COUNTER {
    let counter_op = match read_counter_op(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    @op.RawOpContent::Counter(counter_op)
  } else {
    return Err(@types.LoroError::DecodeError("invalid op tag"))
  }
  Ok(DecodedOp::{ container, content })
}

///|
fn read_tree_id(reader : Reader) -> Result[@types.TreeID, @types.LoroError] {
  let peer = match read_uvarint(reader) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let counter = match read_int(reader) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  Ok(@types.TreeID::new(peer, counter))
}

///|
fn read_tree_parent(
  reader : Reader,
) -> Result[@types.TreeParentId, @types.LoroError] {
  let tag = match reader.read_byte() {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  if tag == TAG_TREE_PARENT_ROOT {
    Ok(@types.TreeParentId::Root)
  } else if tag == TAG_TREE_PARENT_NODE {
    let id = match read_tree_id(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    Ok(@types.TreeParentId::Node(id))
  } else {
    Err(@types.LoroError::DecodeError("invalid tree parent tag"))
  }
}

///|
fn read_tree_op(reader : Reader) -> Result[@op.TreeOp, @types.LoroError] {
  let tag = match reader.read_byte() {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  if tag == TAG_TREE_CREATE {
    let target = match read_tree_id(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let parent = match read_tree_parent(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let bytes = match read_bytes(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let position = @types.FractionalIndex::from_bytes(bytes)
    Ok(@op.TreeOp::Create(target~, parent~, position~))
  } else if tag == TAG_TREE_MOVE {
    let target = match read_tree_id(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let parent = match read_tree_parent(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let bytes = match read_bytes(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let position = @types.FractionalIndex::from_bytes(bytes)
    Ok(@op.TreeOp::Move(target~, parent~, position~))
  } else if tag == TAG_TREE_DELETE {
    let target = match read_tree_id(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    Ok(@op.TreeOp::Delete(target~))
  } else {
    Err(@types.LoroError::DecodeError("invalid tree op tag"))
  }
}

///|
fn read_container_id(
  reader : Reader,
) -> Result[@types.ContainerID, @types.LoroError] {
  let tag = match reader.read_byte() {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  if tag == TAG_CONTAINER_ROOT {
    let name = match read_string(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let container_type = match read_container_type(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    Ok(@types.ContainerID::root(name, container_type))
  } else if tag == TAG_CONTAINER_NORMAL {
    let peer = match read_uvarint(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let counter = match read_int(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let container_type = match read_container_type(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    Ok(@types.ContainerID::normal(peer, counter, container_type))
  } else {
    Err(@types.LoroError::DecodeError("invalid container id tag"))
  }
}

///|
fn read_container_type(
  reader : Reader,
) -> Result[@types.ContainerType, @types.LoroError] {
  let tag = match reader.read_byte() {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  if tag == TAG_CONTAINER_MAP {
    Ok(@types.ContainerType::Map)
  } else if tag == TAG_CONTAINER_LIST {
    Ok(@types.ContainerType::List)
  } else if tag == TAG_CONTAINER_TEXT {
    Ok(@types.ContainerType::Text)
  } else if tag == TAG_CONTAINER_TREE {
    Ok(@types.ContainerType::Tree)
  } else if tag == TAG_CONTAINER_RICH_TEXT {
    Ok(@types.ContainerType::RichText)
  } else if tag == TAG_CONTAINER_MOVABLE_LIST {
    Ok(@types.ContainerType::MovableList)
  } else if tag == TAG_CONTAINER_COUNTER {
    Ok(@types.ContainerType::Counter)
  } else if tag == TAG_CONTAINER_UNKNOWN {
    let raw = match reader.read_byte() {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    Ok(@types.ContainerType::Unknown(raw))
  } else {
    Err(@types.LoroError::DecodeError("invalid container type tag"))
  }
}

///|
fn read_counter_state(
  reader : Reader,
) -> Result[@state.CounterState, @types.LoroError] {
  let value = match read_loro_value(reader) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let delta = match value {
    @types.LoroValue::I64(v) => v.to_double()
    @types.LoroValue::F64(v) => v
    _ => return Err(@types.LoroError::DecodeError("invalid counter value"))
  }
  let state = @state.CounterState::new()
  state.apply(delta)
  Ok(state)
}

///|
fn read_counter_op(reader : Reader) -> Result[@op.CounterOp, @types.LoroError] {
  let value = match read_loro_value(reader) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let delta = match value {
    @types.LoroValue::I64(v) => v.to_double()
    @types.LoroValue::F64(v) => v
    _ => return Err(@types.LoroError::DecodeError("invalid counter delta"))
  }
  Ok(@op.CounterOp::new(delta))
}

///|
fn read_loro_value(
  reader : Reader,
) -> Result[@types.LoroValue, @types.LoroError] {
  let tag = match reader.read_byte() {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  if tag == TAG_VALUE_NULL {
    Ok(@types.LoroValue::Null)
  } else if tag == TAG_VALUE_BOOL_FALSE {
    Ok(@types.LoroValue::Bool(false))
  } else if tag == TAG_VALUE_BOOL_TRUE {
    Ok(@types.LoroValue::Bool(true))
  } else if tag == TAG_VALUE_I64 {
    let val = match read_ivarint(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    Ok(@types.LoroValue::I64(val))
  } else if tag == TAG_VALUE_F64 {
    let text = match read_string(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    Ok(@types.LoroValue::F64(@strconv.parse_double(text))) catch {
      _ => Err(@types.LoroError::DecodeError("invalid float"))
    }
  } else if tag == TAG_VALUE_STRING {
    match read_string(reader) {
      Ok(value) => Ok(@types.LoroValue::String(value))
      Err(err) => Err(err)
    }
  } else if tag == TAG_VALUE_BYTES {
    match read_bytes(reader) {
      Ok(value) => Ok(@types.LoroValue::Bytes(value))
      Err(err) => Err(err)
    }
  } else if tag == TAG_VALUE_LIST {
    let len = match read_uvarint(reader) {
      Ok(value) => value.to_int()
      Err(err) => return Err(err)
    }
    let items : Array[@types.LoroValue] = []
    for i = 0; i < len; i = i + 1 {
      match read_loro_value(reader) {
        Ok(value) => items.push(value)
        Err(err) => return Err(err)
      }
    }
    Ok(@types.LoroValue::List(items))
  } else if tag == TAG_VALUE_MAP {
    let len = match read_uvarint(reader) {
      Ok(value) => value.to_int()
      Err(err) => return Err(err)
    }
    let out : Map[String, @types.LoroValue] = {}
    for i = 0; i < len; i = i + 1 {
      let key = match read_string(reader) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let value = match read_loro_value(reader) {
        Ok(item) => item
        Err(err) => return Err(err)
      }
      out[key] = value
    }
    Ok(@types.LoroValue::Map(out))
  } else if tag == TAG_VALUE_CONTAINER {
    let id = match read_container_id(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    Ok(@types.LoroValue::Container(id))
  } else {
    Err(@types.LoroError::DecodeError("invalid value tag"))
  }
}

///|
pub fn read_value(
  reader : Reader,
) -> Result[@types.LoroValue, @types.LoroError] {
  read_loro_value(reader)
}

///|
pub fn decode_value(
  bytes : Bytes,
) -> Result[@types.LoroValue, @types.LoroError] {
  let reader = Reader::new(bytes)
  read_loro_value(reader)
}

///|
fn read_list_op(reader : Reader) -> Result[@op.ListOp, @types.LoroError] {
  let tag = match reader.read_byte() {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  if tag == TAG_LIST_INSERT {
    let pos = match read_int(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let slice = match read_list_slice(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    Ok(@op.ListOp::Insert(slice~, pos~))
  } else if tag == TAG_LIST_DELETE {
    let peer = match read_uvarint(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let counter = match read_int(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let pos = match read_int(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let signed_len = match read_int(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let id_start = @types.ID::new(peer, counter)
    Ok(@op.ListOp::Delete(@op.DeleteSpanWithId::new(id_start, pos, signed_len)))
  } else if tag == TAG_LIST_MOVE {
    let from = match read_int(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let to = match read_int(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let peer = match read_uvarint(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let lamport = match read_uint(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let id = @types.IdLp::new(peer, lamport)
    Ok(@op.ListOp::Move(from~, to~, elem_id=id))
  } else if tag == TAG_LIST_SET {
    let peer = match read_uvarint(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let lamport = match read_uint(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let value = match read_loro_value(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let id = @types.IdLp::new(peer, lamport)
    Ok(@op.ListOp::Set(elem_id=id, value~))
  } else if tag == TAG_LIST_STYLE_START {
    let start = match read_int(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let end = match read_int(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let key = match read_string(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let info = match read_int(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let value = match read_loro_value(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    Ok(@op.ListOp::StyleStart(start~, end~, key~, info~, value~))
  } else if tag == TAG_LIST_STYLE_END {
    Ok(@op.ListOp::StyleEnd)
  } else {
    Err(@types.LoroError::DecodeError("invalid list op tag"))
  }
}

///|
fn read_list_slice(reader : Reader) -> Result[@op.ListSlice, @types.LoroError] {
  let tag = match reader.read_byte() {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  if tag == TAG_SLICE_DATA {
    let len = match read_uvarint(reader) {
      Ok(value) => value.to_int()
      Err(err) => return Err(err)
    }
    let items : Array[@types.LoroValue] = []
    for i = 0; i < len; i = i + 1 {
      match read_loro_value(reader) {
        Ok(value) => items.push(value)
        Err(err) => return Err(err)
      }
    }
    Ok(@op.ListSlice::RawData(items))
  } else if tag == TAG_SLICE_STR {
    let str = match read_string(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let unicode_len = match read_int(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    Ok(@op.ListSlice::RawStr(str~, unicode_len~))
  } else {
    Err(@types.LoroError::DecodeError("invalid list slice tag"))
  }
}

///|
fn read_map_set(reader : Reader) -> Result[@op.MapSet, @types.LoroError] {
  let key = match read_string(reader) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let tag = match reader.read_byte() {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  if tag == TAG_MAPSET_NONE {
    Ok(@op.MapSet::new(key, None))
  } else if tag == TAG_MAPSET_SOME {
    let value = match read_loro_value(reader) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    Ok(@op.MapSet::new(key, Some(value)))
  } else {
    Err(@types.LoroError::DecodeError("invalid map set tag"))
  }
}
