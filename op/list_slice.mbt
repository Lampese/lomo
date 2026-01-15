///|
// List slices are stored as raw values or raw strings.
pub(all) enum ListSlice {
  RawData(Array[@types.LoroValue])
  RawStr(str~ : String, unicode_len~ : Int)
} derive(Show)

///|
fn count_unicode_len(s : String) -> Int {
  let mut len = 0
  for _ in s {
    len = len + 1
  }
  len
}

///|
pub fn ListSlice::from_str(str : String) -> ListSlice {
  ListSlice::RawStr(str~, unicode_len=count_unicode_len(str))
}

///|
pub struct SliceRange {
  start : UInt
  end : UInt
} derive(Show, Eq)

///|
const UNKNOWN_START : UInt = 0x7fffffff

///|
pub fn SliceRange::is_unknown(self : SliceRange) -> Bool {
  self.start == UNKNOWN_START
}

///|
pub fn SliceRange::new_unknown(size : UInt) -> SliceRange {
  SliceRange::{ start: UNKNOWN_START, end: UNKNOWN_START + size }
}

///|
pub fn SliceRange::new(start : UInt, end : UInt) -> SliceRange {
  SliceRange::{ start, end }
}

///|
pub fn SliceRange::start(self : SliceRange) -> UInt {
  self.start
}

///|
pub fn SliceRange::end(self : SliceRange) -> UInt {
  self.end
}

///|
pub fn SliceRange::len(self : SliceRange) -> Int {
  (self.end - self.start).reinterpret_as_int()
}

///|
pub fn SliceRange::slice(self : SliceRange, from : Int, to : Int) -> SliceRange {
  if self.is_unknown() {
    SliceRange::new_unknown((to - from).reinterpret_as_uint())
  } else {
    SliceRange::{
      start: self.start + from.reinterpret_as_uint(),
      end: self.start + to.reinterpret_as_uint(),
    }
  }
}

///|
pub fn SliceRange::is_mergeable(self : SliceRange, other : SliceRange) -> Bool {
  if self.is_unknown() && other.is_unknown() {
    true
  } else {
    self.end == other.start
  }
}

///|
pub fn SliceRange::merge(self : SliceRange, other : SliceRange) -> SliceRange {
  if self.is_unknown() {
    SliceRange::{ start: self.start, end: self.end + (other.end - other.start) }
  } else {
    SliceRange::{ start: self.start, end: other.end }
  }
}

///|
fn slice_array(
  values : Array[@types.LoroValue],
  from : Int,
  to : Int,
) -> Array[@types.LoroValue] {
  let out : Array[@types.LoroValue] = []
  for i = from; i < to; i = i + 1 {
    out.push(values[i])
  }
  out
}

///|
fn slice_string_by_char(str : String, from : Int, to : Int) -> String {
  let sb = StringBuilder::new()
  let mut idx = 0
  for ch in str {
    if idx >= from && idx < to {
      sb.write_char(ch)
    }
    if idx >= to {
      break
    }
    idx = idx + 1
  }
  sb.to_string()
}

///|
pub fn ListSlice::content_len(self : ListSlice) -> Int {
  match self {
    RawData(values) => values.length()
    RawStr(str=_, unicode_len~) => unicode_len
  }
}

///|
pub fn ListSlice::slice(self : ListSlice, from : Int, to : Int) -> ListSlice {
  match self {
    RawData(values) => ListSlice::RawData(slice_array(values, from, to))
    RawStr(str~, unicode_len=_) => {
      let sliced = slice_string_by_char(str, from, to)
      ListSlice::RawStr(str=sliced, unicode_len=to - from)
    }
  }
}

///|
pub fn ListSlice::is_mergeable(_self : ListSlice, _other : ListSlice) -> Bool {
  false
}
