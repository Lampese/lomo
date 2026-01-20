///|
// LoroDoc is the entry for document operations.
pub struct LoroDoc {
  mut oplog : @oplog.OpLog
  mut state : @state.DocState
  mut arena : @arena.SharedArena
  mut text_style : @types.StyleConfigMap
  mut peer : @types.PeerID
  mut counter : @types.Counter
  mut lamport : @types.Lamport
  mut next_sub_id : Int
  mut root_subs : Array[SubscriberEntry]
  mut container_subs : Map[@types.ContainerID, Array[SubscriberEntry]]
  mut local_update_subs : Array[LocalUpdateEntry]
  mut peer_id_subs : Array[PeerIdEntry]
  mut pre_commit_subs : Array[PreCommitEntry]
  mut next_commit_msg : String?
  mut next_commit_origin : String?
  mut txn_active : Bool
  mut txn_ops : Array[@op.Op]
  mut txn_deps : @types.Frontiers?
  mut txn_base_id : @types.ID?
  mut txn_base_lamport : @types.Lamport
}

///|
struct SubscriberEntry {
  id : Int
  callback : Subscriber
}

///|
struct LocalUpdateEntry {
  id : Int
  callback : LocalUpdateCallback
}

///|
struct PeerIdEntry {
  id : Int
  callback : PeerIdUpdateCallback
}

///|
struct PreCommitEntry {
  id : Int
  callback : PreCommitCallback
}

///|
pub fn LoroDoc::new() -> LoroDoc {
  LoroDoc::{
    oplog: @oplog.OpLog::new(),
    state: @state.DocState::new(),
    arena: @arena.SharedArena::new(),
    text_style: @types.StyleConfigMap::default_rich_text_config(),
    peer: 1,
    counter: 0,
    lamport: 0,
    next_sub_id: 1,
    root_subs: [],
    container_subs: Map::new(),
    local_update_subs: [],
    peer_id_subs: [],
    pre_commit_subs: [],
    next_commit_msg: None,
    next_commit_origin: None,
    txn_active: false,
    txn_ops: [],
    txn_deps: None,
    txn_base_id: None,
    txn_base_lamport: 0,
  }
}

///|
pub fn LoroDoc::set_peer_id(self : LoroDoc, peer : @types.PeerID) -> Unit {
  self.peer = peer
  self.emit_peer_id_change(peer)
}

///|
fn LoroDoc::alloc_sub_id(self : LoroDoc) -> Int {
  let id = self.next_sub_id
  self.next_sub_id = id + 1
  id
}

///|
pub fn LoroDoc::subscribe(
  self : LoroDoc,
  container_id : @types.ContainerID,
  callback : Subscriber,
) -> Subscription {
  let id = self.alloc_sub_id()
  let entry = SubscriberEntry::{ id, callback }
  let list = match self.container_subs.get(container_id) {
    Some(value) => value
    None => []
  }
  list.push(entry)
  self.container_subs[container_id] = list
  Subscription::{ doc: self, id }
}

///|
pub fn LoroDoc::subscribe_root(
  self : LoroDoc,
  callback : Subscriber,
) -> Subscription {
  let id = self.alloc_sub_id()
  self.root_subs.push(SubscriberEntry::{ id, callback })
  Subscription::{ doc: self, id }
}

///|
pub fn LoroDoc::subscribe_local_update(
  self : LoroDoc,
  callback : LocalUpdateCallback,
) -> Subscription {
  let id = self.alloc_sub_id()
  self.local_update_subs.push(LocalUpdateEntry::{ id, callback })
  Subscription::{ doc: self, id }
}

///|
pub fn LoroDoc::subscribe_peer_id_change(
  self : LoroDoc,
  callback : PeerIdUpdateCallback,
) -> Subscription {
  let id = self.alloc_sub_id()
  self.peer_id_subs.push(PeerIdEntry::{ id, callback })
  Subscription::{ doc: self, id }
}

///|
pub fn LoroDoc::subscribe_pre_commit(
  self : LoroDoc,
  callback : PreCommitCallback,
) -> Subscription {
  let id = self.alloc_sub_id()
  self.pre_commit_subs.push(PreCommitEntry::{ id, callback })
  Subscription::{ doc: self, id }
}

///|
pub fn LoroDoc::set_next_commit_message(
  self : LoroDoc,
  message : String?,
) -> Unit {
  self.next_commit_msg = message
}

///|
pub fn LoroDoc::set_next_commit_origin(
  self : LoroDoc,
  origin : String?,
) -> Unit {
  self.next_commit_origin = origin
}

///|
fn LoroDoc::unsubscribe(self : LoroDoc, id : Int) -> Unit {
  self.root_subs = filter_subscribers_by_id(self.root_subs, id)
  self.local_update_subs = filter_update_subs_by_id(self.local_update_subs, id)
  self.peer_id_subs = filter_peer_subs_by_id(self.peer_id_subs, id)
  self.pre_commit_subs = filter_pre_commit_subs_by_id(self.pre_commit_subs, id)
  let next_map : Map[@types.ContainerID, Array[SubscriberEntry]] = {}
  for container_id, entries in self.container_subs {
    let filtered = filter_subscribers_by_id(entries, id)
    if filtered.length() > 0 {
      next_map[container_id] = filtered
    }
  }
  self.container_subs = next_map
}

///|
fn filter_subscribers_by_id(
  entries : Array[SubscriberEntry],
  id : Int,
) -> Array[SubscriberEntry] {
  let out : Array[SubscriberEntry] = []
  for entry in entries {
    if entry.id != id {
      out.push(entry)
    }
  }
  out
}

///|
fn filter_update_subs_by_id(
  entries : Array[LocalUpdateEntry],
  id : Int,
) -> Array[LocalUpdateEntry] {
  let out : Array[LocalUpdateEntry] = []
  for entry in entries {
    if entry.id != id {
      out.push(entry)
    }
  }
  out
}

///|
fn filter_peer_subs_by_id(
  entries : Array[PeerIdEntry],
  id : Int,
) -> Array[PeerIdEntry] {
  let out : Array[PeerIdEntry] = []
  for entry in entries {
    if entry.id != id {
      out.push(entry)
    }
  }
  out
}

///|
fn filter_pre_commit_subs_by_id(
  entries : Array[PreCommitEntry],
  id : Int,
) -> Array[PreCommitEntry] {
  let out : Array[PreCommitEntry] = []
  for entry in entries {
    if entry.id != id {
      out.push(entry)
    }
  }
  out
}

///|
pub fn LoroDoc::begin_transaction(
  self : LoroDoc,
) -> Result[Unit, @types.LoroError] {
  if self.txn_active {
    return Err(@types.LoroError::InternalError("transaction already active"))
  }
  self.txn_active = true
  self.txn_ops = []
  self.txn_deps = Some(self.oplog.frontiers().clone())
  self.txn_base_id = None
  self.txn_base_lamport = 0
  Ok(())
}

///|
pub fn LoroDoc::commit_transaction(
  self : LoroDoc,
) -> Result[Unit, @types.LoroError] {
  if !self.txn_active {
    return Err(@types.LoroError::InternalError("transaction not active"))
  }
  if self.txn_ops.length() == 0 {
    self.reset_transaction()
    return Ok(())
  }
  match (self.txn_base_id, self.txn_deps) {
    (Some(id), Some(deps)) => {
      let meta = self.build_commit_meta()
      let change = @oplog.Change::new_with_meta(
        self.txn_ops,
        deps,
        id,
        self.txn_base_lamport,
        meta.timestamp(),
        meta.message(),
        meta.origin(),
      )
      self.oplog.insert_new_change(change, true)
      match self.oplog.get_change(id) {
        Some(saved) => self.emit_change(saved, true)
        None => ()
      }
      self.reset_transaction()
      Ok(())
    }
    _ => Err(@types.LoroError::InternalError("invalid transaction state"))
  }
}

///|
pub fn LoroDoc::in_transaction(self : LoroDoc) -> Bool {
  self.txn_active
}

///|
fn LoroDoc::reset_transaction(self : LoroDoc) -> Unit {
  self.txn_active = false
  self.txn_ops = []
  self.txn_deps = None
  self.txn_base_id = None
  self.txn_base_lamport = 0
}

///|
fn LoroDoc::emit_peer_id_change(self : LoroDoc, peer : @types.PeerID) -> Unit {
  if self.peer_id_subs.length() == 0 {
    return
  }
  self.peer_id_subs = filter_peer_subs(self.peer_id_subs, peer)
}

///|
fn LoroDoc::build_commit_meta(self : LoroDoc) -> CommitMeta {
  let meta = CommitMeta::new(@env.now().reinterpret_as_int64())
  match self.next_commit_msg {
    Some(msg) => {
      meta.set_message(Some(msg))
      self.next_commit_msg = None
    }
    None => ()
  }
  match self.next_commit_origin {
    Some(origin) => {
      meta.set_origin(Some(origin))
      self.next_commit_origin = None
    }
    None => ()
  }
  if self.pre_commit_subs.length() > 0 {
    self.pre_commit_subs = filter_pre_commit_subs(self.pre_commit_subs, meta)
  }
  meta
}

///|
fn LoroDoc::emit_change(
  self : LoroDoc,
  change : @oplog.Change,
  is_local : Bool,
) -> Unit {
  let events = self.events_for_change(change)
  if events.length() > 0 {
    let batch = EventBatch::{ events, is_local, peer: change.peer() }
    self.root_subs = filter_subscribers(self.root_subs, batch)
    for event in events {
      let container_id = event.container()
      match self.container_subs.get(container_id) {
        Some(entries) => {
          let container_batch = EventBatch::{
            events: [event],
            is_local,
            peer: change.peer(),
          }
          let kept = filter_subscribers(entries, container_batch)
          if kept.length() > 0 {
            self.container_subs[container_id] = kept
          } else {
            self.container_subs.remove(container_id)
          }
        }
        None => ()
      }
    }
  }
  if is_local {
    self.emit_local_update(change)
  }
}

///|
fn LoroDoc::emit_snapshot(self : LoroDoc) -> Unit {
  let events : Array[ContainerEvent] = []
  let items = self.state.container_items()
  for entry in items {
    let (id, _state) = entry
    let diff = self.container_diff(id)
    events.push(ContainerEvent::{ container: id, diff })
  }
  if events.length() == 0 {
    return
  }
  let batch = EventBatch::{ events, is_local: false, peer: self.peer }
  self.root_subs = filter_subscribers(self.root_subs, batch)
  for event in events {
    let container_id = event.container()
    match self.container_subs.get(container_id) {
      Some(entries) => {
        let container_batch = EventBatch::{
          events: [event],
          is_local: false,
          peer: self.peer,
        }
        let kept = filter_subscribers(entries, container_batch)
        if kept.length() > 0 {
          self.container_subs[container_id] = kept
        } else {
          self.container_subs.remove(container_id)
        }
      }
      None => ()
    }
  }
}

///|
fn LoroDoc::emit_local_update(self : LoroDoc, change : @oplog.Change) -> Unit {
  if self.local_update_subs.length() == 0 {
    return
  }
  let bytes = match @encoding.encode_changes(self.arena, [change]) {
    Ok(value) => value
    Err(_) => return
  }
  self.local_update_subs = filter_local_updates(self.local_update_subs, bytes)
}

///|
fn LoroDoc::events_for_change(
  self : LoroDoc,
  change : @oplog.Change,
) -> Array[ContainerEvent] {
  let events : Array[ContainerEvent] = []
  let seen : Map[@types.ContainerID, Bool] = {}
  for op in change.ops() {
    let container_id = op.container()
    if seen.get(container_id) is Some(true) {
      continue
    }
    seen[container_id] = true
    let diff = self.container_diff(container_id)
    events.push(ContainerEvent::{ container: container_id, diff })
  }
  events
}

///|
fn LoroDoc::container_diff(
  self : LoroDoc,
  container_id : @types.ContainerID,
) -> Array[@types.LoroValue] {
  let container_type = container_id.container_type()
  if container_type == @types.ContainerType::Map {
    match self.map_diff(@container.MapHandler::new(container_id)) {
      Ok(value) => value
      Err(_) => []
    }
  } else if container_type == @types.ContainerType::List {
    match self.list_diff(@container.ListHandler::new(container_id)) {
      Ok(value) => value
      Err(_) => []
    }
  } else if container_type == @types.ContainerType::MovableList {
    match
      self.movable_list_diff(@container.MovableListHandler::new(container_id)) {
      Ok(value) => value
      Err(_) => []
    }
  } else if container_type == @types.ContainerType::Text ||
    container_type == @types.ContainerType::RichText {
    match self.text_diff(@container.TextHandler::new(container_id)) {
      Ok(value) => value
      Err(_) => []
    }
  } else if container_type == @types.ContainerType::Tree {
    let value = self.state.deep_value_for_container(container_id)
    match self.list_diff_from_value(value) {
      Ok(list) => list
      Err(_) => []
    }
  } else if container_type == @types.ContainerType::Counter {
    match self.state.counter_value(container_id) {
      Ok(value) => [@types.LoroValue::F64(value)]
      Err(_) => []
    }
  } else {
    []
  }
}

///|
fn filter_subscribers(
  entries : Array[SubscriberEntry],
  batch : EventBatch,
) -> Array[SubscriberEntry] {
  let out : Array[SubscriberEntry] = []
  for entry in entries {
    if (entry.callback)(batch) {
      out.push(entry)
    }
  }
  out
}

///|
fn filter_local_updates(
  entries : Array[LocalUpdateEntry],
  bytes : Bytes,
) -> Array[LocalUpdateEntry] {
  let out : Array[LocalUpdateEntry] = []
  for entry in entries {
    if (entry.callback)(bytes) {
      out.push(entry)
    }
  }
  out
}

///|
fn filter_peer_subs(
  entries : Array[PeerIdEntry],
  peer : @types.PeerID,
) -> Array[PeerIdEntry] {
  let out : Array[PeerIdEntry] = []
  for entry in entries {
    if (entry.callback)(peer) {
      out.push(entry)
    }
  }
  out
}

///|
fn filter_pre_commit_subs(
  entries : Array[PreCommitEntry],
  meta : CommitMeta,
) -> Array[PreCommitEntry] {
  let out : Array[PreCommitEntry] = []
  for entry in entries {
    if (entry.callback)(meta) {
      out.push(entry)
    }
  }
  out
}

///|
pub fn LoroDoc::container_map(
  _self : LoroDoc,
  id : @types.ContainerID,
) -> @container.MapHandler {
  @container.MapHandler::new(id)
}

///|
pub fn LoroDoc::container_list(
  _self : LoroDoc,
  id : @types.ContainerID,
) -> @container.ListHandler {
  @container.ListHandler::new(id)
}

///|
pub fn LoroDoc::container_text(
  _self : LoroDoc,
  id : @types.ContainerID,
) -> @container.TextHandler {
  @container.TextHandler::new(id)
}

///|
pub fn LoroDoc::container_tree(
  _self : LoroDoc,
  id : @types.ContainerID,
) -> @container.TreeHandler {
  @container.TreeHandler::new(id)
}

///|
pub fn LoroDoc::container_movable_list(
  _self : LoroDoc,
  id : @types.ContainerID,
) -> @container.MovableListHandler {
  @container.MovableListHandler::new(id)
}

///|
pub fn LoroDoc::config_text_style(
  self : LoroDoc,
  text_style : @types.StyleConfigMap,
) -> Unit {
  self.text_style = text_style
}

///|
pub fn LoroDoc::config_default_text_style(
  self : LoroDoc,
  text_style : @types.StyleConfig?,
) -> Unit {
  self.text_style.set_default(text_style)
}

///|
pub fn alloc_id_and_lamport(
  doc : LoroDoc,
  len : Int,
) -> (@types.ID, @types.Lamport) {
  let id = @types.ID::new(doc.peer, doc.counter)
  let lamport = doc.lamport
  doc.counter = doc.counter + len
  doc.lamport = doc.lamport + len.reinterpret_as_uint()
  (id, lamport)
}

///|
pub fn LoroDoc::get_list(
  _self : LoroDoc,
  name : String,
) -> @container.ListHandler {
  let id = @types.ContainerID::root(name, @types.ContainerType::List)
  @container.ListHandler::new(id)
}

///|
pub fn LoroDoc::get_movable_list(
  _self : LoroDoc,
  name : String,
) -> @container.MovableListHandler {
  let id = @types.ContainerID::root(name, @types.ContainerType::MovableList)
  @container.MovableListHandler::new(id)
}

///|
pub fn LoroDoc::get_tree(
  _self : LoroDoc,
  name : String,
) -> @container.TreeHandler {
  let id = @types.ContainerID::root(name, @types.ContainerType::Tree)
  @container.TreeHandler::new(id)
}

///|
pub fn LoroDoc::get_map(
  _self : LoroDoc,
  name : String,
) -> @container.MapHandler {
  let id = @types.ContainerID::root(name, @types.ContainerType::Map)
  @container.MapHandler::new(id)
}

///|
pub fn LoroDoc::get_counter(
  _self : LoroDoc,
  name : String,
) -> @container.CounterHandler {
  let id = @types.ContainerID::root(name, @types.ContainerType::Counter)
  @container.CounterHandler::new(id)
}

///|
pub fn LoroDoc::map_id(
  _self : LoroDoc,
  handler : @container.MapHandler,
) -> @types.ContainerID {
  handler.id()
}

///|
pub fn LoroDoc::get_text(
  _self : LoroDoc,
  name : String,
) -> @container.TextHandler {
  let id = @types.ContainerID::root(name, @types.ContainerType::Text)
  @container.TextHandler::new(id)
}

///|
fn LoroDoc::apply_local_content(
  self : LoroDoc,
  container_id : @types.ContainerID,
  content : @op.RawOpContent,
) -> Result[Unit, @types.LoroError] {
  let len = content.content_len()
  let (id, lamport) = alloc_id_and_lamport(self, len)
  self.apply_local_content_with_id(id, lamport, container_id, content)
}

///|
pub fn LoroDoc::apply_local_content_with_id(
  self : LoroDoc,
  id : @types.ID,
  lamport : @types.Lamport,
  container_id : @types.ContainerID,
  content : @op.RawOpContent,
) -> Result[Unit, @types.LoroError] {
  let raw_op = @op.RawOp::new(id, lamport, container_id, content)
  let op = self.arena.to_persisted_op(raw_op)
  if self.txn_active {
    match self.txn_base_id {
      None => {
        self.txn_base_id = Some(id)
        self.txn_base_lamport = lamport
      }
      Some(_) => ()
    }
    self.txn_ops.push(op)
    match self.state.apply_raw_op(self.arena, raw_op) {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
  } else {
    let deps = self.oplog.frontiers().clone()
    let meta = self.build_commit_meta()
    let change = @oplog.Change::new_with_meta(
      [op],
      deps,
      id,
      lamport,
      meta.timestamp(),
      meta.message(),
      meta.origin(),
    )
    self.oplog.insert_new_change(change, true)
    match self.state.apply_raw_op(self.arena, raw_op) {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
    match self.oplog.get_change(id) {
      Some(saved) => self.emit_change(saved, true)
      None => ()
    }
  }
  Ok(())
}

///|
fn LoroDoc::alloc_container_id(
  self : LoroDoc,
  container_type : @types.ContainerType,
) -> (@types.ContainerID, @types.ID, @types.Lamport) {
  let (id, lamport) = alloc_id_and_lamport(self, 1)
  let container_id = @types.ContainerID::normal(
    id.peer,
    id.counter,
    container_type,
  )
  (container_id, id, lamport)
}

///|
fn LoroDoc::apply_list_op_to(
  self : LoroDoc,
  container_id : @types.ContainerID,
  op : @op.ListOp,
) -> Result[Unit, @types.LoroError] {
  self.apply_local_content(container_id, @op.RawOpContent::List(op))
}

///|
pub fn LoroDoc::apply_list_op(
  self : LoroDoc,
  handler : @container.ListHandler,
  op : @op.ListOp,
) -> Result[Unit, @types.LoroError] {
  self.apply_list_op_to(handler.id(), op)
}

///|
pub fn LoroDoc::apply_map_set(
  self : LoroDoc,
  handler : @container.MapHandler,
  key : String,
  value : @types.LoroValue?,
) -> Result[Unit, @types.LoroError] {
  let map_set = @op.MapSet::new(key, value)
  self.apply_local_content(handler.id(), @op.RawOpContent::Map(map_set))
}

///|
pub fn LoroDoc::apply_text_op(
  self : LoroDoc,
  handler : @container.TextHandler,
  op : @op.ListOp,
) -> Result[Unit, @types.LoroError] {
  self.apply_list_op_to(handler.id(), op)
}

///|
pub fn LoroDoc::apply_tree_op(
  self : LoroDoc,
  handler : @container.TreeHandler,
  op : @op.TreeOp,
) -> Result[Unit, @types.LoroError] {
  self.apply_local_content(handler.id(), @op.RawOpContent::Tree(op))
}

///|
pub fn LoroDoc::list_insert(
  self : LoroDoc,
  handler : @container.ListHandler,
  pos : Int,
  value : @types.LoroValue,
) -> Result[Unit, @types.LoroError] {
  let slice = @op.ListSlice::RawData([value])
  let op = @op.ListOp::Insert(slice~, pos~)
  self.apply_list_op(handler, op)
}

///|
pub fn LoroDoc::list_insert_container(
  self : LoroDoc,
  handler : @container.ListHandler,
  pos : Int,
  container_type : @types.ContainerType,
) -> Result[@types.ContainerID, @types.LoroError] {
  let (container_id, id, lamport) = self.alloc_container_id(container_type)
  let slice = @op.ListSlice::RawData([@types.LoroValue::Container(container_id)])
  let op = @op.ListOp::Insert(slice~, pos~)
  match
    self.apply_local_content_with_id(
      id,
      lamport,
      handler.id(),
      @op.RawOpContent::List(op),
    ) {
    Ok(_) => Ok(container_id)
    Err(err) => Err(err)
  }
}

///|
pub fn LoroDoc::list_push(
  self : LoroDoc,
  handler : @container.ListHandler,
  value : @types.LoroValue,
) -> Result[Unit, @types.LoroError] {
  let len = match self.state.list_len(handler.id()) {
    Ok(value) => value
    Err(@types.LoroError::InvalidContainer(_)) => 0
    Err(err) => return Err(err)
  }
  self.list_insert(handler, len, value)
}

///|
pub fn LoroDoc::list_push_container(
  self : LoroDoc,
  handler : @container.ListHandler,
  container_type : @types.ContainerType,
) -> Result[@types.ContainerID, @types.LoroError] {
  let len = match self.state.list_len(handler.id()) {
    Ok(value) => value
    Err(@types.LoroError::InvalidContainer(_)) => 0
    Err(err) => return Err(err)
  }
  self.list_insert_container(handler, len, container_type)
}

///|
pub fn LoroDoc::list_get_or_create_container(
  self : LoroDoc,
  handler : @container.ListHandler,
  pos : Int,
  container_type : @types.ContainerType,
) -> Result[@types.ContainerID, @types.LoroError] {
  match self.state.list_value_at(handler.id(), pos) {
    Ok(Some(@types.LoroValue::Container(id))) =>
      if id.container_type() != container_type {
        Err(@types.LoroError::InternalError("container type mismatch"))
      } else {
        Ok(id)
      }
    Ok(Some(_)) =>
      Err(@types.LoroError::InternalError("list element is not container"))
    Ok(None) => self.list_insert_container(handler, pos, container_type)
    Err(@types.LoroError::InvalidContainer(_)) =>
      self.list_insert_container(handler, pos, container_type)
    Err(err) => Err(err)
  }
}

///|
fn delete_spans_from_ids(
  ids : Array[@types.IdFull],
  start_pos : Int,
  list_pos_at : (Int) -> Result[Int, @types.LoroError],
) -> Result[Array[@op.DeleteSpanWithId], @types.LoroError] {
  let spans : Array[@op.DeleteSpanWithId] = []
  if ids.length() == 0 {
    return Ok(spans)
  }
  let mut current_peer = ids[0].peer
  let mut start_counter = ids[0].counter
  let mut last_counter = ids[0].counter
  let mut current_pos = start_pos
  for i = 1; i < ids.length(); i = i + 1 {
    let id = ids[i]
    if id.peer == current_peer && id.counter == last_counter + 1 {
      last_counter = id.counter
      continue
    }
    let span_len = last_counter - start_counter + 1
    let list_pos = match list_pos_at(current_pos) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    spans.push(
      @op.DeleteSpanWithId::new(
        @types.ID::new(current_peer, start_counter),
        list_pos,
        span_len,
      ),
    )
    current_peer = id.peer
    start_counter = id.counter
    last_counter = id.counter
    current_pos = start_pos + i
  }
  let span_len = last_counter - start_counter + 1
  let list_pos = match list_pos_at(current_pos) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  spans.push(
    @op.DeleteSpanWithId::new(
      @types.ID::new(current_peer, start_counter),
      list_pos,
      span_len,
    ),
  )
  Ok(spans)
}

///|
pub fn LoroDoc::list_delete(
  self : LoroDoc,
  handler : @container.ListHandler,
  pos : Int,
  len : Int,
) -> Result[Unit, @types.LoroError] {
  if len <= 0 {
    return Err(@types.LoroError::InternalError("len must be > 0"))
  }
  let end = pos + len
  let ids = match self.state.list_ids_in_range(handler.id(), pos, end) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let spans = match delete_spans_from_ids(ids, pos, p => Ok(p)) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  if spans.length() == 0 {
    return Ok(())
  }
  let need_txn = !self.txn_active && spans.length() > 1
  if need_txn {
    match self.begin_transaction() {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
  }
  for span in spans {
    let op = @op.ListOp::Delete(span)
    match self.apply_list_op(handler, op) {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
  }
  if need_txn {
    match self.commit_transaction() {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
  }
  Ok(())
}

///|
pub fn LoroDoc::list_set(
  self : LoroDoc,
  handler : @container.ListHandler,
  pos : Int,
  value : @types.LoroValue,
) -> Result[Unit, @types.LoroError] {
  let id_full = match self.state.list_id_at(handler.id(), pos) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let need_txn = !self.txn_active
  if need_txn {
    match self.begin_transaction() {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
  }
  let del = @op.DeleteSpanWithId::new(id_full.to_id(), pos, 1)
  let del_op = @op.ListOp::Delete(del)
  match self.apply_list_op(handler, del_op) {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  let slice = @op.ListSlice::RawData([value])
  let ins_op = @op.ListOp::Insert(slice~, pos~)
  match self.apply_list_op(handler, ins_op) {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  if need_txn {
    match self.commit_transaction() {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
  }
  Ok(())
}

///|
pub fn LoroDoc::movable_list_insert(
  self : LoroDoc,
  handler : @container.MovableListHandler,
  pos : Int,
  value : @types.LoroValue,
) -> Result[Unit, @types.LoroError] {
  let slice = @op.ListSlice::RawData([value])
  let op = @op.ListOp::Insert(slice~, pos~)
  self.apply_list_op_to(handler.id(), op)
}

///|
pub fn LoroDoc::movable_list_push(
  self : LoroDoc,
  handler : @container.MovableListHandler,
  value : @types.LoroValue,
) -> Result[Unit, @types.LoroError] {
  let len = match self.state.movable_list_len(handler.id()) {
    Ok(value) => value
    Err(@types.LoroError::InvalidContainer(_)) => 0
    Err(err) => return Err(err)
  }
  self.movable_list_insert(handler, len, value)
}

///|
pub fn LoroDoc::movable_list_delete(
  self : LoroDoc,
  handler : @container.MovableListHandler,
  pos : Int,
  len : Int,
) -> Result[Unit, @types.LoroError] {
  if len <= 0 {
    return Err(@types.LoroError::InternalError("len must be > 0"))
  }
  let end = pos + len
  let ids = match self.state.movable_list_ids_in_range(handler.id(), pos, end) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let spans = match delete_spans_from_ids(ids, pos, p => Ok(p)) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  if spans.length() == 0 {
    return Ok(())
  }
  let need_txn = !self.txn_active && spans.length() > 1
  if need_txn {
    match self.begin_transaction() {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
  }
  for span in spans {
    let op = @op.ListOp::Delete(span)
    match self.apply_list_op_to(handler.id(), op) {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
  }
  if need_txn {
    match self.commit_transaction() {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
  }
  Ok(())
}

///|
pub fn LoroDoc::movable_list_move(
  self : LoroDoc,
  handler : @container.MovableListHandler,
  from : Int,
  to : Int,
) -> Result[Unit, @types.LoroError] {
  if from == to {
    return Ok(())
  }
  let elem_id = match self.state.movable_list_elem_id_at(handler.id(), from) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let op = @op.ListOp::Move(from~, to~, elem_id~)
  self.apply_list_op_to(handler.id(), op)
}

///|
pub fn LoroDoc::movable_list_set(
  self : LoroDoc,
  handler : @container.MovableListHandler,
  pos : Int,
  value : @types.LoroValue,
) -> Result[Unit, @types.LoroError] {
  let elem_id = match self.state.movable_list_elem_id_at(handler.id(), pos) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let op = @op.ListOp::Set(elem_id~, value~)
  self.apply_list_op_to(handler.id(), op)
}

///|
fn LoroDoc::tree_children(
  self : LoroDoc,
  handler : @container.TreeHandler,
  parent : @types.TreeParentId,
) -> Result[Array[@types.TreeID], @types.LoroError] {
  self.state.tree_children(handler.id(), parent)
}

///|
fn LoroDoc::tree_position_for_index(
  self : LoroDoc,
  handler : @container.TreeHandler,
  parent : @types.TreeParentId,
  index : Int,
) -> Result[@types.FractionalIndex, @types.LoroError] {
  let children = match self.tree_children(handler, parent) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  if index < 0 || index > children.length() {
    return Err(@types.LoroError::InternalError("index out of range"))
  }
  let lower = if index > 0 {
    let lower_id = children[index - 1]
    let node = match self.state.tree_node(handler.id(), lower_id) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    Some(node.position)
  } else {
    None
  }
  let upper = if index < children.length() {
    let upper_id = children[index]
    let node = match self.state.tree_node(handler.id(), upper_id) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    Some(node.position)
  } else {
    None
  }
  match @types.FractionalIndex::new(lower, upper) {
    Some(pos) => Ok(pos)
    None => Err(@types.LoroError::InternalError("cannot generate position"))
  }
}

///|
fn LoroDoc::tree_child_index(
  self : LoroDoc,
  handler : @container.TreeHandler,
  parent : @types.TreeParentId,
  target : @types.TreeID,
) -> Result[Int, @types.LoroError] {
  let children = match self.tree_children(handler, parent) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  for i = 0; i < children.length(); i = i + 1 {
    if children[i] == target {
      return Ok(i)
    }
  }
  Err(@types.LoroError::TreeNodeNotFound(target))
}

///|
fn LoroDoc::ensure_tree_container(
  self : LoroDoc,
  handler : @container.TreeHandler,
) -> Unit {
  ignore(self.state.get_or_create(handler.id(), @types.ContainerType::Tree))
}

///|
pub fn LoroDoc::tree_create(
  self : LoroDoc,
  handler : @container.TreeHandler,
  parent : @types.TreeID?,
) -> Result[@types.TreeID, @types.LoroError] {
  self.ensure_tree_container(handler)
  let parent_id = @types.TreeParentId::from_option(parent)
  let children = match self.tree_children(handler, parent_id) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let pos = match
    self.tree_position_for_index(handler, parent_id, children.length()) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let (id, lamport) = alloc_id_and_lamport(self, 1)
  let target = @types.TreeID::from_id(id)
  let op = @op.TreeOp::Create(target~, parent=parent_id, position=pos)
  let raw_op = @op.RawOp::new(
    id,
    lamport,
    handler.id(),
    @op.RawOpContent::Tree(op),
  )
  let persisted = self.arena.to_persisted_op(raw_op)
  let deps = self.oplog.frontiers().clone()
  let meta = self.build_commit_meta()
  let change = @oplog.Change::new_with_meta(
    [persisted],
    deps,
    id,
    lamport,
    meta.timestamp(),
    meta.message(),
    meta.origin(),
  )
  self.oplog.insert_new_change(change, true)
  match self.state.apply_raw_op(self.arena, raw_op) {
    Ok(_) => Ok(target)
    Err(err) => Err(err)
  }
}

///|
pub fn LoroDoc::tree_create_at(
  self : LoroDoc,
  handler : @container.TreeHandler,
  parent : @types.TreeID?,
  index : Int,
) -> Result[@types.TreeID, @types.LoroError] {
  self.ensure_tree_container(handler)
  let parent_id = @types.TreeParentId::from_option(parent)
  let pos = match self.tree_position_for_index(handler, parent_id, index) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let (id, lamport) = alloc_id_and_lamport(self, 1)
  let target = @types.TreeID::from_id(id)
  let op = @op.TreeOp::Create(target~, parent=parent_id, position=pos)
  let raw_op = @op.RawOp::new(
    id,
    lamport,
    handler.id(),
    @op.RawOpContent::Tree(op),
  )
  let persisted = self.arena.to_persisted_op(raw_op)
  let deps = self.oplog.frontiers().clone()
  let meta = self.build_commit_meta()
  let change = @oplog.Change::new_with_meta(
    [persisted],
    deps,
    id,
    lamport,
    meta.timestamp(),
    meta.message(),
    meta.origin(),
  )
  self.oplog.insert_new_change(change, true)
  match self.state.apply_raw_op(self.arena, raw_op) {
    Ok(_) => Ok(target)
    Err(err) => Err(err)
  }
}

///|
pub fn LoroDoc::tree_move(
  self : LoroDoc,
  handler : @container.TreeHandler,
  target : @types.TreeID,
  parent : @types.TreeID?,
) -> Result[Unit, @types.LoroError] {
  let parent_id = @types.TreeParentId::from_option(parent)
  let children = match self.tree_children(handler, parent_id) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let pos = match
    self.tree_position_for_index(handler, parent_id, children.length()) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let op = @op.TreeOp::Move(target~, parent=parent_id, position=pos)
  self.apply_tree_op(handler, op)
}

///|
pub fn LoroDoc::tree_move_to(
  self : LoroDoc,
  handler : @container.TreeHandler,
  target : @types.TreeID,
  parent : @types.TreeID?,
  index : Int,
) -> Result[Unit, @types.LoroError] {
  let parent_id = @types.TreeParentId::from_option(parent)
  let pos = match self.tree_position_for_index(handler, parent_id, index) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let op = @op.TreeOp::Move(target~, parent=parent_id, position=pos)
  self.apply_tree_op(handler, op)
}

///|
pub fn LoroDoc::tree_move_before(
  self : LoroDoc,
  handler : @container.TreeHandler,
  target : @types.TreeID,
  before : @types.TreeID,
) -> Result[Unit, @types.LoroError] {
  let node = match self.state.tree_node(handler.id(), before) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let parent = node.parent
  let idx = match self.tree_child_index(handler, parent, before) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  self.tree_move_to(handler, target, parent.to_option(), idx)
}

///|
pub fn LoroDoc::tree_move_after(
  self : LoroDoc,
  handler : @container.TreeHandler,
  target : @types.TreeID,
  after : @types.TreeID,
) -> Result[Unit, @types.LoroError] {
  let node = match self.state.tree_node(handler.id(), after) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let parent = node.parent
  let idx = match self.tree_child_index(handler, parent, after) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  self.tree_move_to(handler, target, parent.to_option(), idx + 1)
}

///|
pub fn LoroDoc::tree_delete(
  self : LoroDoc,
  handler : @container.TreeHandler,
  target : @types.TreeID,
) -> Result[Unit, @types.LoroError] {
  let op = @op.TreeOp::Delete(target~)
  self.apply_tree_op(handler, op)
}

///|
pub fn LoroDoc::tree_get_meta(
  _self : LoroDoc,
  target : @types.TreeID,
) -> @container.MapHandler {
  let meta_id = target.meta_container()
  @container.MapHandler::new(meta_id)
}

///|
fn LoroDoc::tree_node_value(
  self : LoroDoc,
  handler : @container.TreeHandler,
  node_id : @types.TreeID,
  with_meta : Bool,
) -> Result[@types.LoroValue, @types.LoroError] {
  let children = match
    self.tree_children(handler, @types.TreeParentId::Node(node_id)) {
    Ok(value) => value
    Err(_) => []
  }
  let child_values : Array[@types.LoroValue] = []
  for child in children {
    match self.tree_node_value(handler, child, with_meta) {
      Ok(value) => child_values.push(value)
      Err(err) => return Err(err)
    }
  }
  let map : Map[String, @types.LoroValue] = {}
  map["id"] = @types.LoroValue::String("\{node_id.peer}:\{node_id.counter}")
  map["children"] = @types.LoroValue::List(child_values)
  if with_meta {
    let meta_id = node_id.meta_container()
    map["meta"] = self.state.deep_value_for_container(meta_id)
  }
  Ok(@types.LoroValue::Map(map))
}

///|
pub fn LoroDoc::tree_get_value(
  self : LoroDoc,
  handler : @container.TreeHandler,
) -> Result[@types.LoroValue, @types.LoroError] {
  let roots = match self.tree_children(handler, @types.TreeParentId::Root) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let values : Array[@types.LoroValue] = []
  for root in roots {
    match self.tree_node_value(handler, root, false) {
      Ok(value) => values.push(value)
      Err(err) => return Err(err)
    }
  }
  Ok(@types.LoroValue::List(values))
}

///|
pub fn LoroDoc::tree_get_value_with_meta(
  self : LoroDoc,
  handler : @container.TreeHandler,
) -> Result[@types.LoroValue, @types.LoroError] {
  let roots = match self.tree_children(handler, @types.TreeParentId::Root) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let values : Array[@types.LoroValue] = []
  for root in roots {
    match self.tree_node_value(handler, root, true) {
      Ok(value) => values.push(value)
      Err(err) => return Err(err)
    }
  }
  Ok(@types.LoroValue::List(values))
}

///|
pub fn LoroDoc::map_set(
  self : LoroDoc,
  handler : @container.MapHandler,
  key : String,
  value : @types.LoroValue,
) -> Result[Unit, @types.LoroError] {
  self.apply_map_set(handler, key, Some(value))
}

///|
pub fn LoroDoc::map_insert_container(
  self : LoroDoc,
  handler : @container.MapHandler,
  key : String,
  container_type : @types.ContainerType,
) -> Result[@types.ContainerID, @types.LoroError] {
  let (container_id, id, lamport) = self.alloc_container_id(container_type)
  let map_set = @op.MapSet::new(
    key,
    Some(@types.LoroValue::Container(container_id)),
  )
  match
    self.apply_local_content_with_id(
      id,
      lamport,
      handler.id(),
      @op.RawOpContent::Map(map_set),
    ) {
    Ok(_) => Ok(container_id)
    Err(err) => Err(err)
  }
}

///|
pub fn LoroDoc::map_get_or_create_container(
  self : LoroDoc,
  handler : @container.MapHandler,
  key : String,
  container_type : @types.ContainerType,
) -> Result[@types.ContainerID, @types.LoroError] {
  let existing = match self.state.map_get(handler.id(), key) {
    Ok(value) => value
    Err(@types.LoroError::InvalidContainer(_)) => None
    Err(err) => return Err(err)
  }
  match existing {
    Some(@types.LoroValue::Container(id)) =>
      if id.container_type() != container_type {
        Err(@types.LoroError::InternalError("container type mismatch"))
      } else {
        Ok(id)
      }
    _ => self.map_insert_container(handler, key, container_type)
  }
}

///|
pub fn LoroDoc::map_delete(
  self : LoroDoc,
  handler : @container.MapHandler,
  key : String,
) -> Result[Unit, @types.LoroError] {
  self.apply_map_set(handler, key, None)
}

///|
pub fn LoroDoc::counter_add(
  self : LoroDoc,
  handler : @container.CounterHandler,
  delta : Double,
) -> Result[Unit, @types.LoroError] {
  let op = @op.CounterOp::new(delta)
  self.apply_local_content(handler.id(), @op.RawOpContent::Counter(op))
}

///|
pub fn LoroDoc::counter_inc(
  self : LoroDoc,
  handler : @container.CounterHandler,
  delta : Int,
) -> Result[Unit, @types.LoroError] {
  self.counter_add(handler, delta.to_double())
}

///|
pub fn LoroDoc::counter_value(
  self : LoroDoc,
  handler : @container.CounterHandler,
) -> Result[Double, @types.LoroError] {
  self.state.counter_value(handler.id())
}

///|
pub fn LoroDoc::text_insert(
  self : LoroDoc,
  handler : @container.TextHandler,
  pos : Int,
  text : String,
) -> Result[Unit, @types.LoroError] {
  let slice = @op.ListSlice::from_str(text)
  let list_pos = match self.state.text_text_pos_to_list_pos(handler.id(), pos) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let op = @op.ListOp::Insert(slice~, pos=list_pos)
  self.apply_text_op(handler, op)
}

///|
pub fn LoroDoc::text_to_string(
  self : LoroDoc,
  handler : @container.TextHandler,
) -> Result[String, @types.LoroError] {
  self.state.text_plain_text(handler.id())
}

///|
pub fn LoroDoc::text_slice(
  self : LoroDoc,
  handler : @container.TextHandler,
  start : Int,
  end : Int,
) -> Result[String, @types.LoroError] {
  self.state.text_slice(handler.id(), start, end)
}

///|
pub fn LoroDoc::text_to_delta(
  self : LoroDoc,
  handler : @container.TextHandler,
) -> Result[Array[@types.LoroValue], @types.LoroError] {
  match self.text_get_richtext_value(handler) {
    Ok(@types.LoroValue::List(items)) => Ok(items)
    Ok(_) => Err(@types.LoroError::InternalError("richtext value is not list"))
    Err(err) => Err(err)
  }
}

///|
pub fn LoroDoc::text_diff(
  self : LoroDoc,
  handler : @container.TextHandler,
) -> Result[Array[@types.LoroValue], @types.LoroError] {
  self.text_to_delta(handler)
}

///|
fn LoroDoc::list_diff_from_value(
  _self : LoroDoc,
  value : @types.LoroValue,
) -> Result[Array[@types.LoroValue], @types.LoroError] {
  match value {
    @types.LoroValue::List(items) => {
      let map : Map[String, @types.LoroValue] = {}
      map["insert"] = @types.LoroValue::List(items)
      Ok([@types.LoroValue::Map(map)])
    }
    _ => Err(@types.LoroError::InternalError("list diff expects list value"))
  }
}

///|
pub fn LoroDoc::list_diff(
  self : LoroDoc,
  handler : @container.ListHandler,
) -> Result[Array[@types.LoroValue], @types.LoroError] {
  let value = self.state.deep_value_for_container(handler.id())
  self.list_diff_from_value(value)
}

///|
pub fn LoroDoc::movable_list_diff(
  self : LoroDoc,
  handler : @container.MovableListHandler,
) -> Result[Array[@types.LoroValue], @types.LoroError] {
  let value = self.state.deep_value_for_container(handler.id())
  self.list_diff_from_value(value)
}

///|
pub fn LoroDoc::map_diff(
  self : LoroDoc,
  handler : @container.MapHandler,
) -> Result[Array[@types.LoroValue], @types.LoroError] {
  let value = self.state.deep_value_for_container(handler.id())
  match value {
    @types.LoroValue::Map(map) => {
      let out : Array[@types.LoroValue] = []
      for k, v in map {
        let entry : Map[String, @types.LoroValue] = {}
        entry["key"] = @types.LoroValue::String(k)
        entry["value"] = v
        out.push(@types.LoroValue::Map(entry))
      }
      Ok(out)
    }
    _ => Err(@types.LoroError::InternalError("map diff expects map value"))
  }
}

///|
fn LoroDoc::text_unicode_index_from_utf16(
  self : LoroDoc,
  handler : @container.TextHandler,
  offset : Int,
) -> Result[Int, @types.LoroError] {
  self.state.text_unicode_index_from_utf16(handler.id(), offset)
}

///|
fn LoroDoc::text_unicode_index_from_utf8(
  self : LoroDoc,
  handler : @container.TextHandler,
  offset : Int,
) -> Result[Int, @types.LoroError] {
  self.state.text_unicode_index_from_utf8(handler.id(), offset)
}

///|
fn LoroDoc::text_unicode_range_from_utf16(
  self : LoroDoc,
  handler : @container.TextHandler,
  pos : Int,
  len : Int,
) -> Result[(Int, Int), @types.LoroError] {
  if pos < 0 || len < 0 {
    return Err(@types.LoroError::InternalError("invalid utf16 range"))
  }
  let end = pos + len
  let start_unicode = match self.text_unicode_index_from_utf16(handler, pos) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let end_unicode = match self.text_unicode_index_from_utf16(handler, end) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  Ok((start_unicode, end_unicode))
}

///|
fn LoroDoc::text_unicode_range_from_utf8(
  self : LoroDoc,
  handler : @container.TextHandler,
  pos : Int,
  len : Int,
) -> Result[(Int, Int), @types.LoroError] {
  if pos < 0 || len < 0 {
    return Err(@types.LoroError::InternalError("invalid utf8 range"))
  }
  let end = pos + len
  let start_unicode = match self.text_unicode_index_from_utf8(handler, pos) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let end_unicode = match self.text_unicode_index_from_utf8(handler, end) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  Ok((start_unicode, end_unicode))
}

///|
pub fn LoroDoc::text_insert_utf16(
  self : LoroDoc,
  handler : @container.TextHandler,
  pos : Int,
  text : String,
) -> Result[Unit, @types.LoroError] {
  let unicode_pos = match self.text_unicode_index_from_utf16(handler, pos) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  self.text_insert(handler, unicode_pos, text)
}

///|
pub fn LoroDoc::text_slice_utf16(
  self : LoroDoc,
  handler : @container.TextHandler,
  pos : Int,
  len : Int,
) -> Result[String, @types.LoroError] {
  let (start, end) = match
    self.text_unicode_range_from_utf16(handler, pos, len) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  self.text_slice(handler, start, end)
}

///|
pub fn LoroDoc::text_insert_utf8(
  self : LoroDoc,
  handler : @container.TextHandler,
  pos : Int,
  text : String,
) -> Result[Unit, @types.LoroError] {
  let unicode_pos = match self.text_unicode_index_from_utf8(handler, pos) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  self.text_insert(handler, unicode_pos, text)
}

///|
pub fn LoroDoc::text_slice_utf8(
  self : LoroDoc,
  handler : @container.TextHandler,
  pos : Int,
  len : Int,
) -> Result[String, @types.LoroError] {
  let (start, end) = match
    self.text_unicode_range_from_utf8(handler, pos, len) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  self.text_slice(handler, start, end)
}

///|
pub fn LoroDoc::text_delete(
  self : LoroDoc,
  handler : @container.TextHandler,
  pos : Int,
  len : Int,
) -> Result[Unit, @types.LoroError] {
  if len <= 0 {
    return Err(@types.LoroError::InternalError("len must be > 0"))
  }
  let end = pos + len
  let ids = match self.state.text_ids_in_range(handler.id(), pos, end) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let list_pos_at = (text_pos : Int) => self.state.text_text_index_to_list_pos(
    handler.id(),
    text_pos,
  )
  let spans = match delete_spans_from_ids(ids, pos, list_pos_at) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  if spans.length() == 0 {
    return Ok(())
  }
  let need_txn = !self.txn_active && spans.length() > 1
  if need_txn {
    match self.begin_transaction() {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
  }
  for span in spans {
    let op = @op.ListOp::Delete(span)
    match self.apply_text_op(handler, op) {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
  }
  if need_txn {
    match self.commit_transaction() {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
  }
  Ok(())
}

///|
pub fn LoroDoc::text_delete_utf16(
  self : LoroDoc,
  handler : @container.TextHandler,
  pos : Int,
  len : Int,
) -> Result[Unit, @types.LoroError] {
  let (start, end) = match
    self.text_unicode_range_from_utf16(handler, pos, len) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let unicode_len = end - start
  self.text_delete(handler, start, unicode_len)
}

///|
pub fn LoroDoc::text_delete_utf8(
  self : LoroDoc,
  handler : @container.TextHandler,
  pos : Int,
  len : Int,
) -> Result[Unit, @types.LoroError] {
  let (start, end) = match
    self.text_unicode_range_from_utf8(handler, pos, len) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let unicode_len = end - start
  self.text_delete(handler, start, unicode_len)
}

///|
pub fn LoroDoc::text_mark(
  self : LoroDoc,
  handler : @container.TextHandler,
  start : Int,
  end : Int,
  key : String,
  value : @types.LoroValue,
) -> Result[Unit, @types.LoroError] {
  if start < 0 || end < start {
    return Err(@types.LoroError::InternalError("invalid text range"))
  }
  if start == end {
    return Ok(())
  }
  let info = match self.text_style.style_info(key, false) {
    Some(v) => v
    None => return Err(@types.LoroError::StyleConfigMissing(key))
  }
  let list_start = match
    self.state.text_text_pos_to_list_pos(handler.id(), start) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let list_end = match self.state.text_text_pos_to_list_pos(handler.id(), end) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let need_txn = !self.txn_active
  if need_txn {
    match self.begin_transaction() {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
  }
  let start_op = @op.ListOp::StyleStart(
    start=list_start,
    end=list_end,
    key~,
    info~,
    value~,
  )
  match self.apply_text_op(handler, start_op) {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  let end_op = @op.ListOp::StyleEnd
  match self.apply_text_op(handler, end_op) {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  if need_txn {
    match self.commit_transaction() {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
  }
  Ok(())
}

///|
pub fn LoroDoc::text_mark_utf16(
  self : LoroDoc,
  handler : @container.TextHandler,
  pos : Int,
  len : Int,
  key : String,
  value : @types.LoroValue,
) -> Result[Unit, @types.LoroError] {
  let (start, end) = match
    self.text_unicode_range_from_utf16(handler, pos, len) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  self.text_mark(handler, start, end, key, value)
}

///|
pub fn LoroDoc::text_mark_utf8(
  self : LoroDoc,
  handler : @container.TextHandler,
  pos : Int,
  len : Int,
  key : String,
  value : @types.LoroValue,
) -> Result[Unit, @types.LoroError] {
  let (start, end) = match
    self.text_unicode_range_from_utf8(handler, pos, len) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  self.text_mark(handler, start, end, key, value)
}

///|
pub fn LoroDoc::text_unmark(
  self : LoroDoc,
  handler : @container.TextHandler,
  start : Int,
  end : Int,
  key : String,
) -> Result[Unit, @types.LoroError] {
  if start < 0 || end < start {
    return Err(@types.LoroError::InternalError("invalid text range"))
  }
  if start == end {
    return Ok(())
  }
  let info = match self.text_style.style_info(key, true) {
    Some(v) => v
    None => return Err(@types.LoroError::StyleConfigMissing(key))
  }
  let list_start = match
    self.state.text_text_pos_to_list_pos(handler.id(), start) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let list_end = match self.state.text_text_pos_to_list_pos(handler.id(), end) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let need_txn = !self.txn_active
  if need_txn {
    match self.begin_transaction() {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
  }
  let start_op = @op.ListOp::StyleStart(
    start=list_start,
    end=list_end,
    key~,
    info~,
    value=@types.LoroValue::Null,
  )
  match self.apply_text_op(handler, start_op) {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  let end_op = @op.ListOp::StyleEnd
  match self.apply_text_op(handler, end_op) {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  if need_txn {
    match self.commit_transaction() {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
  }
  Ok(())
}

///|
pub fn LoroDoc::text_unmark_utf16(
  self : LoroDoc,
  handler : @container.TextHandler,
  pos : Int,
  len : Int,
  key : String,
) -> Result[Unit, @types.LoroError] {
  let (start, end) = match
    self.text_unicode_range_from_utf16(handler, pos, len) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  self.text_unmark(handler, start, end, key)
}

///|
pub fn LoroDoc::text_unmark_utf8(
  self : LoroDoc,
  handler : @container.TextHandler,
  pos : Int,
  len : Int,
  key : String,
) -> Result[Unit, @types.LoroError] {
  let (start, end) = match
    self.text_unicode_range_from_utf8(handler, pos, len) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  self.text_unmark(handler, start, end, key)
}

///|
pub fn LoroDoc::text_get_richtext_value(
  self : LoroDoc,
  handler : @container.TextHandler,
) -> Result[@types.LoroValue, @types.LoroError] {
  self.state.text_richtext_value(handler.id())
}

///|
pub fn LoroDoc::get_deep_value(self : LoroDoc) -> @types.LoroValue {
  self.state.get_deep_value()
}

///|
pub fn LoroDoc::oplog_vv(self : LoroDoc) -> @types.VersionVector {
  self.oplog.vv()
}

///|
pub fn LoroDoc::version(self : LoroDoc) -> @types.VersionVector {
  self.oplog.vv()
}

///|
pub fn LoroDoc::oplog_frontiers(self : LoroDoc) -> @types.Frontiers {
  self.oplog.frontiers().clone()
}

///|
pub fn LoroDoc::frontiers_to_vv(
  self : LoroDoc,
  frontiers : @types.Frontiers,
) -> Result[@types.VersionVector, @types.LoroError] {
  self.oplog.frontiers_to_vv(frontiers)
}

///|
pub fn LoroDoc::vv_to_frontiers(
  self : LoroDoc,
  vv : @types.VersionVector,
) -> @types.Frontiers {
  self.oplog.vv_to_frontiers(vv)
}

///|
fn trim_change_by_vv(
  change : @oplog.Change,
  vv : @types.VersionVector,
) -> @oplog.Change? {
  let end = vv.get(change.id.peer)
  if change.id.counter >= end {
    return Some(change)
  }
  let change_end = change.id.counter + change.len()
  if change_end <= end {
    return None
  }
  let offset = end - change.id.counter
  Some(change.slice(offset, change.len()))
}

///|
fn LoroDoc::changes_until_vv(
  self : LoroDoc,
  vv : @types.VersionVector,
) -> Array[@oplog.Change] {
  let changes = self.oplog.all_changes()
  let out : Array[@oplog.Change] = []
  for change in changes {
    let change_id = change.id()
    let end = change_id.counter + change.len()
    let vv_end = vv.get(change_id.peer)
    if vv_end <= change_id.counter {
      continue
    }
    if vv_end >= end {
      out.push(change)
    } else {
      let slice_end = vv_end - change_id.counter
      if slice_end > 0 {
        out.push(change.slice(0, slice_end))
      }
    }
  }
  out
}

///|
pub fn LoroDoc::export_updates_from(
  self : LoroDoc,
  from : @types.VersionVector?,
) -> Result[Bytes, @types.LoroError] {
  let changes = self.oplog.all_changes()
  match from {
    None => @encoding.encode_changes(self.arena, changes)
    Some(vv) => {
      let trimmed : Array[@oplog.Change] = []
      for change in changes {
        match trim_change_by_vv(change, vv) {
          Some(value) => trimmed.push(value)
          None => ()
        }
      }
      @encoding.encode_changes(self.arena, trimmed)
    }
  }
}

///|
pub fn LoroDoc::export_from(
  self : LoroDoc,
  from : @types.VersionVector?,
) -> Result[Bytes, @types.LoroError] {
  self.export_updates_from(from)
}

///|
pub fn LoroDoc::checkout(
  self : LoroDoc,
  frontiers : @types.Frontiers,
) -> Result[Unit, @types.LoroError] {
  let vv = match self.oplog.frontiers_to_vv(frontiers) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let changes = self.changes_until_vv(vv)
  let next_state = @state.DocState::new()
  for change in changes {
    let base_vv = match self.oplog.frontiers_to_vv(change.deps()) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let local_vv = base_vv
    let change_id = change.id()
    let base_lamport = change.lamport()
    for op in change.ops() {
      let counter = op.counter()
      let offset = counter - change_id.counter
      let op_lamport = base_lamport + offset.reinterpret_as_uint()
      let id = @types.ID::new(change_id.peer, counter)
      match
        next_state.apply_op_with_vv(self.arena, op, id, op_lamport, local_vv) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      let len = op.content_len()
      if len > 0 {
        let last_id = @types.ID::new(change_id.peer, counter + len - 1)
        local_vv.extend_to_include_last_id(last_id)
      }
    }
  }
  self.state = next_state
  self.emit_snapshot()
  Ok(())
}

///|
pub fn LoroDoc::fork_at(
  self : LoroDoc,
  frontiers : @types.Frontiers,
) -> Result[LoroDoc, @types.LoroError] {
  let vv = match self.oplog.frontiers_to_vv(frontiers) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let changes = self.changes_until_vv(vv)
  let bytes = match @encoding.encode_changes(self.arena, changes) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  let new_doc = LoroDoc::new()
  match new_doc.import_updates(bytes) {
    Ok(_) => ()
    Err(err) => return Err(err)
  }
  Ok(new_doc)
}

///|
pub fn LoroDoc::export_bytes(
  self : LoroDoc,
  mode : @types.ExportMode,
) -> Result[Bytes, @types.LoroError] {
  match mode {
    @types.ExportMode::Snapshot => {
      let changes = self.oplog.all_changes()
      @encoding.encode_snapshot(self.arena, self.state, changes)
    }
    @types.ExportMode::Updates(from) => self.export_updates_from(from)
  }
}

///|
pub fn LoroDoc::export_updates(
  self : LoroDoc,
) -> Result[Bytes, @types.LoroError] {
  self.export_updates_from(None)
}

///|
pub fn LoroDoc::export_loro_updates(
  self : LoroDoc,
) -> Result[Bytes, @types.LoroError] {
  let changes = self.oplog.all_changes()
  @encoding.encode_loro_updates(self.arena, changes)
}

///|
pub fn LoroDoc::export_loro_snapshot(
  self : LoroDoc,
) -> Result[Bytes, @types.LoroError] {
  let changes = self.oplog.all_changes()
  @encoding.encode_loro_snapshot(self.arena, self.state, changes)
}

///|
priv enum ApplyState {
  Applied
  CanApply
  Awaiting
}

///|
fn change_apply_state(
  vv : @types.VersionVector,
  change : @encoding.DecodedChange,
) -> ApplyState {
  let span_start = change.id.counter
  let span_end = span_start + change.len()
  let vv_latest_ctr = vv.get(change.id.peer)
  if vv_latest_ctr >= span_end {
    return ApplyState::Applied
  }
  if vv_latest_ctr < span_start {
    return ApplyState::Awaiting
  }
  for dep in change.deps.iter() {
    if !vv.includes_id(dep) {
      return ApplyState::Awaiting
    }
  }
  ApplyState::CanApply
}

///|
fn LoroDoc::apply_decoded_change(
  self : LoroDoc,
  change : @encoding.DecodedChange,
) -> Result[Unit, @types.LoroError] {
  match self.oplog.get_change(change.id) {
    Some(_) => return Ok(())
    None => ()
  }
  let ops : Array[@op.Op] = []
  let mut offset = 0
  for entry in change.ops {
    let content_len = entry.content.content_len()
    let id = change.id.inc(offset)
    let lamport = change.lamport + offset.reinterpret_as_uint()
    let raw_op = @op.RawOp::new(id, lamport, entry.container, entry.content)
    let persisted = self.arena.to_persisted_op(raw_op)
    ops.push(persisted)
    match self.state.apply_raw_op(self.arena, raw_op) {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
    offset = offset + content_len
  }
  let new_change = @oplog.Change::new_with_meta(
    ops,
    change.deps,
    change.id,
    change.lamport,
    change.timestamp,
    change.commit_msg,
    change.origin,
  )
  self.oplog.insert_new_change(new_change, false)
  match self.oplog.get_change(change.id) {
    Some(saved) => self.emit_change(saved, false)
    None => ()
  }
  let change_end = change.lamport + offset.reinterpret_as_uint()
  if change_end > self.lamport {
    self.lamport = change_end
  }
  if change.id.peer == self.peer {
    let local_end = change.id.counter + offset
    if local_end > self.counter {
      self.counter = local_end
    }
  }
  Ok(())
}

///|
fn LoroDoc::apply_decoded_change_to_state_and_oplog(
  self : LoroDoc,
  change : @encoding.DecodedChange,
) -> Result[Unit, @types.LoroError] {
  match self.oplog.get_change(change.id) {
    Some(_) => return Ok(())
    None => ()
  }
  let ops : Array[@op.Op] = []
  let mut offset = 0
  for entry in change.ops {
    let content_len = entry.content.content_len()
    let id = change.id.inc(offset)
    let lamport = change.lamport + offset.reinterpret_as_uint()
    let raw_op = @op.RawOp::new(id, lamport, entry.container, entry.content)
    let persisted = self.arena.to_persisted_op(raw_op)
    ops.push(persisted)
    match self.state.apply_raw_op(self.arena, raw_op) {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
    offset = offset + content_len
  }
  let new_change = @oplog.Change::new_with_meta(
    ops,
    change.deps,
    change.id,
    change.lamport,
    change.timestamp,
    change.commit_msg,
    change.origin,
  )
  self.oplog.insert_new_change(new_change, false)
  let change_end = change.lamport + offset.reinterpret_as_uint()
  if change_end > self.lamport {
    self.lamport = change_end
  }
  if change.id.peer == self.peer {
    let local_end = change.id.counter + offset
    if local_end > self.counter {
      self.counter = local_end
    }
  }
  Ok(())
}

///|
fn LoroDoc::apply_decoded_change_to_oplog(
  self : LoroDoc,
  change : @encoding.DecodedChange,
) -> Result[Unit, @types.LoroError] {
  match self.oplog.get_change(change.id) {
    Some(_) => return Ok(())
    None => ()
  }
  let ops : Array[@op.Op] = []
  let mut offset = 0
  for entry in change.ops {
    let content_len = entry.content.content_len()
    let id = change.id.inc(offset)
    let lamport = change.lamport + offset.reinterpret_as_uint()
    let raw_op = @op.RawOp::new(id, lamport, entry.container, entry.content)
    let persisted = self.arena.to_persisted_op(raw_op)
    ops.push(persisted)
    offset = offset + content_len
  }
  let new_change = @oplog.Change::new_with_meta(
    ops,
    change.deps,
    change.id,
    change.lamport,
    change.timestamp,
    change.commit_msg,
    change.origin,
  )
  self.oplog.insert_new_change(new_change, false)
  let change_end = change.lamport + offset.reinterpret_as_uint()
  if change_end > self.lamport {
    self.lamport = change_end
  }
  if change.id.peer == self.peer {
    let local_end = change.id.counter + offset
    if local_end > self.counter {
      self.counter = local_end
    }
  }
  Ok(())
}

///|
pub fn LoroDoc::import_updates(
  self : LoroDoc,
  bytes : Bytes,
) -> Result[Unit, @types.LoroError] {
  let decoded = match @encoding.decode_changes(bytes) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  self.apply_decoded_changes(decoded)
}

///|
fn LoroDoc::apply_decoded_changes(
  self : LoroDoc,
  decoded : Array[@encoding.DecodedChange],
) -> Result[Unit, @types.LoroError] {
  let mut pending = decoded
  let mut applied_any = false
  let mut progressed = true
  while progressed {
    progressed = false
    let next_pending : Array[@encoding.DecodedChange] = []
    for change in pending {
      match change_apply_state(self.oplog.vv(), change) {
        ApplyState::Applied => ()
        ApplyState::CanApply =>
          match self.apply_decoded_change(change) {
            Ok(_) => {
              progressed = true
              applied_any = true
            }
            Err(err) => return Err(err)
          }
        ApplyState::Awaiting => next_pending.push(change)
      }
    }
    pending = next_pending
  }
  if pending.length() > 0 {
    return Err(@types.LoroError::MissingDependency("missing dependencies"))
  }
  if applied_any {
    match self.rebuild_state_from_oplog() {
      Ok(_) => ()
      Err(err) => return Err(err)
    }
  }
  Ok(())
}

///|
fn LoroDoc::rebuild_state_from_oplog(
  self : LoroDoc,
) -> Result[Unit, @types.LoroError] {
  let new_state = @state.DocState::new()
  let changes = self.oplog.changes_sorted()
  for change in changes {
    let base_vv = match self.oplog.frontiers_to_vv(change.deps()) {
      Ok(value) => value
      Err(err) => return Err(err)
    }
    let vv = base_vv
    let base_id = change.id()
    let base_lamport = change.lamport()
    for op in change.ops() {
      let counter = op.counter()
      let offset = counter - base_id.counter
      let lamport = base_lamport + offset.reinterpret_as_uint()
      let id = @types.ID::new(base_id.peer, counter)
      match new_state.apply_op_with_vv(self.arena, op, id, lamport, vv) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
      let len = op.content_len()
      if len > 0 {
        let last_id = @types.ID::new(base_id.peer, counter + len - 1)
        vv.extend_to_include_last_id(last_id)
      }
    }
  }
  self.state = new_state
  Ok(())
}

///|
fn LoroDoc::apply_decoded_snapshot(
  self : LoroDoc,
  snapshot : @encoding.DecodedSnapshot,
) -> Result[Unit, @types.LoroError] {
  self.state = snapshot.state
  self.oplog = @oplog.OpLog::new()
  self.arena = @arena.SharedArena::new()
  self.counter = 0
  self.lamport = 0
  if snapshot.needs_replay {
    for change in snapshot.changes {
      match self.apply_decoded_change_to_state_and_oplog(change) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
    }
  } else {
    for change in snapshot.changes {
      match self.apply_decoded_change_to_oplog(change) {
        Ok(_) => ()
        Err(err) => return Err(err)
      }
    }
  }
  self.emit_snapshot()
  Ok(())
}

///|
pub fn LoroDoc::import_bytes(
  self : LoroDoc,
  bytes : Bytes,
) -> Result[Unit, @types.LoroError] {
  let decoded = match @encoding.decode_payload(bytes) {
    Ok(value) => value
    Err(err) => return Err(err)
  }
  match decoded {
    @encoding.DecodedPayload::Updates(changes) =>
      self.apply_decoded_changes(changes)
    @encoding.DecodedPayload::Snapshot(snapshot) =>
      self.apply_decoded_snapshot(snapshot)
  }
}
