///|
// List operations for list and text containers.
pub(all) enum ListOp {
  Insert(slice~ : ListSlice, pos~ : Int)
  Delete(DeleteSpanWithId)
  Move(from~ : Int, to~ : Int, elem_id~ : @types.IdLp)
  Set(elem_id~ : @types.IdLp, value~ : @types.LoroValue)
  StyleStart(
    start~ : Int,
    end~ : Int,
    key~ : String,
    info~ : Int,
    value~ : @types.LoroValue
  )
  StyleEnd
} derive(Show)

///|
pub(all) enum InnerListOp {
  Insert(slice~ : SliceRange, pos~ : Int)
  InsertText(
    str~ : String,
    unicode_start~ : Int,
    unicode_len~ : Int,
    pos~ : Int
  )
  Delete(DeleteSpanWithId)
  Move(from~ : Int, elem_id~ : @types.IdLp, to~ : Int)
  Set(elem_id~ : @types.IdLp, value~ : @types.LoroValue)
  StyleStart(
    start~ : Int,
    end~ : Int,
    key~ : String,
    info~ : Int,
    value~ : @types.LoroValue
  )
  StyleEnd
} derive(Show)

///|
// Delete span allows reversed spans for efficient merging.
pub struct DeleteSpan {
  pos : Int
  signed_len : Int
} derive(Show, Eq)

///|
// Delete span with its starting op id.
pub struct DeleteSpanWithId {
  id_start : @types.ID
  span : DeleteSpan
} derive(Show, Eq)

///|
pub fn DeleteSpan::new(pos : Int, len : Int) -> DeleteSpan {
  DeleteSpan::{ pos, signed_len: len }
}

///|
fn abs_int(v : Int) -> Int {
  if v >= 0 {
    v
  } else {
    -v
  }
}

///|
pub fn DeleteSpan::len(self : DeleteSpan) -> Int {
  abs_int(self.signed_len)
}

///|
pub fn DeleteSpan::pos(self : DeleteSpan) -> Int {
  self.pos
}

///|
pub fn DeleteSpan::signed_len(self : DeleteSpan) -> Int {
  self.signed_len
}

///|
pub fn DeleteSpan::start(self : DeleteSpan) -> Int {
  if self.signed_len > 0 {
    self.pos
  } else {
    self.pos + 1 + self.signed_len
  }
}

///|
pub fn DeleteSpan::last(self : DeleteSpan) -> Int {
  if self.signed_len > 0 {
    self.pos + self.signed_len - 1
  } else {
    self.pos
  }
}

///|
pub fn DeleteSpan::end(self : DeleteSpan) -> Int {
  if self.signed_len > 0 {
    self.pos + self.signed_len
  } else {
    self.pos + 1
  }
}

///|
pub fn DeleteSpan::bidirectional(self : DeleteSpan) -> Bool {
  abs_int(self.signed_len) == 1
}

///|
pub fn DeleteSpan::is_reversed(self : DeleteSpan) -> Bool {
  self.signed_len < 0
}

///|
pub fn DeleteSpan::direction(self : DeleteSpan) -> Int {
  if self.signed_len > 0 {
    1
  } else {
    -1
  }
}

///|
pub fn DeleteSpan::next_pos(self : DeleteSpan) -> Int {
  if self.signed_len > 0 {
    self.start()
  } else {
    self.start() - 1
  }
}

///|
pub fn DeleteSpan::prev_pos(self : DeleteSpan) -> Int {
  if self.signed_len > 0 {
    self.pos
  } else {
    self.end()
  }
}

///|
pub fn DeleteSpan::is_mergeable(self : DeleteSpan, other : DeleteSpan) -> Bool {
  match (self.bidirectional(), other.bidirectional()) {
    (true, true) => self.pos == other.pos || self.pos == other.pos + 1
    (true, false) => self.pos == other.prev_pos()
    (false, true) => self.next_pos() == other.pos
    (false, false) =>
      self.next_pos() == other.pos && self.direction() == other.direction()
  }
}

///|
pub fn DeleteSpan::merge(self : DeleteSpan, other : DeleteSpan) -> DeleteSpan {
  let this = self
  let mut signed_len = this.signed_len
  match (this.bidirectional(), other.bidirectional()) {
    (true, true) =>
      if this.pos == other.pos {
        signed_len = 2
      } else if this.pos == other.pos + 1 {
        signed_len = -2
      }
    (true, false) => signed_len = other.signed_len + other.direction()
    (false, true) => signed_len = this.signed_len + this.direction()
    (false, false) => signed_len = this.signed_len + other.signed_len
  }
  DeleteSpan::{ pos: this.pos, signed_len }
}

///|
pub fn DeleteSpan::slice(self : DeleteSpan, from : Int, to : Int) -> DeleteSpan {
  if self.signed_len > 0 {
    DeleteSpan::new(self.pos, to - from)
  } else {
    DeleteSpan::new(self.pos - from, from - to)
  }
}

///|
pub fn DeleteSpanWithId::new(
  id_start : @types.ID,
  pos : Int,
  len : Int,
) -> DeleteSpanWithId {
  DeleteSpanWithId::{ id_start, span: DeleteSpan::new(pos, len) }
}

///|
pub fn DeleteSpanWithId::id_start(self : DeleteSpanWithId) -> @types.ID {
  self.id_start
}

///|
pub fn DeleteSpanWithId::span(self : DeleteSpanWithId) -> DeleteSpan {
  self.span
}

///|
pub fn DeleteSpanWithId::start(self : DeleteSpanWithId) -> Int {
  self.span.start()
}

///|
pub fn DeleteSpanWithId::end(self : DeleteSpanWithId) -> Int {
  self.span.end()
}

///|
pub fn DeleteSpanWithId::last(self : DeleteSpanWithId) -> Int {
  self.span.last()
}

///|
pub fn DeleteSpanWithId::is_reversed(self : DeleteSpanWithId) -> Bool {
  self.span.is_reversed()
}

///|
pub fn DeleteSpanWithId::id_end(self : DeleteSpanWithId) -> @types.ID {
  self.id_start.inc(self.span.len())
}

///|
pub fn DeleteSpanWithId::id_last(self : DeleteSpanWithId) -> @types.ID {
  self.id_start.inc(self.span.len() - 1)
}

///|
pub fn DeleteSpanWithId::content_len(self : DeleteSpanWithId) -> Int {
  self.span.len()
}

///|
pub fn DeleteSpanWithId::is_mergeable(
  self : DeleteSpanWithId,
  other : DeleteSpanWithId,
) -> Bool {
  let this = self.span
  let rhs = other.span
  match (this.bidirectional(), rhs.bidirectional()) {
    (true, true) => {
      let left = this.pos == rhs.pos && self.id_start.inc(1) == other.id_start
      let right = this.pos == rhs.pos + 1 &&
        self.id_start == other.id_start.inc(1)
      left || right
    }
    (true, false) =>
      if this.pos == rhs.prev_pos() {
        if rhs.signed_len > 0 {
          self.id_start.inc(1) == other.id_start
        } else {
          self.id_start == other.id_end()
        }
      } else {
        false
      }
    (false, true) =>
      if this.next_pos() == rhs.pos {
        if this.signed_len > 0 {
          self.id_end() == other.id_start
        } else {
          self.id_start == other.id_start.inc(1)
        }
      } else {
        false
      }
    (false, false) =>
      if this.next_pos() == rhs.pos && this.direction() == rhs.direction() {
        if this.signed_len > 0 {
          self.id_end() == other.id_start
        } else {
          self.id_start == other.id_end()
        }
      } else {
        false
      }
  }
}

///|
pub fn DeleteSpanWithId::merge(
  self : DeleteSpanWithId,
  other : DeleteSpanWithId,
) -> DeleteSpanWithId {
  let id_start = if other.id_start.counter < self.id_start.counter {
    other.id_start
  } else {
    self.id_start
  }
  let span = self.span.merge(other.span)
  DeleteSpanWithId::{ id_start, span }
}

///|
pub fn DeleteSpanWithId::slice(
  self : DeleteSpanWithId,
  from : Int,
  to : Int,
) -> DeleteSpanWithId {
  let id_start = if self.span.signed_len > 0 {
    self.id_start.inc(from)
  } else {
    self.id_start.inc(self.span.len() - to)
  }
  DeleteSpanWithId::{ id_start, span: self.span.slice(from, to) }
}

///|
pub fn ListOp::new_del(id_start : @types.ID, pos : Int, len : Int) -> ListOp {
  ListOp::Delete(DeleteSpanWithId::new(id_start, pos, len))
}

///|
pub fn ListOp::content_len(self : ListOp) -> Int {
  match self {
    Insert(slice~, pos=_) => slice.content_len()
    Delete(span) => span.content_len()
    StyleStart(start=_, end=_, key=_, info=_, value=_) => 1
    StyleEnd => 1
    Move(from=_, to=_, elem_id=_) => 1
    Set(elem_id=_, value=_) => 1
  }
}

///|
pub fn ListOp::slice(self : ListOp, from : Int, to : Int) -> ListOp {
  match self {
    Insert(slice~, pos~) =>
      ListOp::Insert(slice=slice.slice(from, to), pos=pos + from)
    Delete(span) => ListOp::Delete(span.slice(from, to))
    other => other
  }
}

///|
pub fn ListOp::is_mergeable(self : ListOp, other : ListOp) -> Bool {
  match (self, other) {
    (Insert(slice~, pos~), Insert(slice=other_slice, pos=other_pos)) =>
      pos + slice.content_len() == other_pos && slice.is_mergeable(other_slice)
    (Delete(span), Delete(other_span)) => span.is_mergeable(other_span)
    _ => false
  }
}

///|
pub fn ListOp::merge(self : ListOp, other : ListOp) -> ListOp {
  match (self, other) {
    (Delete(span), Delete(other_span)) => ListOp::Delete(span.merge(other_span))
    _ => self
  }
}

///|
pub fn InnerListOp::content_len(self : InnerListOp) -> Int {
  match self {
    Insert(slice~, pos=_) => slice.len()
    InsertText(str=_, unicode_start=_, unicode_len=len, pos=_) => len
    Delete(span) => span.content_len()
    StyleStart(start=_, end=_, key=_, info=_, value=_) => 1
    StyleEnd => 1
    Move(from=_, elem_id=_, to=_) => 1
    Set(elem_id=_, value=_) => 1
  }
}

///|
pub fn InnerListOp::slice(
  self : InnerListOp,
  from : Int,
  to : Int,
) -> InnerListOp {
  match self {
    Insert(slice~, pos~) =>
      InnerListOp::Insert(slice=slice.slice(from, to), pos=pos + from)
    InsertText(str~, unicode_start=start, unicode_len=len, pos~) => {
      let sliced = ListSlice::RawStr(str~, unicode_len=len).slice(from, to)
      match sliced {
        ListSlice::RawStr(str=s, unicode_len=ulen) =>
          InnerListOp::InsertText(
            str=s,
            unicode_start=start + from,
            unicode_len=ulen,
            pos=pos + from,
          )
        _ =>
          InnerListOp::InsertText(
            str="",
            unicode_start=start + from,
            unicode_len=to - from,
            pos=pos + from,
          )
      }
    }
    Delete(span) => InnerListOp::Delete(span.slice(from, to))
    other => other
  }
}

///|
pub fn InnerListOp::is_mergeable(
  self : InnerListOp,
  other : InnerListOp,
) -> Bool {
  match (self, other) {
    (Insert(slice~, pos~), Insert(slice=other_slice, pos=other_pos)) =>
      pos + slice.len() == other_pos && slice.is_mergeable(other_slice)
    (Delete(span), Delete(other_span)) => span.is_mergeable(other_span)
    (
      InsertText(str=_, unicode_start~, unicode_len=len, pos~),
      InsertText(
        str=_,
        unicode_start=other_unicode_start,
        unicode_len=other_len,
        pos=other_pos
      ),
    ) =>
      pos + len == other_pos &&
      unicode_start + len == other_unicode_start &&
      other_len >= 0
    _ => false
  }
}

///|
pub fn InnerListOp::merge(
  self : InnerListOp,
  other : InnerListOp,
) -> InnerListOp {
  match (self, other) {
    (Insert(slice~, pos~), Insert(slice=other_slice, pos=other_pos)) => {
      let merged = slice.merge(other_slice)
      let _ = other_pos
      InnerListOp::Insert(slice=merged, pos~)
    }
    (Delete(span), Delete(other_span)) =>
      InnerListOp::Delete(span.merge(other_span))
    (
      InsertText(str~, unicode_start=start, unicode_len=len, pos~),
      InsertText(str=other_str, unicode_start=_, unicode_len=other_len, pos=_),
    ) => {
      let merged = String::add(str, other_str)
      InnerListOp::InsertText(
        str=merged,
        unicode_start=start,
        unicode_len=len + other_len,
        pos~,
      )
    }
    _ => self
  }
}
