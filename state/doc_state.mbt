///|
// Document state for map/list/text containers.
pub enum ContainerState {
  MapState(MapState)
  ListState(ListState)
  TextState(TextState)
  MovableListState(MovableListState)
  TreeState(TreeState)
  CounterState(CounterState)
} derive(Show)

///|
pub struct DocState {
  containers : Map[@types.ContainerID, ContainerState]
} derive(Show)

///|
pub fn DocState::new() -> DocState {
  DocState::{ containers: Map::new() }
}

///|
pub fn DocState::get_or_create(
  self : DocState,
  id : @types.ContainerID,
  container_type : @types.ContainerType,
) -> ContainerState {
  match self.containers.get(id) {
    Some(state) => state
    None => {
      let state = match container_type {
        @types.ContainerType::Map => ContainerState::MapState(MapState::new())
        @types.ContainerType::List =>
          ContainerState::ListState(ListState::new())
        @types.ContainerType::Text =>
          ContainerState::TextState(TextState::new())
        @types.ContainerType::MovableList =>
          ContainerState::MovableListState(MovableListState::new())
        @types.ContainerType::Tree =>
          ContainerState::TreeState(TreeState::new())
        @types.ContainerType::Counter =>
          ContainerState::CounterState(CounterState::new())
        _ => ContainerState::MapState(MapState::new())
      }
      self.containers[id] = state
      state
    }
  }
}

///|
pub fn DocState::apply_raw_op(
  self : DocState,
  arena : @arena.SharedArena,
  raw_op : @op.RawOp,
) -> Result[Unit, @types.LoroError] {
  let id = raw_op.container()
  let container_type = id.container_type()
  let base_id = raw_op.id_full()
  let op = arena.to_persisted_op(raw_op)
  let state = match self.containers.get(id) {
    Some(existing) => existing
    None => {
      let created = match container_type {
        @types.ContainerType::Map => ContainerState::MapState(MapState::new())
        @types.ContainerType::List =>
          ContainerState::ListState(ListState::new())
        @types.ContainerType::Text =>
          ContainerState::TextState(TextState::new())
        @types.ContainerType::MovableList =>
          ContainerState::MovableListState(MovableListState::new())
        @types.ContainerType::Tree =>
          ContainerState::TreeState(TreeState::new())
        @types.ContainerType::Counter =>
          ContainerState::CounterState(CounterState::new())
        _ => ContainerState::MapState(MapState::new())
      }
      self.containers[id] = created
      created
    }
  }
  let updated = match (container_type, state, op.content()) {
    (
      @types.ContainerType::Map,
      ContainerState::MapState(map_state),
      @op.InnerContent::Map(map_set),
    ) => {
      let key = map_set.key()
      match map_set.value() {
        Some(v) => map_state.set(key, v, base_id)
        None => map_state.delete(key, base_id)
      }
      ContainerState::MapState(map_state)
    }
    (
      @types.ContainerType::List,
      ContainerState::ListState(list_state),
      @op.InnerContent::List(inner),
    ) =>
      match list_state.apply_inner_op(arena, inner, base_id) {
        Ok(_) => ContainerState::ListState(list_state)
        Err(err) => return Err(err)
      }
    (
      @types.ContainerType::Text,
      ContainerState::TextState(text_state),
      @op.InnerContent::List(inner),
    ) =>
      match text_state.apply_inner_op(inner, base_id) {
        Ok(_) => ContainerState::TextState(text_state)
        Err(err) => return Err(err)
      }
    (
      @types.ContainerType::MovableList,
      ContainerState::MovableListState(list_state),
      @op.InnerContent::List(inner),
    ) =>
      match list_state.apply_inner_op(arena, inner, base_id) {
        Ok(_) => ContainerState::MovableListState(list_state)
        Err(err) => return Err(err)
      }
    (
      @types.ContainerType::Tree,
      ContainerState::TreeState(tree_state),
      @op.InnerContent::Tree(tree_op),
    ) =>
      match tree_state.apply_op(tree_op, base_id) {
        Ok(_) => ContainerState::TreeState(tree_state)
        Err(err) => return Err(err)
      }
    (
      @types.ContainerType::Counter,
      ContainerState::CounterState(counter_state),
      @op.InnerContent::Counter(counter_op),
    ) => {
      counter_state.apply(counter_op.delta())
      ContainerState::CounterState(counter_state)
    }
    _ => return Err(@types.LoroError::Unsupported("op/container mismatch"))
  }
  self.containers[id] = updated
  Ok(())
}

///|
pub fn DocState::apply_op(
  self : DocState,
  arena : @arena.SharedArena,
  op : @op.Op,
  id : @types.ID,
  lamport : @types.Lamport,
) -> Result[Unit, @types.LoroError] {
  let container_id = op.container()
  let container_type = container_id.container_type()
  let base_id = @types.IdFull::new(id.peer, id.counter, lamport)
  let state = match self.containers.get(container_id) {
    Some(existing) => existing
    None => {
      let created = match container_type {
        @types.ContainerType::Map => ContainerState::MapState(MapState::new())
        @types.ContainerType::List =>
          ContainerState::ListState(ListState::new())
        @types.ContainerType::Text =>
          ContainerState::TextState(TextState::new())
        @types.ContainerType::MovableList =>
          ContainerState::MovableListState(MovableListState::new())
        @types.ContainerType::Tree =>
          ContainerState::TreeState(TreeState::new())
        @types.ContainerType::Counter =>
          ContainerState::CounterState(CounterState::new())
        _ => ContainerState::MapState(MapState::new())
      }
      self.containers[container_id] = created
      created
    }
  }
  let updated = match (container_type, state, op.content()) {
    (
      @types.ContainerType::Map,
      ContainerState::MapState(map_state),
      @op.InnerContent::Map(map_set),
    ) => {
      let key = map_set.key()
      match map_set.value() {
        Some(v) => map_state.set(key, v, base_id)
        None => map_state.delete(key, base_id)
      }
      ContainerState::MapState(map_state)
    }
    (
      @types.ContainerType::List,
      ContainerState::ListState(list_state),
      @op.InnerContent::List(inner),
    ) =>
      match list_state.apply_inner_op(arena, inner, base_id) {
        Ok(_) => ContainerState::ListState(list_state)
        Err(err) => return Err(err)
      }
    (
      @types.ContainerType::Text,
      ContainerState::TextState(text_state),
      @op.InnerContent::List(inner),
    ) =>
      match text_state.apply_inner_op(inner, base_id) {
        Ok(_) => ContainerState::TextState(text_state)
        Err(err) => return Err(err)
      }
    (
      @types.ContainerType::MovableList,
      ContainerState::MovableListState(list_state),
      @op.InnerContent::List(inner),
    ) =>
      match list_state.apply_inner_op(arena, inner, base_id) {
        Ok(_) => ContainerState::MovableListState(list_state)
        Err(err) => return Err(err)
      }
    (
      @types.ContainerType::Tree,
      ContainerState::TreeState(tree_state),
      @op.InnerContent::Tree(tree_op),
    ) =>
      match tree_state.apply_op(tree_op, base_id) {
        Ok(_) => ContainerState::TreeState(tree_state)
        Err(err) => return Err(err)
      }
    (
      @types.ContainerType::Counter,
      ContainerState::CounterState(counter_state),
      @op.InnerContent::Counter(counter_op),
    ) => {
      counter_state.apply(counter_op.delta())
      ContainerState::CounterState(counter_state)
    }
    _ => return Err(@types.LoroError::Unsupported("op/container mismatch"))
  }
  self.containers[container_id] = updated
  Ok(())
}

///|
pub fn DocState::container_items(
  self : DocState,
) -> Array[(@types.ContainerID, ContainerState)] {
  let out : Array[(@types.ContainerID, ContainerState)] = []
  for id, state in self.containers {
    out.push((id, state))
  }
  out
}

///|
pub fn DocState::set_container_state(
  self : DocState,
  id : @types.ContainerID,
  state : ContainerState,
) -> Unit {
  self.containers[id] = state
}

///|
pub fn DocState::set_map_state(
  self : DocState,
  id : @types.ContainerID,
  state : MapState,
) -> Unit {
  self.containers[id] = ContainerState::MapState(state)
}

///|
pub fn DocState::set_list_state(
  self : DocState,
  id : @types.ContainerID,
  state : ListState,
) -> Unit {
  self.containers[id] = ContainerState::ListState(state)
}

///|
pub fn DocState::set_text_state(
  self : DocState,
  id : @types.ContainerID,
  state : TextState,
) -> Unit {
  self.containers[id] = ContainerState::TextState(state)
}

///|
pub fn DocState::set_movable_list_state(
  self : DocState,
  id : @types.ContainerID,
  state : MovableListState,
) -> Unit {
  self.containers[id] = ContainerState::MovableListState(state)
}

///|
pub fn DocState::set_tree_state(
  self : DocState,
  id : @types.ContainerID,
  state : TreeState,
) -> Unit {
  self.containers[id] = ContainerState::TreeState(state)
}

///|
pub fn DocState::set_counter_state(
  self : DocState,
  id : @types.ContainerID,
  state : CounterState,
) -> Unit {
  self.containers[id] = ContainerState::CounterState(state)
}

///|
pub fn DocState::list_id_at(
  self : DocState,
  id : @types.ContainerID,
  index : Int,
) -> Result[@types.IdFull, @types.LoroError] {
  match self.containers.get(id) {
    Some(ContainerState::ListState(list_state)) => list_state.id_at(index)
    _ => Err(@types.LoroError::InvalidContainer("list not found"))
  }
}

///|
pub fn DocState::text_id_at(
  self : DocState,
  id : @types.ContainerID,
  index : Int,
) -> Result[@types.IdFull, @types.LoroError] {
  match self.containers.get(id) {
    Some(ContainerState::TextState(text_state)) => text_state.id_at(index)
    _ => Err(@types.LoroError::InvalidContainer("text not found"))
  }
}

///|
pub fn DocState::movable_list_id_at(
  self : DocState,
  id : @types.ContainerID,
  index : Int,
) -> Result[@types.IdFull, @types.LoroError] {
  match self.containers.get(id) {
    Some(ContainerState::MovableListState(list_state)) =>
      list_state.id_at(index)
    _ => Err(@types.LoroError::InvalidContainer("movable list not found"))
  }
}

///|
pub fn DocState::movable_list_elem_id_at(
  self : DocState,
  id : @types.ContainerID,
  index : Int,
) -> Result[@types.IdLp, @types.LoroError] {
  match self.containers.get(id) {
    Some(ContainerState::MovableListState(list_state)) =>
      list_state.elem_id_at(index)
    _ => Err(@types.LoroError::InvalidContainer("movable list not found"))
  }
}

///|
pub fn DocState::list_len(
  self : DocState,
  id : @types.ContainerID,
) -> Result[Int, @types.LoroError] {
  match self.containers.get(id) {
    Some(ContainerState::ListState(list_state)) => Ok(list_state.len())
    _ => Err(@types.LoroError::InvalidContainer("list not found"))
  }
}

///|
pub fn DocState::list_value_at(
  self : DocState,
  id : @types.ContainerID,
  index : Int,
) -> Result[@types.LoroValue?, @types.LoroError] {
  match self.containers.get(id) {
    Some(ContainerState::ListState(list_state)) => list_state.value_at(index)
    _ => Err(@types.LoroError::InvalidContainer("list not found"))
  }
}

///|
pub fn DocState::movable_list_value_at(
  self : DocState,
  id : @types.ContainerID,
  index : Int,
) -> Result[@types.LoroValue?, @types.LoroError] {
  match self.containers.get(id) {
    Some(ContainerState::MovableListState(list_state)) =>
      list_state.value_at(index)
    _ => Err(@types.LoroError::InvalidContainer("movable list not found"))
  }
}

///|
pub fn DocState::text_len(
  self : DocState,
  id : @types.ContainerID,
) -> Result[Int, @types.LoroError] {
  match self.containers.get(id) {
    Some(ContainerState::TextState(text_state)) => Ok(text_state.len())
    _ => Err(@types.LoroError::InvalidContainer("text not found"))
  }
}

///|
pub fn DocState::text_plain_text(
  self : DocState,
  id : @types.ContainerID,
) -> Result[String, @types.LoroError] {
  match self.containers.get(id) {
    Some(ContainerState::TextState(text_state)) => Ok(text_state.plain_text())
    _ => Err(@types.LoroError::InvalidContainer("text not found"))
  }
}

///|
pub fn DocState::text_styles(
  self : DocState,
  id : @types.ContainerID,
) -> Result[Array[StyleSpan], @types.LoroError] {
  match self.containers.get(id) {
    Some(ContainerState::TextState(text_state)) => Ok(text_state.styles())
    _ => Err(@types.LoroError::InvalidContainer("text not found"))
  }
}

///|
pub fn DocState::text_list_pos_to_text_pos(
  self : DocState,
  id : @types.ContainerID,
  list_pos : Int,
) -> Result[Int, @types.LoroError] {
  match self.containers.get(id) {
    Some(ContainerState::TextState(text_state)) =>
      Ok(text_state.list_pos_to_text_pos(list_pos))
    _ => Err(@types.LoroError::InvalidContainer("text not found"))
  }
}

///|
pub fn DocState::text_text_pos_to_list_pos(
  self : DocState,
  id : @types.ContainerID,
  text_pos : Int,
) -> Result[Int, @types.LoroError] {
  match self.containers.get(id) {
    Some(ContainerState::TextState(text_state)) =>
      Ok(text_state.text_pos_to_list_pos(text_pos))
    None => {
      let container_type = id.container_type()
      if container_type == @types.ContainerType::Text ||
        container_type == @types.ContainerType::RichText {
        Ok(0)
      } else {
        Err(@types.LoroError::InvalidContainer("text not found"))
      }
    }
    _ => Err(@types.LoroError::InvalidContainer("text not found"))
  }
}

///|
pub fn DocState::text_slice(
  self : DocState,
  id : @types.ContainerID,
  start : Int,
  end : Int,
) -> Result[String, @types.LoroError] {
  match self.containers.get(id) {
    Some(ContainerState::TextState(text_state)) => text_state.slice(start, end)
    _ => Err(@types.LoroError::InvalidContainer("text not found"))
  }
}

///|
pub fn DocState::text_unicode_index_from_utf16(
  self : DocState,
  id : @types.ContainerID,
  offset : Int,
) -> Result[Int, @types.LoroError] {
  match self.containers.get(id) {
    Some(ContainerState::TextState(text_state)) =>
      text_state.unicode_index_from_utf16(offset)
    None => {
      let container_type = id.container_type()
      if container_type == @types.ContainerType::Text ||
        container_type == @types.ContainerType::RichText {
        Ok(0)
      } else {
        Err(@types.LoroError::InvalidContainer("text not found"))
      }
    }
    _ => Err(@types.LoroError::InvalidContainer("text not found"))
  }
}

///|
pub fn DocState::text_unicode_index_from_utf8(
  self : DocState,
  id : @types.ContainerID,
  offset : Int,
) -> Result[Int, @types.LoroError] {
  match self.containers.get(id) {
    Some(ContainerState::TextState(text_state)) =>
      text_state.unicode_index_from_utf8(offset)
    None => {
      let container_type = id.container_type()
      if container_type == @types.ContainerType::Text ||
        container_type == @types.ContainerType::RichText {
        Ok(0)
      } else {
        Err(@types.LoroError::InvalidContainer("text not found"))
      }
    }
    _ => Err(@types.LoroError::InvalidContainer("text not found"))
  }
}

///|
pub fn DocState::text_richtext_value(
  self : DocState,
  id : @types.ContainerID,
) -> Result[@types.LoroValue, @types.LoroError] {
  match self.containers.get(id) {
    Some(ContainerState::TextState(text_state)) =>
      Ok(text_state.to_richtext_value())
    _ => Err(@types.LoroError::InvalidContainer("text not found"))
  }
}

///|
pub fn DocState::movable_list_len(
  self : DocState,
  id : @types.ContainerID,
) -> Result[Int, @types.LoroError] {
  match self.containers.get(id) {
    Some(ContainerState::MovableListState(list_state)) => Ok(list_state.len())
    _ => Err(@types.LoroError::InvalidContainer("movable list not found"))
  }
}

///|
pub fn DocState::tree_children(
  self : DocState,
  id : @types.ContainerID,
  parent : @types.TreeParentId,
) -> Result[Array[@types.TreeID], @types.LoroError] {
  match self.containers.get(id) {
    Some(ContainerState::TreeState(tree_state)) =>
      match tree_state.children(parent) {
        Some(children) => Ok(children)
        None => Err(@types.LoroError::InvalidContainer("tree parent not found"))
      }
    _ => Err(@types.LoroError::InvalidContainer("tree not found"))
  }
}

///|
pub fn DocState::tree_node(
  self : DocState,
  id : @types.ContainerID,
  target : @types.TreeID,
) -> Result[TreeNode, @types.LoroError] {
  match self.containers.get(id) {
    Some(ContainerState::TreeState(tree_state)) =>
      match tree_state.get_node(target) {
        Some(node) => Ok(node)
        None => Err(@types.LoroError::TreeNodeNotFound(target))
      }
    _ => Err(@types.LoroError::InvalidContainer("tree not found"))
  }
}

///|
pub fn DocState::map_value(
  self : DocState,
  id : @types.ContainerID,
) -> @types.LoroValue? {
  match self.containers.get(id) {
    Some(ContainerState::MapState(map_state)) => Some(map_state.to_value())
    _ => None
  }
}

///|
pub fn DocState::counter_value(
  self : DocState,
  id : @types.ContainerID,
) -> Result[Double, @types.LoroError] {
  match self.containers.get(id) {
    Some(ContainerState::CounterState(counter_state)) =>
      Ok(counter_state.value())
    _ => Err(@types.LoroError::InvalidContainer("counter not found"))
  }
}

///|
pub fn DocState::deep_value_for_container(
  self : DocState,
  id : @types.ContainerID,
) -> @types.LoroValue {
  let seen : Map[@types.ContainerID, Bool] = {}
  self.container_deep_value(id, seen)
}

///|
pub fn DocState::map_get(
  self : DocState,
  id : @types.ContainerID,
  key : String,
) -> Result[@types.LoroValue?, @types.LoroError] {
  match self.containers.get(id) {
    Some(ContainerState::MapState(map_state)) => Ok(map_state.get(key))
    _ => Err(@types.LoroError::InvalidContainer("map not found"))
  }
}

///|
fn DocState::empty_container_value(
  _self : DocState,
  container_type : @types.ContainerType,
) -> @types.LoroValue {
  match container_type {
    @types.ContainerType::Map => @types.LoroValue::Map({})
    @types.ContainerType::List => @types.LoroValue::List([])
    @types.ContainerType::Text => @types.LoroValue::String("")
    @types.ContainerType::MovableList => @types.LoroValue::List([])
    @types.ContainerType::Tree => @types.LoroValue::List([])
    @types.ContainerType::Counter => @types.LoroValue::F64(0.0)
    _ => @types.LoroValue::Null
  }
}

///|
fn DocState::tree_node_value(
  self : DocState,
  tree_state : TreeState,
  node_id : @types.TreeID,
  seen : Map[@types.ContainerID, Bool],
) -> @types.LoroValue {
  let children = match tree_state.children(@types.TreeParentId::Node(node_id)) {
    Some(value) => value
    None => []
  }
  let child_values : Array[@types.LoroValue] = []
  for child in children {
    child_values.push(self.tree_node_value(tree_state, child, seen))
  }
  let map : Map[String, @types.LoroValue] = {}
  map["id"] = @types.LoroValue::String("\{node_id.peer}:\{node_id.counter}")
  map["children"] = @types.LoroValue::List(child_values)
  let meta_id = node_id.meta_container()
  let meta_value = match self.map_value(meta_id) {
    Some(value) => self.resolve_value_inner(value, seen)
    None => @types.LoroValue::Map({})
  }
  map["meta"] = meta_value
  @types.LoroValue::Map(map)
}

///|
fn DocState::container_deep_value(
  self : DocState,
  id : @types.ContainerID,
  seen : Map[@types.ContainerID, Bool],
) -> @types.LoroValue {
  if seen.get(id) is Some(true) {
    return @types.LoroValue::Null
  }
  seen[id] = true
  match self.containers.get(id) {
    Some(ContainerState::MapState(map_state)) =>
      self.resolve_value_inner(map_state.to_value(), seen)
    Some(ContainerState::ListState(list_state)) =>
      self.resolve_value_inner(list_state.to_value(), seen)
    Some(ContainerState::TextState(text_state)) => text_state.to_value()
    Some(ContainerState::MovableListState(list_state)) =>
      self.resolve_value_inner(list_state.to_value(), seen)
    Some(ContainerState::TreeState(tree_state)) => {
      let roots = tree_state.roots()
      let items : Array[@types.LoroValue] = []
      for root in roots {
        items.push(self.tree_node_value(tree_state, root, seen))
      }
      @types.LoroValue::List(items)
    }
    Some(ContainerState::CounterState(counter_state)) =>
      counter_state.to_value()
    None => self.empty_container_value(id.container_type())
  }
}

///|
fn DocState::resolve_value_inner(
  self : DocState,
  value : @types.LoroValue,
  seen : Map[@types.ContainerID, Bool],
) -> @types.LoroValue {
  match value {
    @types.LoroValue::Container(id) => self.container_deep_value(id, seen)
    @types.LoroValue::List(items) => {
      let out : Array[@types.LoroValue] = []
      for item in items {
        out.push(self.resolve_value_inner(item, seen))
      }
      @types.LoroValue::List(out)
    }
    @types.LoroValue::Map(map) => {
      let out : Map[String, @types.LoroValue] = {}
      for k, v in map {
        out[k] = self.resolve_value_inner(v, seen)
      }
      @types.LoroValue::Map(out)
    }
    other => other
  }
}

///|
pub fn DocState::get_deep_value(self : DocState) -> @types.LoroValue {
  let root : Map[String, @types.LoroValue] = {}
  for id, _state in self.containers {
    match id {
      @types.ContainerID::Root(name~, container_type=_) => {
        let seen : Map[@types.ContainerID, Bool] = {}
        root[name] = self.container_deep_value(id, seen)
      }
      _ => ()
    }
  }
  @types.LoroValue::Map(root)
}
