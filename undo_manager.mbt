///|
pub struct UndoOp {
  container : @types.ContainerID
  content : @op.RawOpContent
} derive(Show)

///|
pub fn UndoOp::content_len(self : UndoOp) -> Int {
  self.content.content_len()
}

///|
pub struct UndoStep {
  ops : Array[UndoOp]
} derive(Show)

///|
pub struct UndoManager {
  doc : LoroDoc
  peer_id : @types.PeerID
  undo_stack : Array[UndoStep]
  redo_stack : Array[UndoStep]
  mut seen_changes : Int
  tracking_state : @state.DocState
  ignore_change_ids : Array[@types.ID]
  exclude_origin_prefixes : Array[String]
  mut max_undo_steps : Int
  mut merge_interval_ms : Int64
  mut group_active : Bool
  mut group_ops : Array[UndoOp]
}

///|
pub fn UndoManager::new(doc : LoroDoc) -> UndoManager {
  UndoManager::{
    doc,
    peer_id: doc.peer,
    undo_stack: [],
    redo_stack: [],
    seen_changes: 0,
    tracking_state: @state.DocState::new(),
    ignore_change_ids: [],
    exclude_origin_prefixes: [],
    max_undo_steps: 100,
    merge_interval_ms: 0,
    group_active: false,
    group_ops: [],
  }
}

///|
pub fn UndoManager::undo(self : UndoManager) -> Result[Bool, @types.LoroError] {
  match self.sync_with_oplog() {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  self.finalize_group()
  if self.undo_stack.length() == 0 {
    return Ok(false)
  }
  if self.doc.in_transaction() {
    return Err(@types.LoroError::InternalError("undo inside transaction"))
  }
  let step = self.undo_stack.remove(self.undo_stack.length() - 1)
  let (redo_ops, change_id) = match self.apply_ops_with_inverse(step.ops) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  match change_id {
    Some(id) => self.ignore_change_ids.push(id)
    None => ()
  }
  if redo_ops.length() > 0 {
    self.redo_stack.push(UndoStep::{ ops: redo_ops })
  }
  Ok(true)
}

///|
pub fn UndoManager::redo(self : UndoManager) -> Result[Bool, @types.LoroError] {
  match self.sync_with_oplog() {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  self.finalize_group()
  if self.redo_stack.length() == 0 {
    return Ok(false)
  }
  if self.doc.in_transaction() {
    return Err(@types.LoroError::InternalError("redo inside transaction"))
  }
  let step = self.redo_stack.remove(self.redo_stack.length() - 1)
  let (undo_ops, change_id) = match self.apply_ops_with_inverse(step.ops) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  match change_id {
    Some(id) => self.ignore_change_ids.push(id)
    None => ()
  }
  if undo_ops.length() > 0 {
    self.undo_stack.push(UndoStep::{ ops: undo_ops })
    self.trim_undo_stack()
  }
  Ok(true)
}

///|
pub fn UndoManager::can_undo(self : UndoManager) -> Bool {
  match self.sync_with_oplog() {
    Ok(_) => self.undo_stack.length() > 0
    Err(_) => false
  }
}

///|
pub fn UndoManager::can_redo(self : UndoManager) -> Bool {
  match self.sync_with_oplog() {
    Ok(_) => self.redo_stack.length() > 0
    Err(_) => false
  }
}

///|
pub fn UndoManager::undo_count(self : UndoManager) -> Int {
  match self.sync_with_oplog() {
    Ok(_) => self.undo_stack.length()
    Err(_) => 0
  }
}

///|
pub fn UndoManager::redo_count(self : UndoManager) -> Int {
  match self.sync_with_oplog() {
    Ok(_) => self.redo_stack.length()
    Err(_) => 0
  }
}

///|
pub fn UndoManager::clear(self : UndoManager) -> Unit {
  self.undo_stack.clear()
  self.redo_stack.clear()
}

///|
pub fn UndoManager::group_start(
  self : UndoManager,
) -> Result[Unit, @types.LoroError] {
  match self.sync_with_oplog() {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  if self.group_active {
    return Err(@types.LoroError::UndoGroupAlreadyStarted)
  }
  self.group_active = true
  self.group_ops = []
  Ok(())
}

///|
pub fn UndoManager::group_end(self : UndoManager) -> Unit {
  match self.sync_with_oplog() {
    Ok(_) => ()
    Err(_) => ()
  }
  self.finalize_group()
}

///|
pub fn UndoManager::record_new_checkpoint(
  self : UndoManager,
) -> Result[Unit, @types.LoroError] {
  match self.sync_with_oplog() {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  self.finalize_group()
  Ok(())
}

///|
pub fn UndoManager::set_max_undo_steps(self : UndoManager, steps : Int) -> Unit {
  self.max_undo_steps = steps
  self.trim_undo_stack()
}

///|
pub fn UndoManager::set_merge_interval(
  self : UndoManager,
  interval : Int64,
) -> Unit {
  self.merge_interval_ms = interval
}

///|
pub fn UndoManager::add_exclude_origin_prefix(
  _self : UndoManager,
  _prefix : String,
) -> Unit {
  _self.exclude_origin_prefixes.push(_prefix)
}

///|
pub fn UndoManager::peer(self : UndoManager) -> @types.PeerID {
  self.peer_id
}

///|
pub fn UndoManager::top_undo_value(_self : UndoManager) -> @types.LoroValue? {
  None
}

///|
pub fn UndoManager::top_redo_value(_self : UndoManager) -> @types.LoroValue? {
  None
}

///|
fn UndoManager::ensure_peer(
  self : UndoManager,
) -> Result[Unit, @types.LoroError] {
  if self.doc.peer != self.peer_id {
    Err(
      @types.LoroError::UndoWithDifferentPeerId(
        expected=self.peer_id,
        actual=self.doc.peer,
      ),
    )
  } else {
    Ok(())
  }
}

///|
fn UndoManager::sync_with_oplog(
  self : UndoManager,
) -> Result[Unit, @types.LoroError] {
  match self.ensure_peer() {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  let changes = self.doc.oplog.all_changes()
  let total = changes.length()
  while self.seen_changes < total {
    let change = changes[self.seen_changes]
    let ignore = self.consume_ignore_change(change.id())
    let is_local = change.peer() == self.peer_id
    let excluded_origin = self.is_excluded_origin(change.origin())
    let track_local = is_local && !excluded_origin
    let undo_ops = if !ignore && track_local {
      match
        inverse_ops_for_change(
          self.tracking_state,
          self.doc.arena,
          change,
          self.doc.text_style,
        ) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
    } else {
      []
    }
    if ignore || !track_local {
      match apply_change_to_state(self.tracking_state, self.doc.arena, change) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
    }
    if !ignore && track_local && undo_ops.length() > 0 {
      if self.group_active {
        self.prepend_group_ops(undo_ops)
      } else {
        self.undo_stack.push(UndoStep::{ ops: undo_ops })
        self.trim_undo_stack()
      }
      self.redo_stack.clear()
    }
    self.seen_changes = self.seen_changes + 1
  }
  Ok(())
}

///|
fn UndoManager::is_excluded_origin(
  self : UndoManager,
  origin : String?,
) -> Bool {
  if self.exclude_origin_prefixes.length() == 0 {
    return false
  }
  match origin {
    Some(value) => {
      for prefix in self.exclude_origin_prefixes {
        if value.has_prefix(prefix[:]) {
          return true
        }
      }
      false
    }
    None => false
  }
}

///|
fn UndoManager::consume_ignore_change(
  self : UndoManager,
  id : @types.ID,
) -> Bool {
  let mut i = 0
  while i < self.ignore_change_ids.length() {
    if self.ignore_change_ids[i] == id {
      ignore(self.ignore_change_ids.remove(i))
      return true
    }
    i = i + 1
  }
  false
}

///|
fn UndoManager::prepend_group_ops(
  self : UndoManager,
  ops : Array[UndoOp],
) -> Unit {
  if ops.length() == 0 {
    return
  }
  let merged : Array[UndoOp] = []
  for op in ops {
    merged.push(op)
  }
  for op in self.group_ops {
    merged.push(op)
  }
  self.group_ops = merged
}

///|
fn UndoManager::finalize_group(self : UndoManager) -> Unit {
  if self.group_active {
    if self.group_ops.length() > 0 {
      self.undo_stack.push(UndoStep::{ ops: self.group_ops })
      self.trim_undo_stack()
    }
    self.group_ops = []
    self.group_active = false
  }
}

///|
fn UndoManager::trim_undo_stack(self : UndoManager) -> Unit {
  if self.max_undo_steps <= 0 {
    self.undo_stack.clear()
    return
  }
  while self.undo_stack.length() > self.max_undo_steps {
    ignore(self.undo_stack.remove(0))
  }
}

///|
fn UndoManager::apply_ops_with_inverse(
  self : UndoManager,
  ops : Array[UndoOp],
) -> Result[(Array[UndoOp], @types.ID?), @types.LoroError] {
  if ops.length() == 0 {
    return Ok(([], None))
  }
  match self.doc.begin_transaction() {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  let batches : Array[Array[UndoOp]] = []
  let mut first_id : @types.ID? = None
  for op in ops {
    let len = op.content_len()
    let (id, lamport) = alloc_id_and_lamport(self.doc, len)
    match first_id {
      None => first_id = Some(id)
      Some(_) => ()
    }
    let inv_ops = match
      inverse_ops_for_raw_op(
        self.doc.state,
        op.container,
        op.content,
        id,
        lamport,
        self.doc.text_style,
      ) {
      Ok(value) => value
      Err(err) => {
        ignore(self.doc.commit_transaction())
        return Err(err)
      }
    }
    batches.push(inv_ops)
    match
      self.doc.apply_local_content_with_id(
        id,
        lamport,
        op.container,
        op.content,
      ) {
      Ok(_) => ()
      Err(err) => {
        ignore(self.doc.commit_transaction())
        return Err(err)
      }
    }
  }
  match self.doc.commit_transaction() {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  let inverse_ops = flatten_reverse(batches)
  Ok((inverse_ops, first_id))
}

///|
fn flatten_reverse(batches : Array[Array[UndoOp]]) -> Array[UndoOp] {
  let out : Array[UndoOp] = []
  let mut i = batches.length()
  while i > 0 {
    i = i - 1
    let batch = batches[i]
    for op in batch {
      out.push(op)
    }
  }
  out
}

///|
fn apply_change_to_state(
  state : @state.DocState,
  arena : @arena.SharedArena,
  change : @oplog.Change,
) -> Result[Unit, @types.LoroError] {
  let mut offset = 0
  let change_id = change.id()
  let lamport = change.lamport()
  for op in change.ops() {
    let id = change_id.inc(offset)
    let op_lamport = lamport + offset.reinterpret_as_uint()
    match state.apply_op(arena, op, id, op_lamport) {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
    offset = offset + op.content_len()
  }
  Ok(())
}

///|
fn inverse_ops_for_change(
  state : @state.DocState,
  arena : @arena.SharedArena,
  change : @oplog.Change,
  style_map : @types.StyleConfigMap,
) -> Result[Array[UndoOp], @types.LoroError] {
  let batches : Array[Array[UndoOp]] = []
  let mut offset = 0
  let base_id = change.id()
  let base_lamport = change.lamport()
  for op in change.ops() {
    let id = base_id.inc(offset)
    let lamport = base_lamport + offset.reinterpret_as_uint()
    let full_id = @types.IdFull::new(id.peer, id.counter, lamport)
    let inv_ops = match
      inverse_ops_for_persisted_op(state, op, full_id, style_map) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    batches.push(inv_ops)
    match state.apply_op(arena, op, id, lamport) {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
    offset = offset + op.content_len()
  }
  Ok(flatten_reverse(batches))
}

///|
fn inverse_ops_for_persisted_op(
  state : @state.DocState,
  op : @op.Op,
  base_id : @types.IdFull,
  style_map : @types.StyleConfigMap,
) -> Result[Array[UndoOp], @types.LoroError] {
  let container = op.container()
  match op.content() {
    @op.InnerContent::Map(map_set) => {
      let key = map_set.key()
      let old_value = match state.map_get(container, key) {
        Ok(value) => value
        Err(@types.LoroError::InvalidContainer(_)) => None
        Err(err) => return Err(err)
      }
      let undo = @op.MapSet::new(key, old_value)
      Ok([UndoOp::{ container, content: @op.RawOpContent::Map(undo) }])
    }
    @op.InnerContent::List(inner) =>
      inverse_list_inner_op(state, container, inner, base_id, style_map)
    @op.InnerContent::Tree(tree_op) =>
      inverse_tree_op(state, container, tree_op)
    _ => Err(@types.LoroError::Unsupported("undo op not supported"))
  }
}

///|
fn inverse_ops_for_raw_op(
  state : @state.DocState,
  container : @types.ContainerID,
  content : @op.RawOpContent,
  id : @types.ID,
  lamport : @types.Lamport,
  style_map : @types.StyleConfigMap,
) -> Result[Array[UndoOp], @types.LoroError] {
  let base_id = @types.IdFull::new(id.peer, id.counter, lamport)
  match content {
    @op.RawOpContent::Map(map_set) => {
      let key = map_set.key()
      let old_value = match state.map_get(container, key) {
        Ok(value) => value
        Err(@types.LoroError::InvalidContainer(_)) => None
        Err(err) => return Err(err)
      }
      let undo = @op.MapSet::new(key, old_value)
      Ok([UndoOp::{ container, content: @op.RawOpContent::Map(undo) }])
    }
    @op.RawOpContent::List(list_op) =>
      inverse_list_raw_op(state, container, list_op, base_id, style_map)
    @op.RawOpContent::Tree(tree_op) =>
      inverse_tree_op(state, container, tree_op)
  }
}

///|
fn inverse_list_inner_op(
  state : @state.DocState,
  container : @types.ContainerID,
  op : @op.InnerListOp,
  base_id : @types.IdFull,
  style_map : @types.StyleConfigMap,
) -> Result[Array[UndoOp], @types.LoroError] {
  match op {
    @op.InnerListOp::Insert(slice~, pos~) => {
      let len = slice.len()
      let span = @op.DeleteSpanWithId::new(base_id.to_id(), pos, len)
      Ok([
        UndoOp::{
          container,
          content: @op.RawOpContent::List(@op.ListOp::Delete(span)),
        },
      ])
    }
    @op.InnerListOp::InsertText(str=_, unicode_len=len, pos~, unicode_start=_) => {
      let span = @op.DeleteSpanWithId::new(base_id.to_id(), pos, len)
      Ok([
        UndoOp::{
          container,
          content: @op.RawOpContent::List(@op.ListOp::Delete(span)),
        },
      ])
    }
    @op.InnerListOp::Delete(span) =>
      inverse_insert_for_delete(state, container, span)
    @op.InnerListOp::Move(from=_, elem_id~, to=_) =>
      inverse_move(state, container, elem_id)
    @op.InnerListOp::Set(elem_id~, value=_) =>
      inverse_set(state, container, elem_id)
    @op.InnerListOp::StyleStart(start~, end~, key~, info=_, value=_) =>
      inverse_style(state, container, start, end, key, style_map)
    @op.InnerListOp::StyleEnd => Ok([])
  }
}

///|
fn inverse_list_raw_op(
  state : @state.DocState,
  container : @types.ContainerID,
  op : @op.ListOp,
  base_id : @types.IdFull,
  style_map : @types.StyleConfigMap,
) -> Result[Array[UndoOp], @types.LoroError] {
  match op {
    @op.ListOp::Insert(slice~, pos~) => {
      let len = slice.content_len()
      let span = @op.DeleteSpanWithId::new(base_id.to_id(), pos, len)
      Ok([
        UndoOp::{
          container,
          content: @op.RawOpContent::List(@op.ListOp::Delete(span)),
        },
      ])
    }
    @op.ListOp::Delete(span) =>
      inverse_insert_for_delete(state, container, span)
    @op.ListOp::Move(from=_, elem_id~, to=_) =>
      inverse_move(state, container, elem_id)
    @op.ListOp::Set(elem_id~, value=_) => inverse_set(state, container, elem_id)
    @op.ListOp::StyleStart(start~, end~, key~, info=_, value=_) =>
      inverse_style(state, container, start, end, key, style_map)
    @op.ListOp::StyleEnd => Ok([])
  }
}

///|
fn inverse_insert_for_delete(
  state : @state.DocState,
  container : @types.ContainerID,
  span : @op.DeleteSpanWithId,
) -> Result[Array[UndoOp], @types.LoroError] {
  let start = span.start()
  let end = span.end()
  if start >= end {
    return Ok([])
  }
  let container_type = container.container_type()
  if is_text_container(container_type) {
    let text = match state.text_slice(container, start, end) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let slice = @op.ListSlice::from_str(text)
    let op = @op.ListOp::Insert(slice~, pos=start)
    Ok([UndoOp::{ container, content: @op.RawOpContent::List(op) }])
  } else if container_type == @types.ContainerType::List {
    let values = match list_values_range(state, container, start, end) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let slice = @op.ListSlice::RawData(values)
    let op = @op.ListOp::Insert(slice~, pos=start)
    Ok([UndoOp::{ container, content: @op.RawOpContent::List(op) }])
  } else if container_type == @types.ContainerType::MovableList {
    let values = match movable_list_values_range(state, container, start, end) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let slice = @op.ListSlice::RawData(values)
    let op = @op.ListOp::Insert(slice~, pos=start)
    Ok([UndoOp::{ container, content: @op.RawOpContent::List(op) }])
  } else {
    Err(@types.LoroError::Unsupported("list delete undo not supported"))
  }
}

///|
fn inverse_move(
  state : @state.DocState,
  container : @types.ContainerID,
  elem_id : @types.IdLp,
) -> Result[Array[UndoOp], @types.LoroError] {
  let container_type = container.container_type()
  if container_type == @types.ContainerType::List {
    let index = match list_index_by_id(state, container, elem_id) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let op = @op.ListOp::Move(from=index, to=index, elem_id~)
    Ok([UndoOp::{ container, content: @op.RawOpContent::List(op) }])
  } else if container_type == @types.ContainerType::MovableList {
    let index = match movable_list_index_by_id(state, container, elem_id) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let op = @op.ListOp::Move(from=index, to=index, elem_id~)
    Ok([UndoOp::{ container, content: @op.RawOpContent::List(op) }])
  } else {
    Err(@types.LoroError::Unsupported("move undo not supported"))
  }
}

///|
fn inverse_set(
  state : @state.DocState,
  container : @types.ContainerID,
  elem_id : @types.IdLp,
) -> Result[Array[UndoOp], @types.LoroError] {
  let container_type = container.container_type()
  if container_type == @types.ContainerType::List {
    let index = match list_index_by_id(state, container, elem_id) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let old_value = match state.list_value_at(container, index) {
      Ok(Some(value)) => value
      Ok(None) =>
        return Err(@types.LoroError::InternalError("list element missing"))
      Err(err) => return Err(err)
    }
    let op = @op.ListOp::Set(elem_id~, value=old_value)
    Ok([UndoOp::{ container, content: @op.RawOpContent::List(op) }])
  } else if container_type == @types.ContainerType::MovableList {
    let index = match movable_list_index_by_id(state, container, elem_id) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let old_value = match state.movable_list_value_at(container, index) {
      Ok(Some(value)) => value
      Ok(None) =>
        return Err(@types.LoroError::InternalError("list element missing"))
      Err(err) => return Err(err)
    }
    let op = @op.ListOp::Set(elem_id~, value=old_value)
    Ok([UndoOp::{ container, content: @op.RawOpContent::List(op) }])
  } else {
    Err(@types.LoroError::Unsupported("set undo not supported"))
  }
}

///|
fn inverse_style(
  state : @state.DocState,
  container : @types.ContainerID,
  start : Int,
  end : Int,
  key : String,
  style_map : @types.StyleConfigMap,
) -> Result[Array[UndoOp], @types.LoroError] {
  if start >= end {
    return Ok([])
  }
  let container_type = container.container_type()
  if !is_text_container(container_type) {
    return Err(@types.LoroError::Unsupported("style undo not supported"))
  }
  let styles = match state.text_styles(container) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let info_mark = match style_map.style_info(key, false) {
    Some(value) => value
    None => return Err(@types.LoroError::StyleConfigMissing(key))
  }
  let info_unmark = match style_map.style_info(key, true) {
    Some(value) => value
    None => return Err(@types.LoroError::StyleConfigMissing(key))
  }
  let segments = style_segments(styles, key, start, end)
  let ops : Array[UndoOp] = []
  for seg in segments {
    let (seg_start, seg_end, seg_value) = seg
    match seg_value.value {
      Some(v) => {
        let info = match seg_value.expand {
          Some(expand) => expand.to_info()
          None => info_mark
        }
        let op = @op.ListOp::StyleStart(
          start=seg_start,
          end=seg_end,
          key~,
          info~,
          value=v,
        )
        ops.push(UndoOp::{ container, content: @op.RawOpContent::List(op) })
      }
      None => {
        let op = @op.ListOp::StyleStart(
          start=seg_start,
          end=seg_end,
          key~,
          info=info_unmark,
          value=@types.LoroValue::Null,
        )
        ops.push(UndoOp::{ container, content: @op.RawOpContent::List(op) })
      }
    }
  }
  Ok(ops)
}

///|
fn inverse_tree_op(
  state : @state.DocState,
  container : @types.ContainerID,
  op : @op.TreeOp,
) -> Result[Array[UndoOp], @types.LoroError] {
  match op {
    @op.TreeOp::Create(target~, parent=_, position=_) => {
      let undo = @op.TreeOp::Delete(target~)
      Ok([UndoOp::{ container, content: @op.RawOpContent::Tree(undo) }])
    }
    @op.TreeOp::Move(target~, parent=_, position=_) => {
      let node = match state.tree_node(container, target) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let undo = @op.TreeOp::Move(
        target~,
        parent=node.parent(),
        position=node.position(),
      )
      Ok([UndoOp::{ container, content: @op.RawOpContent::Tree(undo) }])
    }
    @op.TreeOp::Delete(target~) => {
      let node = match state.tree_node(container, target) {
        Ok(value) => value
        Err(err) => return Err(err)
      }
      let undo = @op.TreeOp::Create(
        target~,
        parent=node.parent(),
        position=node.position(),
      )
      Ok([UndoOp::{ container, content: @op.RawOpContent::Tree(undo) }])
    }
  }
}

///|
fn list_values_range(
  state : @state.DocState,
  container : @types.ContainerID,
  start : Int,
  end : Int,
) -> Result[Array[@types.LoroValue], @types.LoroError] {
  let values : Array[@types.LoroValue] = []
  for i = start; i < end; i = i + 1 {
    match state.list_value_at(container, i) {
      Ok(Some(value)) => values.push(value)
      Ok(None) =>
        return Err(@types.LoroError::InternalError("list element missing"))
      Err(err) => return Err(err)
    }
  }
  Ok(values)
}

///|
fn movable_list_values_range(
  state : @state.DocState,
  container : @types.ContainerID,
  start : Int,
  end : Int,
) -> Result[Array[@types.LoroValue], @types.LoroError] {
  let values : Array[@types.LoroValue] = []
  for i = start; i < end; i = i + 1 {
    match state.movable_list_value_at(container, i) {
      Ok(Some(value)) => values.push(value)
      Ok(None) =>
        return Err(@types.LoroError::InternalError("list element missing"))
      Err(err) => return Err(err)
    }
  }
  Ok(values)
}

///|
fn list_index_by_id(
  state : @state.DocState,
  container : @types.ContainerID,
  elem_id : @types.IdLp,
) -> Result[Int, @types.LoroError] {
  let len = match state.list_len(container) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  for i = 0; i < len; i = i + 1 {
    let id_full = match state.list_id_at(container, i) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    if id_full.to_id_lp() == elem_id {
      return Ok(i)
    }
  }
  Err(@types.LoroError::InternalError("element not found"))
}

///|
fn movable_list_index_by_id(
  state : @state.DocState,
  container : @types.ContainerID,
  elem_id : @types.IdLp,
) -> Result[Int, @types.LoroError] {
  let len = match state.movable_list_len(container) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  for i = 0; i < len; i = i + 1 {
    let id_full = match state.movable_list_id_at(container, i) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    if id_full.to_id_lp() == elem_id {
      return Ok(i)
    }
  }
  Err(@types.LoroError::InternalError("element not found"))
}

///|
fn is_text_container(container_type : @types.ContainerType) -> Bool {
  container_type == @types.ContainerType::Text ||
  container_type == @types.ContainerType::RichText
}

///|
priv struct StyleValue {
  value : @types.LoroValue?
  expand : @types.ExpandType?
}

///|
fn style_segments(
  styles : Array[@state.StyleSpan],
  key : String,
  start : Int,
  end : Int,
) -> Array[(Int, Int, StyleValue)] {
  let segments : Array[(Int, Int, StyleValue)] = []
  if start >= end {
    return segments
  }
  let mut idx = start
  let mut current = style_value_at(styles, key, idx)
  let mut seg_start = start
  idx = idx + 1
  while idx < end {
    let next = style_value_at(styles, key, idx)
    if !style_value_eq(current, next) {
      segments.push((seg_start, idx, current))
      seg_start = idx
      current = next
    }
    idx = idx + 1
  }
  segments.push((seg_start, end, current))
  segments
}

///|
fn style_value_at(
  styles : Array[@state.StyleSpan],
  key : String,
  index : Int,
) -> StyleValue {
  let mut value : @types.LoroValue? = None
  let mut expand : @types.ExpandType? = None
  for span in styles {
    if span.key() == key && index >= span.start() && index < span.end() {
      value = Some(span.value())
      expand = Some(span.expand())
    }
  }
  StyleValue::{ value, expand }
}

///|
fn style_value_eq(a : StyleValue, b : StyleValue) -> Bool {
  if !loro_value_opt_eq(a.value, b.value) {
    return false
  }
  match (a.expand, b.expand) {
    (None, None) => true
    (Some(x), Some(y)) => x == y
    _ => false
  }
}

///|
fn loro_value_opt_eq(a : @types.LoroValue?, b : @types.LoroValue?) -> Bool {
  match (a, b) {
    (None, None) => true
    (Some(x), Some(y)) => loro_value_eq(x, y)
    _ => false
  }
}

///|
fn loro_value_eq(a : @types.LoroValue, b : @types.LoroValue) -> Bool {
  match (a, b) {
    (@types.LoroValue::Null, @types.LoroValue::Null) => true
    (@types.LoroValue::Bool(x), @types.LoroValue::Bool(y)) => x == y
    (@types.LoroValue::I64(x), @types.LoroValue::I64(y)) => x == y
    (@types.LoroValue::F64(x), @types.LoroValue::F64(y)) => x == y
    (@types.LoroValue::String(x), @types.LoroValue::String(y)) => x == y
    (@types.LoroValue::Bytes(x), @types.LoroValue::Bytes(y)) => x == y
    (@types.LoroValue::List(xs), @types.LoroValue::List(ys)) => {
      if xs.length() != ys.length() {
        return false
      }
      for i = 0; i < xs.length(); i = i + 1 {
        if !loro_value_eq(xs[i], ys[i]) {
          return false
        }
      }
      true
    }
    (@types.LoroValue::Map(xm), @types.LoroValue::Map(ym)) => map_eq(xm, ym)
    (@types.LoroValue::Container(x), @types.LoroValue::Container(y)) => x == y
    _ => false
  }
}

///|
fn map_eq(
  a : Map[String, @types.LoroValue],
  b : Map[String, @types.LoroValue],
) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for k, v in a {
    match b.get(k) {
      Some(value) => if !loro_value_eq(v, value) { return false }
      None => return false
    }
  }
  true
}
