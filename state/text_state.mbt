///|
// Text state modeled as per-character entries with IDs.
pub struct TextElem {
  ch : Char
  id : @types.IdFull
} derive(Show)

///|
pub struct StyleSpan {
  start : Int
  end : Int
  key : String
  value : @types.LoroValue
  expand : @types.ExpandType
} derive(Show)

///|
pub fn StyleSpan::new(
  start : Int,
  end : Int,
  key : String,
  value : @types.LoroValue,
  expand : @types.ExpandType,
) -> StyleSpan {
  StyleSpan::{ start, end, key, value, expand }
}

///|
pub fn StyleSpan::start(self : StyleSpan) -> Int {
  self.start
}

///|
pub fn StyleSpan::end(self : StyleSpan) -> Int {
  self.end
}

///|
pub fn StyleSpan::key(self : StyleSpan) -> String {
  self.key
}

///|
pub fn StyleSpan::value(self : StyleSpan) -> @types.LoroValue {
  self.value
}

///|
pub fn StyleSpan::expand(self : StyleSpan) -> @types.ExpandType {
  self.expand
}

///|
pub(all) enum AnchorType {
  Start
  End
} derive(Show, Eq)

///|
pub(all) struct StyleOp {
  id : @types.IdFull
  key : String
  value : @types.LoroValue
  info : Int
} derive(Show)

///|
pub(all) enum RichtextElem {
  Text(TextElem)
  Anchor(style~ : StyleOp, anchor~ : AnchorType)
} derive(Show)

///|
pub struct TextState {
  elems : Array[RichtextElem]
} derive(Show)

///|
pub fn TextState::new() -> TextState {
  TextState::{ elems: [] }
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

///|
fn value_is_null(v : @types.LoroValue) -> Bool {
  v is @types.LoroValue::Null
}

///|
fn value_is_false(v : @types.LoroValue) -> Bool {
  match v {
    @types.LoroValue::Bool(b) => !b
    _ => false
  }
}

///|
fn style_op_same_id(a : StyleOp, b : StyleOp) -> Bool {
  a.id.peer == b.id.peer && a.id.counter == b.id.counter
}

///|
fn style_op_cmp(a : StyleOp, b : StyleOp) -> Int {
  if a.id.lamport < b.id.lamport {
    -1
  } else if a.id.lamport > b.id.lamport {
    1
  } else if a.id.peer < b.id.peer {
    -1
  } else if a.id.peer > b.id.peer {
    1
  } else {
    0
  }
}

///|
fn best_style(ops : Array[StyleOp]) -> StyleOp? {
  if ops.length() == 0 {
    return None
  }
  let mut best = ops[0]
  for i = 1; i < ops.length(); i = i + 1 {
    let candidate = ops[i]
    if style_op_cmp(candidate, best) > 0 {
      best = candidate
    }
  }
  Some(best)
}

///|
fn anchor_id(style : StyleOp, anchor : AnchorType) -> @types.IdFull {
  match anchor {
    AnchorType::Start => style.id
    AnchorType::End =>
      @types.IdFull::new(
        style.id.peer,
        style.id.counter + 1,
        style.id.lamport + 1U,
      )
  }
}

///|
fn text_elem_visible_in_vv(
  vv : @types.VersionVector,
  elem : RichtextElem,
) -> Bool {
  match elem {
    RichtextElem::Text(text) => vv.includes_id(text.id.to_id())
    RichtextElem::Anchor(style~, anchor=_) => vv.includes_id(style.id.to_id())
  }
}

///|
fn text_elem_order_id(elem : RichtextElem) -> @types.IdFull {
  match elem {
    RichtextElem::Text(text) => text.id
    RichtextElem::Anchor(style~, anchor~) => anchor_id(style, anchor)
  }
}

///|
fn prefer_insert_before(info : Int, anchor : AnchorType) -> Bool {
  let expand = @types.ExpandType::from_info(info)
  match anchor {
    AnchorType::Start => !expand.expand_before()
    AnchorType::End => expand.expand_after()
  }
}

///|
pub fn TextState::to_value(self : TextState) -> @types.LoroValue {
  @types.LoroValue::String(self.plain_text())
}

///|
pub fn TextState::elems(self : TextState) -> Array[TextElem] {
  let out : Array[TextElem] = []
  for elem in self.elems {
    match elem {
      RichtextElem::Text(text) => out.push(text)
      _ => ()
    }
  }
  out
}

///|
pub fn TextState::raw_elems(self : TextState) -> Array[RichtextElem] {
  let out : Array[RichtextElem] = []
  for elem in self.elems {
    out.push(elem)
  }
  out
}

///|
pub fn TextState::styles(self : TextState) -> Array[StyleSpan] {
  let spans : Array[StyleSpan] = []
  let active : Map[String, Array[StyleOp]] = {}
  let mut current : Map[String, StyleOp] = {}
  let open : Map[String, (Int, StyleOp)] = {}
  let mut text_pos = 0
  for elem in self.elems {
    match elem {
      RichtextElem::Anchor(style~, anchor~) => {
        match active.get(style.key) {
          Some(list) =>
            if anchor == AnchorType::Start {
              list.push(style)
            } else {
              let mut idx = 0
              while idx < list.length() {
                if style_op_same_id(list[idx], style) {
                  ignore(list.remove(idx))
                  break
                }
                idx = idx + 1
              }
            }
          None => if anchor == AnchorType::Start { active[style.key] = [style] }
        }
        continue
      }
      RichtextElem::Text(_) => ()
    }
    let next : Map[String, StyleOp] = {}
    for key, list in active {
      match best_style(list) {
        Some(best) => if !value_is_null(best.value) { next[key] = best }
        None => ()
      }
    }
    let keys : Array[String] = []
    for key, _ in current {
      keys.push(key)
    }
    for key, _ in next {
      if !keys.contains(key) {
        keys.push(key)
      }
    }
    for key in keys {
      let old = current.get(key)
      let new = next.get(key)
      let same = match (old, new) {
        (Some(a), Some(b)) => style_op_same_id(a, b)
        (None, None) => true
        _ => false
      }
      if same {
        continue
      }
      match old {
        Some(_) =>
          match open.get(key) {
            Some((start, op)) =>
              if start < text_pos {
                spans.push(StyleSpan::{
                  start,
                  end: text_pos,
                  key,
                  value: op.value,
                  expand: @types.ExpandType::from_info(op.info),
                })
              }
            None => ()
          }
        None => ()
      }
      match new {
        Some(next_op) => open[key] = (text_pos, next_op)
        None => ignore(open.remove(key))
      }
    }
    current = next
    text_pos = text_pos + 1
  }
  for key, entry in open {
    let (start, op) = entry
    if start < text_pos && !value_is_null(op.value) {
      spans.push(StyleSpan::{
        start,
        end: text_pos,
        key,
        value: op.value,
        expand: @types.ExpandType::from_info(op.info),
      })
    }
  }
  spans
}

///|
pub fn TextState::append_elem(
  self : TextState,
  ch : Char,
  id : @types.IdFull,
) -> Unit {
  self.elems.push(RichtextElem::Text(TextElem::{ ch, id }))
}

///|
pub fn TextState::append_anchor(
  self : TextState,
  style : StyleOp,
  anchor : AnchorType,
) -> Unit {
  self.elems.push(RichtextElem::Anchor(style~, anchor~))
}

///|
pub fn TextState::plain_text(self : TextState) -> String {
  let sb = StringBuilder::new()
  for elem in self.elems {
    match elem {
      RichtextElem::Text(text) => sb.write_char(text.ch)
      _ => ()
    }
  }
  sb.to_string()
}

///|
fn text_elem_id_at(base : @types.IdFull, offset : Int) -> @types.IdFull {
  @types.IdFull::new(
    base.peer,
    base.counter + offset,
    base.lamport + offset.reinterpret_as_uint(),
  )
}

///|
fn utf8_len(ch : Char) -> Int {
  let code = ch.to_int()
  if code <= 0x7f {
    1
  } else if code <= 0x7ff {
    2
  } else if code <= 0xffff {
    3
  } else {
    4
  }
}

///|
pub fn TextState::len(self : TextState) -> Int {
  let mut count = 0
  for elem in self.elems {
    match elem {
      RichtextElem::Text(_) => count = count + 1
      _ => ()
    }
  }
  count
}

///|
pub fn TextState::id_at(
  self : TextState,
  index : Int,
) -> Result[@types.IdFull, @types.LoroError] {
  if index < 0 {
    return Err(@types.LoroError::InternalError("index out of range"))
  }
  let mut text_idx = 0
  for elem in self.elems {
    match elem {
      RichtextElem::Text(text) => {
        if text_idx == index {
          return Ok(text.id)
        }
        text_idx = text_idx + 1
      }
      _ => ()
    }
  }
  Err(@types.LoroError::InternalError("index out of range"))
}

///|
pub fn TextState::ids_in_range(
  self : TextState,
  start : Int,
  end : Int,
) -> Result[Array[@types.IdFull], @types.LoroError] {
  if start < 0 || end < start {
    return Err(@types.LoroError::InternalError("index out of range"))
  }
  let out : Array[@types.IdFull] = []
  let mut text_idx = 0
  for elem in self.elems {
    match elem {
      RichtextElem::Text(text) => {
        if text_idx >= start && text_idx < end {
          out.push(text.id)
        }
        text_idx = text_idx + 1
      }
      _ => ()
    }
  }
  if end > text_idx {
    return Err(@types.LoroError::InternalError("index out of range"))
  }
  Ok(out)
}

///|
pub fn TextState::slice(
  self : TextState,
  start : Int,
  end : Int,
) -> Result[String, @types.LoroError] {
  if start < 0 || end < start {
    return Err(@types.LoroError::InternalError("slice out of range"))
  }
  let sb = StringBuilder::new()
  let mut text_idx = 0
  for elem in self.elems {
    match elem {
      RichtextElem::Text(text) => {
        if text_idx >= start && text_idx < end {
          sb.write_char(text.ch)
        }
        text_idx = text_idx + 1
      }
      _ => ()
    }
  }
  if end > text_idx {
    return Err(@types.LoroError::InternalError("slice out of range"))
  }
  Ok(sb.to_string())
}

///|
pub fn TextState::unicode_index_from_utf16(
  self : TextState,
  offset : Int,
) -> Result[Int, @types.LoroError] {
  if offset < 0 {
    return Err(@types.LoroError::InternalError("utf16 offset out of range"))
  }
  let mut count = 0
  let mut text_idx = 0
  for elem in self.elems {
    match elem {
      RichtextElem::Text(text) => {
        if count == offset {
          return Ok(text_idx)
        }
        let len = text.ch.utf16_len()
        if count + len > offset {
          return Err(
            @types.LoroError::InternalError("utf16 offset in middle of char"),
          )
        }
        count = count + len
        text_idx = text_idx + 1
      }
      _ => ()
    }
  }
  if count == offset {
    Ok(text_idx)
  } else {
    Err(@types.LoroError::InternalError("utf16 offset out of range"))
  }
}

///|
pub fn TextState::unicode_index_from_utf8(
  self : TextState,
  offset : Int,
) -> Result[Int, @types.LoroError] {
  if offset < 0 {
    return Err(@types.LoroError::InternalError("utf8 offset out of range"))
  }
  let mut count = 0
  let mut text_idx = 0
  for elem in self.elems {
    match elem {
      RichtextElem::Text(text) => {
        if count == offset {
          return Ok(text_idx)
        }
        let len = utf8_len(text.ch)
        if count + len > offset {
          return Err(
            @types.LoroError::InternalError("utf8 offset in middle of char"),
          )
        }
        count = count + len
        text_idx = text_idx + 1
      }
      _ => ()
    }
  }
  if count == offset {
    Ok(text_idx)
  } else {
    Err(@types.LoroError::InternalError("utf8 offset out of range"))
  }
}

///|
pub fn TextState::insert(
  self : TextState,
  pos : Int,
  text : String,
  base_id : @types.IdFull,
) -> Unit {
  if pos < 0 || pos > self.elems.length() {
    return
  }
  let mut offset = 0
  for ch in text {
    let id = text_elem_id_at(base_id, offset)
    self.elems.insert(pos + offset, RichtextElem::Text(TextElem::{ ch, id }))
    offset = offset + 1
  }
}

///|
fn TextState::insert_pos_with_vv(
  self : TextState,
  pos : Int,
  vv : @types.VersionVector,
  new_id : @types.IdFull,
) -> Int? {
  if pos < 0 {
    return None
  }
  let mut visible_count = 0
  let mut last_visible = -1
  let mut idx = 0
  let mut gap_start = 0
  let mut gap_end = self.elems.length()
  let mut found_gap = false
  while idx < self.elems.length() {
    let elem = self.elems[idx]
    if text_elem_visible_in_vv(vv, elem) {
      if visible_count == pos {
        gap_start = last_visible + 1
        gap_end = idx
        found_gap = true
        break
      }
      visible_count = visible_count + 1
      last_visible = idx
    }
    idx = idx + 1
  }
  if !found_gap {
    if visible_count == pos {
      gap_start = last_visible + 1
      gap_end = self.elems.length()
    } else {
      return None
    }
  }
  let mut insert_idx = gap_start
  while insert_idx < gap_end {
    let elem = self.elems[insert_idx]
    let elem_id = text_elem_order_id(elem)
    if id_full_cmp(elem_id, new_id) < 0 {
      insert_idx = insert_idx + 1
    } else {
      break
    }
  }
  Some(insert_idx)
}

///|
pub fn TextState::insert_with_vv(
  self : TextState,
  pos : Int,
  text : String,
  base_id : @types.IdFull,
  vv : @types.VersionVector,
) -> Unit {
  let insert_at = match self.insert_pos_with_vv(pos, vv, base_id) {
    Some(value) => value
    None => return
  }
  let mut offset = 0
  for ch in text {
    let id = text_elem_id_at(base_id, offset)
    self.elems.insert(
      insert_at + offset,
      RichtextElem::Text(TextElem::{ ch, id }),
    )
    offset = offset + 1
  }
}

///|
pub fn TextState::delete(self : TextState, start : Int, end : Int) -> Unit {
  if start < 0 || end < start {
    return
  }
  let mut text_idx = 0
  let kept : Array[RichtextElem] = []
  for elem in self.elems {
    match elem {
      RichtextElem::Text(_) => {
        if text_idx < start || text_idx >= end {
          kept.push(elem)
        }
        text_idx = text_idx + 1
      }
      _ => kept.push(elem)
    }
  }
  if end > text_idx {
    return
  }
  self.elems.clear()
  self.elems.append(kept[:])
}

///|
pub fn TextState::delete_by_id(
  self : TextState,
  span : @op.DeleteSpanWithId,
) -> Unit {
  let id_start = span.id_start()
  let len = span.content_len()
  if len <= 0 {
    return
  }
  let start_ctr = id_start.counter
  let end_ctr = start_ctr + len
  let peer = id_start.peer
  let kept : Array[RichtextElem] = []
  for elem in self.elems {
    let elem_id = match elem {
      RichtextElem::Text(text) => text.id
      RichtextElem::Anchor(style~, anchor~) => anchor_id(style, anchor)
    }
    if elem_id.peer == peer &&
      elem_id.counter >= start_ctr &&
      elem_id.counter < end_ctr {
      continue
    }
    kept.push(elem)
  }
  self.elems.clear()
  self.elems.append(kept[:])
}

///|
fn attrs_from_active(
  active : Map[String, Array[StyleOp]],
) -> Map[String, @types.LoroValue] {
  let attrs : Map[String, @types.LoroValue] = {}
  for key, list in active {
    match best_style(list) {
      Some(best) => if !value_is_null(best.value) { attrs[key] = best.value }
      None => ()
    }
  }
  attrs
}

///|
pub fn TextState::to_richtext_value(self : TextState) -> @types.LoroValue {
  let deltas : Array[@types.LoroValue] = []
  let active : Map[String, Array[StyleOp]] = {}
  let mut sb = StringBuilder::new()
  let mut has_text = false
  let mut current_attrs : Map[String, @types.LoroValue]? = None
  for elem in self.elems {
    match elem {
      RichtextElem::Anchor(style~, anchor~) =>
        match active.get(style.key) {
          Some(list) =>
            if anchor == AnchorType::Start {
              list.push(style)
            } else {
              let mut idx = 0
              while idx < list.length() {
                if style_op_same_id(list[idx], style) {
                  ignore(list.remove(idx))
                  break
                }
                idx = idx + 1
              }
            }
          None => if anchor == AnchorType::Start { active[style.key] = [style] }
        }
      RichtextElem::Text(text) => {
        let next_attrs = attrs_from_active(active)
        match current_attrs {
          Some(attrs) =>
            if map_eq(attrs, next_attrs) {
              sb.write_char(text.ch)
              has_text = true
            } else {
              if has_text {
                deltas.push(richtext_delta(sb.to_string(), attrs))
              }
              sb = StringBuilder::new()
              has_text = false
              current_attrs = Some(next_attrs)
              sb.write_char(text.ch)
              has_text = true
            }
          None => {
            current_attrs = Some(next_attrs)
            sb.write_char(text.ch)
            has_text = true
          }
        }
      }
    }
  }
  match current_attrs {
    Some(attrs) =>
      if has_text {
        deltas.push(richtext_delta(sb.to_string(), attrs))
      }
    None => ()
  }
  @types.LoroValue::List(deltas)
}

///|
fn richtext_delta(
  text : String,
  attrs : Map[String, @types.LoroValue],
) -> @types.LoroValue {
  let map : Map[String, @types.LoroValue] = {}
  map["insert"] = @types.LoroValue::String(text)
  if attrs.length() > 0 {
    let attributes : Map[String, @types.LoroValue] = {}
    for k, v in attrs {
      attributes[k] = v
    }
    map["attributes"] = @types.LoroValue::Map(attributes)
  }
  @types.LoroValue::Map(map)
}

///|
fn TextState::entity_index_of_text_index(
  self : TextState,
  target : Int,
) -> Int? {
  if target < 0 {
    return None
  }
  let mut text_idx = 0
  for i = 0; i < self.elems.length(); i = i + 1 {
    match self.elems[i] {
      RichtextElem::Text(_) => {
        if text_idx == target {
          return Some(i)
        }
        text_idx = text_idx + 1
      }
      _ => ()
    }
  }
  None
}

///|
fn TextState::find_best_insert_pos(
  self : TextState,
  left : Int,
  right : Int,
) -> Int {
  let mut iter = left
  let mut entity_index = left
  let visited : Array[(StyleOp, AnchorType, Int)] = []
  while iter < right {
    let elem = self.elems[iter]
    match elem {
      RichtextElem::Anchor(style~, anchor~) => {
        visited.push((style, anchor, iter))
        if anchor == AnchorType::Start &&
          (!value_is_null(style.value) || !value_is_false(style.value)) {
          break
        }
        if prefer_insert_before(style.info, anchor) {
          break
        }
      }
      _ => ()
    }
    iter = iter + 1
    entity_index = entity_index + 1
  }
  while visited.length() > 0 {
    let idx = visited.length() - 1
    let (style, anchor, pos) = visited[idx]
    ignore(visited.remove(idx))
    if !prefer_insert_before(style.info, anchor) {
      break
    }
    iter = pos
    entity_index = pos
  }
  entity_index
}

///|
pub fn TextState::text_pos_to_list_pos(self : TextState, text_pos : Int) -> Int {
  let max_pos = self.len()
  let mut pos = text_pos
  if pos < 0 {
    pos = 0
  } else if pos > max_pos {
    pos = max_pos
  }
  if self.elems.length() == 0 {
    return 0
  }
  if pos == 0 {
    let mut right = 0
    while right < self.elems.length() {
      match self.elems[right] {
        RichtextElem::Text(_) => break
        _ => right = right + 1
      }
    }
    if right == 0 {
      return 0
    }
    return self.find_best_insert_pos(0, right)
  }
  let prev_entity = match self.entity_index_of_text_index(pos - 1) {
    Some(v) => v
    None => return self.elems.length()
  }
  let left = prev_entity + 1
  if left >= self.elems.length() {
    return left
  }
  let mut right = left
  while right < self.elems.length() {
    match self.elems[right] {
      RichtextElem::Text(_) => break
      _ => right = right + 1
    }
  }
  if left == right {
    left
  } else {
    self.find_best_insert_pos(left, right)
  }
}

///|
pub fn TextState::text_index_to_list_pos(
  self : TextState,
  text_pos : Int,
) -> Result[Int, @types.LoroError] {
  if text_pos < 0 {
    return Err(@types.LoroError::InternalError("index out of range"))
  }
  let len = self.len()
  if text_pos == len {
    return Ok(self.elems.length())
  }
  if text_pos > len {
    return Err(@types.LoroError::InternalError("index out of range"))
  }
  match self.entity_index_of_text_index(text_pos) {
    Some(pos) => Ok(pos)
    None => Err(@types.LoroError::InternalError("index out of range"))
  }
}

///|
pub fn TextState::list_pos_to_text_pos(self : TextState, list_pos : Int) -> Int {
  if list_pos <= 0 {
    return 0
  }
  let max_list_pos = self.elems.length()
  if list_pos >= max_list_pos {
    return self.len()
  }
  let mut count = 0
  let mut idx = 0
  while idx < list_pos {
    match self.elems[idx] {
      RichtextElem::Text(_) => count = count + 1
      _ => ()
    }
    idx = idx + 1
  }
  count
}

///|
pub fn TextState::apply_inner_op(
  self : TextState,
  op : @op.InnerListOp,
  base_id : @types.IdFull,
) -> Result[Unit, @types.LoroError] {
  match op {
    @op.InnerListOp::InsertText(str~, unicode_len=_, pos~, unicode_start=_) => {
      self.insert(pos, str, base_id)
      Ok(())
    }
    @op.InnerListOp::Delete(span) => {
      self.delete_by_id(span)
      Ok(())
    }
    @op.InnerListOp::StyleStart(start~, end~, key~, info~, value~) => {
      if start < 0 || end < start {
        return Ok(())
      }
      let style = StyleOp::{ id: base_id, key, value, info }
      if end <= self.elems.length() {
        self.elems.insert(
          end,
          RichtextElem::Anchor(style~, anchor=AnchorType::End),
        )
      }
      if start <= self.elems.length() {
        self.elems.insert(
          start,
          RichtextElem::Anchor(style~, anchor=AnchorType::Start),
        )
      }
      Ok(())
    }
    @op.InnerListOp::StyleEnd => Ok(())
    _ => Err(@types.LoroError::Unsupported("text op not supported"))
  }
}

///|
pub fn TextState::apply_inner_op_with_vv(
  self : TextState,
  op : @op.InnerListOp,
  base_id : @types.IdFull,
  vv : @types.VersionVector,
) -> Result[Unit, @types.LoroError] {
  match op {
    @op.InnerListOp::InsertText(str~, unicode_len=_, pos~, unicode_start=_) => {
      self.insert_with_vv(pos, str, base_id, vv)
      Ok(())
    }
    @op.InnerListOp::Delete(span) => {
      self.delete_by_id(span)
      Ok(())
    }
    @op.InnerListOp::StyleStart(start~, end~, key~, info~, value~) => {
      if start < 0 || end < start {
        return Ok(())
      }
      let style = StyleOp::{ id: base_id, key, value, info }
      let end_pos = self.insert_pos_with_vv(
        end,
        vv,
        anchor_id(style, AnchorType::End),
      )
      let start_pos = self.insert_pos_with_vv(
        start,
        vv,
        anchor_id(style, AnchorType::Start),
      )
      match end_pos {
        Some(pos) =>
          if pos <= self.elems.length() {
            self.elems.insert(
              pos,
              RichtextElem::Anchor(style~, anchor=AnchorType::End),
            )
          }
        None => ()
      }
      match start_pos {
        Some(pos) =>
          if pos <= self.elems.length() {
            self.elems.insert(
              pos,
              RichtextElem::Anchor(style~, anchor=AnchorType::Start),
            )
          }
        None => ()
      }
      Ok(())
    }
    @op.InnerListOp::StyleEnd => Ok(())
    _ => Err(@types.LoroError::Unsupported("text op not supported"))
  }
}
