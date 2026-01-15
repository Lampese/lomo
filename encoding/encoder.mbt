///|
pub fn encode_changes(
  arena : @arena.SharedArena,
  changes : Array[@oplog.Change],
) -> Result[Bytes, @types.LoroError] {
  encode_changes_with_magic(arena, changes, MAGIC)
}

///|
pub fn encode_snapshot(
  arena : @arena.SharedArena,
  state : @state.DocState,
  changes : Array[@oplog.Change],
) -> Result[Bytes, @types.LoroError] {
  let buf = @buffer.new()
  buf.write_bytes(MAGIC_SNAPSHOT)
  buf.write_byte(VERSION)
  let containers = state.container_items()
  write_uvarint(buf, containers.length().to_uint64())
  for entry in containers {
    let (id, container_state) = entry
    write_container_id(buf, id)
    let container_type = id.container_type()
    match (container_type, container_state) {
      (@types.ContainerType::Map, @state.ContainerState::MapState(map_state)) =>
        match write_map_state(buf, map_state) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      (@types.ContainerType::List, @state.ContainerState::ListState(list_state)) =>
        match write_list_state(buf, list_state) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      (@types.ContainerType::Text, @state.ContainerState::TextState(text_state)) =>
        match write_text_state(buf, text_state) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      (
        @types.ContainerType::RichText,
        @state.ContainerState::TextState(text_state),
      ) =>
        match write_text_state(buf, text_state) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      (
        @types.ContainerType::MovableList,
        @state.ContainerState::MovableListState(list_state),
      ) =>
        match write_movable_list_state(buf, list_state) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      (@types.ContainerType::Tree, @state.ContainerState::TreeState(tree_state)) =>
        match write_tree_state(buf, tree_state) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      _ => return Err(@types.LoroError::EncodeError("container type mismatch"))
    }
  }
  write_uvarint(buf, changes.length().to_uint64())
  for change in changes {
    match encode_change(buf, arena, change) {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
  }
  Ok(buf.to_bytes())
}

///|
fn encode_changes_with_magic(
  arena : @arena.SharedArena,
  changes : Array[@oplog.Change],
  magic : Bytes,
) -> Result[Bytes, @types.LoroError] {
  let buf = @buffer.new()
  buf.write_bytes(magic)
  buf.write_byte(VERSION)
  write_uvarint(buf, changes.length().to_uint64())
  for change in changes {
    match encode_change(buf, arena, change) {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
  }
  Ok(buf.to_bytes())
}

///|
fn write_id_full(buf : @buffer.Buffer, id : @types.IdFull) -> Unit {
  write_uvarint(buf, id.peer)
  write_int(buf, id.counter)
  write_uint(buf, id.lamport)
}

///|
fn write_id_lp(buf : @buffer.Buffer, id : @types.IdLp) -> Unit {
  write_uvarint(buf, id.peer)
  write_uint(buf, id.lamport)
}

///|
fn write_char(buf : @buffer.Buffer, value : Char) -> Unit {
  write_string(buf, value.to_string())
}

///|
fn write_opt_string(buf : @buffer.Buffer, value : String?) -> Unit {
  match value {
    None => buf.write_byte(TAG_OPTION_NONE)
    Some(text) => {
      buf.write_byte(TAG_OPTION_SOME)
      write_string(buf, text)
    }
  }
}

///|
fn write_map_state(
  buf : @buffer.Buffer,
  map_state : @state.MapState,
) -> Result[Unit, @types.LoroError] {
  let entries = map_state.entry_items()
  write_uvarint(buf, entries.length().to_uint64())
  for entry in entries {
    let (key, value) = entry
    write_string(buf, key)
    match value.value {
      None => buf.write_byte(TAG_MAPSET_NONE)
      Some(v) => {
        buf.write_byte(TAG_MAPSET_SOME)
        match write_loro_value(buf, v) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
    }
    write_uint(buf, value.lamport)
    write_uvarint(buf, value.peer)
  }
  Ok(())
}

///|
fn write_list_state(
  buf : @buffer.Buffer,
  list_state : @state.ListState,
) -> Result[Unit, @types.LoroError] {
  let elems = list_state.elems()
  write_uvarint(buf, elems.length().to_uint64())
  for elem in elems {
    write_id_full(buf, elem.id)
    match write_loro_value(buf, elem.v) {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
  }
  Ok(())
}

///|
fn write_movable_list_state(
  buf : @buffer.Buffer,
  list_state : @state.MovableListState,
) -> Result[Unit, @types.LoroError] {
  let elems = list_state.elems()
  write_uvarint(buf, elems.length().to_uint64())
  for elem in elems {
    write_id_full(buf, elem.id)
    match write_loro_value(buf, elem.v) {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
  }
  Ok(())
}

///|
fn write_text_state(
  buf : @buffer.Buffer,
  text_state : @state.TextState,
) -> Result[Unit, @types.LoroError] {
  let elems = text_state.elems()
  write_uvarint(buf, elems.length().to_uint64())
  for elem in elems {
    write_id_full(buf, elem.id)
    write_char(buf, elem.ch)
  }
  let styles = text_state.styles()
  write_uvarint(buf, styles.length().to_uint64())
  for span in styles {
    write_int(buf, span.start)
    write_int(buf, span.end)
    write_string(buf, span.key)
    match write_loro_value(buf, span.value) {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
    write_int(buf, span.expand.to_info())
  }
  Ok(())
}

///|
fn write_tree_parent_snapshot(
  buf : @buffer.Buffer,
  parent : @types.TreeParentId,
) -> Result[Unit, @types.LoroError] {
  match parent {
    @types.TreeParentId::Root => {
      buf.write_byte(TAG_TREE_PARENT_ROOT)
      Ok(())
    }
    @types.TreeParentId::Node(id) => {
      buf.write_byte(TAG_TREE_PARENT_NODE)
      write_tree_id(buf, id)
      Ok(())
    }
    @types.TreeParentId::Deleted => {
      buf.write_byte(TAG_TREE_PARENT_DELETED)
      Ok(())
    }
  }
}

///|
fn write_tree_state(
  buf : @buffer.Buffer,
  tree_state : @state.TreeState,
) -> Result[Unit, @types.LoroError] {
  let nodes = tree_state.nodes()
  write_uvarint(buf, nodes.length().to_uint64())
  for node in nodes {
    write_tree_id(buf, node.id)
    match write_tree_parent_snapshot(buf, node.parent) {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
    write_bytes(buf, node.position.bytes())
    write_id_lp(buf, node.last_id)
  }
  Ok(())
}

///|
fn encode_change(
  buf : @buffer.Buffer,
  arena : @arena.SharedArena,
  change : @oplog.Change,
) -> Result[Unit, @types.LoroError] {
  let id = change.id()
  write_uvarint(buf, id.peer)
  write_int(buf, id.counter)
  write_uint(buf, change.lamport())
  write_ivarint(buf, change.timestamp())
  write_opt_string(buf, change.origin())
  write_opt_string(buf, change.commit_msg())
  let deps = change.deps()
  write_uvarint(buf, deps.len().to_uint64())
  for dep in deps.iter() {
    write_uvarint(buf, dep.peer)
    write_int(buf, dep.counter)
  }
  let ops = change.ops()
  write_uvarint(buf, ops.length().to_uint64())
  for op in ops {
    match encode_op(buf, arena, op) {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
  }
  Ok(())
}

///|
fn encode_op(
  buf : @buffer.Buffer,
  arena : @arena.SharedArena,
  op : @op.Op,
) -> Result[Unit, @types.LoroError] {
  write_container_id(buf, op.container())
  match op.content() {
    @op.InnerContent::Map(map_set) => {
      buf.write_byte(TAG_OP_MAP)
      match write_map_set(buf, map_set) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
    }
    @op.InnerContent::List(inner) => {
      buf.write_byte(TAG_OP_LIST)
      let list_op = match inner_to_raw_list(arena, inner) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      match write_list_op(buf, list_op) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
    }
    @op.InnerContent::Tree(tree_op) => {
      buf.write_byte(TAG_OP_TREE)
      match write_tree_op(buf, tree_op) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
    }
    _ => return Err(@types.LoroError::Unsupported("unsupported op content"))
  }
  Ok(())
}

///|
fn write_tree_id(buf : @buffer.Buffer, id : @types.TreeID) -> Unit {
  write_uvarint(buf, id.peer)
  write_int(buf, id.counter)
}

///|
fn write_tree_parent(
  buf : @buffer.Buffer,
  parent : @types.TreeParentId,
) -> Result[Unit, @types.LoroError] {
  match parent {
    @types.TreeParentId::Root => {
      buf.write_byte(TAG_TREE_PARENT_ROOT)
      Ok(())
    }
    @types.TreeParentId::Node(id) => {
      buf.write_byte(TAG_TREE_PARENT_NODE)
      write_tree_id(buf, id)
      Ok(())
    }
    @types.TreeParentId::Deleted =>
      Err(@types.LoroError::EncodeError("invalid tree parent"))
  }
}

///|
fn write_tree_op(
  buf : @buffer.Buffer,
  op : @op.TreeOp,
) -> Result[Unit, @types.LoroError] {
  match op {
    @op.TreeOp::Create(target~, parent~, position~) => {
      buf.write_byte(TAG_TREE_CREATE)
      write_tree_id(buf, target)
      match write_tree_parent(buf, parent) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      write_bytes(buf, position.bytes())
      Ok(())
    }
    @op.TreeOp::Move(target~, parent~, position~) => {
      buf.write_byte(TAG_TREE_MOVE)
      write_tree_id(buf, target)
      match write_tree_parent(buf, parent) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      write_bytes(buf, position.bytes())
      Ok(())
    }
    @op.TreeOp::Delete(target~) => {
      buf.write_byte(TAG_TREE_DELETE)
      write_tree_id(buf, target)
      Ok(())
    }
  }
}

///|
fn inner_to_raw_list(
  arena : @arena.SharedArena,
  inner : @op.InnerListOp,
) -> Result[@op.ListOp, @types.LoroError] {
  match inner {
    @op.InnerListOp::Insert(slice~, pos~) => {
      let values = arena.get_values(slice)
      Ok(@op.ListOp::Insert(slice=@op.ListSlice::RawData(values), pos~))
    }
    @op.InnerListOp::InsertText(str~, unicode_len=len, unicode_start=_, pos~) =>
      Ok(
        @op.ListOp::Insert(
          slice=@op.ListSlice::RawStr(str~, unicode_len=len),
          pos~,
        ),
      )
    @op.InnerListOp::Delete(span) => Ok(@op.ListOp::Delete(span))
    @op.InnerListOp::Move(from~, elem_id~, to~) =>
      Ok(@op.ListOp::Move(from~, elem_id~, to~))
    @op.InnerListOp::Set(elem_id~, value~) =>
      Ok(@op.ListOp::Set(elem_id~, value~))
    @op.InnerListOp::StyleStart(start~, end~, key~, info~, value~) =>
      Ok(@op.ListOp::StyleStart(start~, end~, key~, info~, value~))
    @op.InnerListOp::StyleEnd => Ok(@op.ListOp::StyleEnd)
  }
}

///|
fn write_container_id(buf : @buffer.Buffer, id : @types.ContainerID) -> Unit {
  match id {
    @types.ContainerID::Root(name~, container_type~) => {
      buf.write_byte(TAG_CONTAINER_ROOT)
      write_string(buf, name)
      write_container_type(buf, container_type)
    }
    @types.ContainerID::Normal(peer~, counter~, container_type~) => {
      buf.write_byte(TAG_CONTAINER_NORMAL)
      write_uvarint(buf, peer)
      write_int(buf, counter)
      write_container_type(buf, container_type)
    }
  }
}

///|
fn write_container_type(
  buf : @buffer.Buffer,
  container_type : @types.ContainerType,
) -> Unit {
  match container_type {
    @types.ContainerType::Map => buf.write_byte(TAG_CONTAINER_MAP)
    @types.ContainerType::List => buf.write_byte(TAG_CONTAINER_LIST)
    @types.ContainerType::Text => buf.write_byte(TAG_CONTAINER_TEXT)
    @types.ContainerType::Tree => buf.write_byte(TAG_CONTAINER_TREE)
    @types.ContainerType::RichText => buf.write_byte(TAG_CONTAINER_RICH_TEXT)
    @types.ContainerType::MovableList =>
      buf.write_byte(TAG_CONTAINER_MOVABLE_LIST)
    @types.ContainerType::Unknown(tag) => {
      buf.write_byte(TAG_CONTAINER_UNKNOWN)
      buf.write_byte(tag)
    }
  }
}

///|
fn write_loro_value(
  buf : @buffer.Buffer,
  value : @types.LoroValue,
) -> Result[Unit, @types.LoroError] {
  match value {
    @types.LoroValue::Null => buf.write_byte(TAG_VALUE_NULL)
    @types.LoroValue::Bool(false) => buf.write_byte(TAG_VALUE_BOOL_FALSE)
    @types.LoroValue::Bool(true) => buf.write_byte(TAG_VALUE_BOOL_TRUE)
    @types.LoroValue::I64(v) => {
      buf.write_byte(TAG_VALUE_I64)
      write_ivarint(buf, v)
    }
    @types.LoroValue::F64(v) => {
      buf.write_byte(TAG_VALUE_F64)
      write_string(buf, v.to_string())
    }
    @types.LoroValue::String(s) => {
      buf.write_byte(TAG_VALUE_STRING)
      write_string(buf, s)
    }
    @types.LoroValue::Bytes(bytes) => {
      buf.write_byte(TAG_VALUE_BYTES)
      write_bytes(buf, bytes)
    }
    @types.LoroValue::List(items) => {
      buf.write_byte(TAG_VALUE_LIST)
      write_uvarint(buf, items.length().to_uint64())
      for item in items {
        match write_loro_value(buf, item) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
    }
    @types.LoroValue::Map(map) => {
      buf.write_byte(TAG_VALUE_MAP)
      write_uvarint(buf, map.length().to_uint64())
      for key, value in map {
        write_string(buf, key)
        match write_loro_value(buf, value) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
    }
    @types.LoroValue::Container(id) => {
      buf.write_byte(TAG_VALUE_CONTAINER)
      write_container_id(buf, id)
    }
  }
  Ok(())
}

///|
pub fn write_value(
  buf : @buffer.Buffer,
  value : @types.LoroValue,
) -> Result[Unit, @types.LoroError] {
  write_loro_value(buf, value)
}

///|
pub fn encode_value(
  value : @types.LoroValue,
) -> Result[Bytes, @types.LoroError] {
  let buf = @buffer.new()
  match write_loro_value(buf, value) {
    Ok(_) => Ok(buf.to_bytes())
    Err(err) => Err(err)
  }
}

///|
fn write_list_op(
  buf : @buffer.Buffer,
  op : @op.ListOp,
) -> Result[Unit, @types.LoroError] {
  match op {
    @op.ListOp::Insert(slice~, pos~) => {
      buf.write_byte(TAG_LIST_INSERT)
      write_int(buf, pos)
      match write_list_slice(buf, slice) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
    }
    @op.ListOp::Delete(span) => {
      buf.write_byte(TAG_LIST_DELETE)
      write_uvarint(buf, span.id_start().peer)
      write_int(buf, span.id_start().counter)
      write_int(buf, span.span().pos())
      write_int(buf, span.span().signed_len())
    }
    @op.ListOp::Move(from~, to~, elem_id~) => {
      buf.write_byte(TAG_LIST_MOVE)
      write_int(buf, from)
      write_int(buf, to)
      write_uvarint(buf, elem_id.peer)
      write_uint(buf, elem_id.lamport)
    }
    @op.ListOp::Set(elem_id~, value~) => {
      buf.write_byte(TAG_LIST_SET)
      write_uvarint(buf, elem_id.peer)
      write_uint(buf, elem_id.lamport)
      match write_loro_value(buf, value) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
    }
    @op.ListOp::StyleStart(start~, end~, key~, info~, value~) => {
      buf.write_byte(TAG_LIST_STYLE_START)
      write_int(buf, start)
      write_int(buf, end)
      write_string(buf, key)
      write_int(buf, info)
      match write_loro_value(buf, value) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
    }
    @op.ListOp::StyleEnd => buf.write_byte(TAG_LIST_STYLE_END)
  }
  Ok(())
}

///|
fn write_list_slice(
  buf : @buffer.Buffer,
  slice : @op.ListSlice,
) -> Result[Unit, @types.LoroError] {
  match slice {
    @op.ListSlice::RawData(values) => {
      buf.write_byte(TAG_SLICE_DATA)
      write_uvarint(buf, values.length().to_uint64())
      for value in values {
        match write_loro_value(buf, value) {
          Ok(_) => ()
          Err(err) => return Err(err)
        }
      }
    }
    @op.ListSlice::RawStr(str~, unicode_len=len) => {
      buf.write_byte(TAG_SLICE_STR)
      write_string(buf, str)
      write_int(buf, len)
    }
  }
  Ok(())
}

///|
fn write_map_set(
  buf : @buffer.Buffer,
  map_set : @op.MapSet,
) -> Result[Unit, @types.LoroError] {
  write_string(buf, map_set.key())
  match map_set.value() {
    None => buf.write_byte(TAG_MAPSET_NONE)
    Some(value) => {
      buf.write_byte(TAG_MAPSET_SOME)
      match write_loro_value(buf, value) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
    }
  }
  Ok(())
}
