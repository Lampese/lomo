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
pub struct TextState {
  elems : Array[TextElem]
  styles : Array[StyleSpan]
} derive(Show)

///|
pub fn TextState::new() -> TextState {
  TextState::{ elems: [], styles: [] }
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
pub fn TextState::to_value(self : TextState) -> @types.LoroValue {
  @types.LoroValue::String(self.plain_text())
}

///|
pub fn TextState::elems(self : TextState) -> Array[TextElem] {
  let out : Array[TextElem] = []
  for elem in self.elems {
    out.push(elem)
  }
  out
}

///|
pub fn TextState::styles(self : TextState) -> Array[StyleSpan] {
  let out : Array[StyleSpan] = []
  for span in self.styles {
    out.push(span)
  }
  out
}

///|
pub fn TextState::append_elem(
  self : TextState,
  ch : Char,
  id : @types.IdFull,
) -> Unit {
  self.elems.push(TextElem::{ ch, id })
}

///|
pub fn TextState::append_style(self : TextState, span : StyleSpan) -> Unit {
  self.styles.push(span)
}

///|
pub fn TextState::plain_text(self : TextState) -> String {
  let sb = StringBuilder::new()
  for elem in self.elems {
    sb.write_char(elem.ch)
  }
  sb.to_string()
}

///|
pub fn TextState::to_richtext_value(self : TextState) -> @types.LoroValue {
  let len = self.elems.length()
  if len == 0 {
    return @types.LoroValue::List([])
  }
  let attrs : Array[Map[String, @types.LoroValue]] = []
  for i = 0; i < len; i = i + 1 {
    let map : Map[String, @types.LoroValue] = {}
    attrs.push(map)
  }
  for span in self.styles {
    let start = if span.start < 0 { 0 } else { span.start }
    let end = if span.end > len { len } else { span.end }
    if end <= start {
      continue
    }
    for i = start; i < end; i = i + 1 {
      attrs[i][span.key] = span.value
    }
  }
  let deltas : Array[@types.LoroValue] = []
  let mut sb = StringBuilder::new()
  let mut current_attrs = attrs[0]
  sb.write_char(self.elems[0].ch)
  for i = 1; i < len; i = i + 1 {
    let next_attrs = attrs[i]
    if map_eq(current_attrs, next_attrs) {
      sb.write_char(self.elems[i].ch)
    } else {
      let delta = richtext_delta(sb.to_string(), current_attrs)
      deltas.push(delta)
      sb = StringBuilder::new()
      current_attrs = next_attrs
      sb.write_char(self.elems[i].ch)
    }
  }
  deltas.push(richtext_delta(sb.to_string(), current_attrs))
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
  self.elems.length()
}

///|
pub fn TextState::id_at(
  self : TextState,
  index : Int,
) -> Result[@types.IdFull, @types.LoroError] {
  if index < 0 || index >= self.elems.length() {
    return Err(@types.LoroError::InternalError("index out of range"))
  }
  Ok(self.elems[index].id)
}

///|
pub fn TextState::ids_in_range(
  self : TextState,
  start : Int,
  end : Int,
) -> Result[Array[@types.IdFull], @types.LoroError] {
  if start < 0 || end < start || end > self.elems.length() {
    return Err(@types.LoroError::InternalError("index out of range"))
  }
  let out : Array[@types.IdFull] = []
  for i = start; i < end; i = i + 1 {
    out.push(self.elems[i].id)
  }
  Ok(out)
}

///|
pub fn TextState::slice(
  self : TextState,
  start : Int,
  end : Int,
) -> Result[String, @types.LoroError] {
  if start < 0 || end < start || end > self.elems.length() {
    return Err(@types.LoroError::InternalError("slice out of range"))
  }
  let sb = StringBuilder::new()
  for i = start; i < end; i = i + 1 {
    sb.write_char(self.elems[i].ch)
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
  for i = 0; i < self.elems.length(); i = i + 1 {
    if count == offset {
      return Ok(i)
    }
    let len = self.elems[i].ch.utf16_len()
    if count + len > offset {
      return Err(
        @types.LoroError::InternalError("utf16 offset in middle of char"),
      )
    }
    count = count + len
  }
  if count == offset {
    Ok(self.elems.length())
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
  for i = 0; i < self.elems.length(); i = i + 1 {
    if count == offset {
      return Ok(i)
    }
    let len = utf8_len(self.elems[i].ch)
    if count + len > offset {
      return Err(
        @types.LoroError::InternalError("utf8 offset in middle of char"),
      )
    }
    count = count + len
  }
  if count == offset {
    Ok(self.elems.length())
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
    self.elems.insert(pos + offset, TextElem::{ ch, id })
    offset = offset + 1
  }
  let len = offset
  for i = 0; i < self.styles.length(); i = i + 1 {
    let span = self.styles[i]
    if pos < span.start {
      self.styles[i] = StyleSpan::{
        start: span.start + len,
        end: span.end + len,
        key: span.key,
        value: span.value,
        expand: span.expand,
      }
    } else if pos == span.start {
      if span.expand.expand_before() {
        self.styles[i] = StyleSpan::{
          start: span.start,
          end: span.end + len,
          key: span.key,
          value: span.value,
          expand: span.expand,
        }
      } else {
        self.styles[i] = StyleSpan::{
          start: span.start + len,
          end: span.end + len,
          key: span.key,
          value: span.value,
          expand: span.expand,
        }
      }
    } else if pos < span.end {
      self.styles[i] = StyleSpan::{
        start: span.start,
        end: span.end + len,
        key: span.key,
        value: span.value,
        expand: span.expand,
      }
    } else if pos == span.end {
      if span.expand.expand_after() {
        self.styles[i] = StyleSpan::{
          start: span.start,
          end: span.end + len,
          key: span.key,
          value: span.value,
          expand: span.expand,
        }
      }
    }
  }
}

///|
pub fn TextState::delete(self : TextState, start : Int, end : Int) -> Unit {
  if start < 0 || end < start || end > self.elems.length() {
    return
  }
  let mut idx = start
  while idx < end {
    ignore(self.elems.remove(start))
    idx = idx + 1
  }
  let len = end - start
  let mut i = 0
  while i < self.styles.length() {
    let span = self.styles[i]
    if end <= span.start {
      self.styles[i] = StyleSpan::{
        start: span.start - len,
        end: span.end - len,
        key: span.key,
        value: span.value,
        expand: span.expand,
      }
      i = i + 1
    } else if start >= span.end {
      i = i + 1
    } else {
      let overlap_start = if span.start > start { span.start } else { start }
      let overlap_end = if span.end < end { span.end } else { end }
      let removed = overlap_end - overlap_start
      let new_start = if span.start < start { span.start } else { start }
      let new_end = span.end - removed
      if new_end <= new_start {
        ignore(self.styles.remove(i))
      } else {
        self.styles[i] = StyleSpan::{
          start: new_start,
          end: new_end,
          key: span.key,
          value: span.value,
          expand: span.expand,
        }
        i = i + 1
      }
    }
  }
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
  let old_len = self.elems.length()
  let prefix : Array[Int] = [0]
  let mut deleted = 0
  let kept : Array[TextElem] = []
  for i = 0; i < old_len; i = i + 1 {
    let elem = self.elems[i]
    if elem.id.peer == peer &&
      elem.id.counter >= start_ctr &&
      elem.id.counter < end_ctr {
      deleted = deleted + 1
    } else {
      kept.push(elem)
    }
    prefix.push(deleted)
  }
  if deleted == 0 {
    return
  }
  self.elems.clear()
  self.elems.append(kept[:])
  let new_styles : Array[StyleSpan] = []
  for span in self.styles {
    let start = span.start
    let end = span.end
    if start < 0 || end > old_len {
      continue
    }
    let new_start = start - prefix[start]
    let new_end = end - prefix[end]
    if new_end > new_start {
      new_styles.push(StyleSpan::{
        start: new_start,
        end: new_end,
        key: span.key,
        value: span.value,
        expand: span.expand,
      })
    }
  }
  self.styles.clear()
  self.styles.append(new_styles[:])
}

///|
fn TextState::apply_style(
  self : TextState,
  start : Int,
  end : Int,
  key : String,
  value : @types.LoroValue,
  info : Int,
) -> Unit {
  if start < 0 || end < start || end > self.elems.length() {
    return
  }
  if start == end {
    return
  }
  let expand = @types.ExpandType::from_info(info)
  if value is @types.LoroValue::Null {
    let mut i = 0
    while i < self.styles.length() {
      let span = self.styles[i]
      if span.key != key || end <= span.start || start >= span.end {
        i = i + 1
        continue
      }
      if start <= span.start && end >= span.end {
        ignore(self.styles.remove(i))
      } else if start <= span.start && end < span.end {
        self.styles[i] = StyleSpan::{
          start: end,
          end: span.end,
          key: span.key,
          value: span.value,
          expand: span.expand,
        }
        i = i + 1
      } else if start > span.start && end >= span.end {
        self.styles[i] = StyleSpan::{
          start: span.start,
          end: start,
          key: span.key,
          value: span.value,
          expand: span.expand,
        }
        i = i + 1
      } else {
        let right = StyleSpan::{
          start: end,
          end: span.end,
          key: span.key,
          value: span.value,
          expand: span.expand,
        }
        self.styles[i] = StyleSpan::{
          start: span.start,
          end: start,
          key: span.key,
          value: span.value,
          expand: span.expand,
        }
        self.styles.insert(i + 1, right)
        i = i + 2
      }
    }
  } else {
    let mut new_start = start
    let mut new_end = end
    let mut i = 0
    while i < self.styles.length() {
      let span = self.styles[i]
      if span.key == key &&
        span.expand == expand &&
        loro_value_eq(span.value, value) &&
        !(new_end < span.start || new_start > span.end) {
        if span.start < new_start {
          new_start = span.start
        }
        if span.end > new_end {
          new_end = span.end
        }
        ignore(self.styles.remove(i))
      } else {
        i = i + 1
      }
    }
    self.styles.push(StyleSpan::{
      start: new_start,
      end: new_end,
      key,
      value,
      expand,
    })
  }
}

///|
fn TextState::markers_before(self : TextState, pos : Int) -> Int {
  let mut count = 0
  for span in self.styles {
    if span.start <= pos {
      count = count + 1
    }
    if span.end <= pos {
      count = count + 1
    }
  }
  count
}

///|
fn TextState::text_pos_to_list_pos(self : TextState, text_pos : Int) -> Int {
  let max_pos = self.elems.length()
  let mut pos = text_pos
  if pos < 0 {
    pos = 0
  } else if pos > max_pos {
    pos = max_pos
  }
  pos + self.markers_before(pos)
}

///|
fn TextState::list_pos_to_text_pos(self : TextState, list_pos : Int) -> Int {
  let max_pos = self.elems.length()
  if list_pos <= 0 {
    return 0
  }
  let max_list_pos = max_pos + self.markers_before(max_pos)
  if list_pos >= max_list_pos {
    return max_pos
  }
  let mut low = 0
  let mut high = max_pos
  while low < high {
    let mid = (low + high + 1) / 2
    let list_index = mid + self.markers_before(mid)
    if list_index <= list_pos {
      low = mid
    } else {
      high = mid - 1
    }
  }
  low
}

///|
pub fn TextState::apply_inner_op(
  self : TextState,
  op : @op.InnerListOp,
  base_id : @types.IdFull,
) -> Result[Unit, @types.LoroError] {
  match op {
    @op.InnerListOp::InsertText(str~, unicode_len=_, pos~, unicode_start=_) => {
      let text_pos = self.list_pos_to_text_pos(pos)
      self.insert(text_pos, str, base_id)
      Ok(())
    }
    @op.InnerListOp::Delete(span) => {
      self.delete_by_id(span)
      Ok(())
    }
    @op.InnerListOp::StyleStart(start~, end~, key~, info~, value~) => {
      let text_start = self.list_pos_to_text_pos(start)
      let text_end = self.list_pos_to_text_pos(end)
      self.apply_style(text_start, text_end, key, value, info)
      Ok(())
    }
    @op.InnerListOp::StyleEnd => Ok(())
    _ => Err(@types.LoroError::Unsupported("text op not supported"))
  }
}
