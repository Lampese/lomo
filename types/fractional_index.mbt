///|
// Fractional index for ordering movable tree children.
pub struct FractionalIndex {
  bytes : Bytes
} derive(Show)

///|
const TERMINATOR : Byte = b'\x80'

///|
fn slice_array(values : Array[Byte], from : Int, to : Int) -> Array[Byte] {
  let out : Array[Byte] = []
  for i = from; i < to; i = i + 1 {
    out.push(values[i])
  }
  out
}

///|
fn bytes_to_array(bytes : Bytes) -> Array[Byte] {
  let out : Array[Byte] = []
  for b in bytes {
    out.push(b)
  }
  out
}

///|
fn from_vec_unterminated(values : Array[Byte]) -> FractionalIndex {
  let with_term = values
  with_term.push(TERMINATOR)
  FractionalIndex::{ bytes: Bytes::from_array(with_term) }
}

///|
pub fn FractionalIndex::default() -> FractionalIndex {
  FractionalIndex::{ bytes: [TERMINATOR] }
}

///|
pub fn FractionalIndex::from_bytes(bytes : Bytes) -> FractionalIndex {
  FractionalIndex::{ bytes, }
}

///|
pub fn FractionalIndex::bytes(self : FractionalIndex) -> Bytes {
  self.bytes
}

///|
pub fn FractionalIndex::compare(
  self : FractionalIndex,
  other : FractionalIndex,
) -> Int {
  let a = self.bytes
  let b = other.bytes
  let len_a = a.length()
  let len_b = b.length()
  let len = if len_a < len_b { len_a } else { len_b }
  for i = 0; i < len; i = i + 1 {
    let av = a[i].to_uint()
    let bv = b[i].to_uint()
    if av < bv {
      return -1
    } else if av > bv {
      return 1
    }
  }
  if len_a < len_b {
    -1
  } else if len_a > len_b {
    1
  } else {
    0
  }
}

///|
pub fn FractionalIndex::new(
  lower : FractionalIndex?,
  upper : FractionalIndex?,
) -> FractionalIndex? {
  match (lower, upper) {
    (Some(l), Some(u)) => FractionalIndex::new_between(l, u)
    (Some(l), None) => Some(FractionalIndex::new_after(l))
    (None, Some(u)) => Some(FractionalIndex::new_before(u))
    (None, None) => Some(FractionalIndex::default())
  }
}

///|
pub fn FractionalIndex::new_before(value : FractionalIndex) -> FractionalIndex {
  from_vec_unterminated(new_before(value.bytes))
}

///|
pub fn FractionalIndex::new_after(value : FractionalIndex) -> FractionalIndex {
  from_vec_unterminated(new_after(value.bytes))
}

///|
pub fn FractionalIndex::new_between(
  left : FractionalIndex,
  right : FractionalIndex,
) -> FractionalIndex? {
  match new_between(left.bytes, right.bytes) {
    Some(values) => Some(from_vec_unterminated(values))
    None => None
  }
}

///|
fn new_before(bytes : Bytes) -> Array[Byte] {
  let arr = bytes_to_array(bytes)
  for i = 0; i < arr.length(); i = i + 1 {
    let b = arr[i].to_int()
    if b > TERMINATOR.to_int() {
      return slice_array(arr, 0, i)
    }
    if b > 0 {
      let out = slice_array(arr, 0, i + 1)
      out[i] = (b - 1).to_byte()
      return out
    }
  }
  []
}

///|
fn new_after(bytes : Bytes) -> Array[Byte] {
  let arr = bytes_to_array(bytes)
  for i = 0; i < arr.length(); i = i + 1 {
    let b = arr[i].to_int()
    if b < TERMINATOR.to_int() {
      return slice_array(arr, 0, i)
    }
    if b < 0xff {
      let out = slice_array(arr, 0, i + 1)
      out[i] = (b + 1).to_byte()
      return out
    }
  }
  []
}

///|
fn new_between(left : Bytes, right : Bytes) -> Array[Byte]? {
  let l = bytes_to_array(left)
  let r = bytes_to_array(right)
  let shorter_len = l.length().min(r.length()) - 1
  for i = 0; i < shorter_len; i = i + 1 {
    let lb = l[i].to_int()
    let rb = r[i].to_int()
    if lb + 1 < rb {
      let out = slice_array(l, 0, i + 1)
      out[i] = (lb + (rb - lb) / 2).to_byte()
      return Some(out)
    }
    if lb + 1 == rb {
      let prefix = slice_array(l, 0, i + 1)
      let suffix = slice_array(l, i + 1, l.length())
      let new_suffix = new_after(Bytes::from_array(suffix))
      let out : Array[Byte] = []
      for v in prefix {
        out.push(v)
      }
      for v in new_suffix {
        out.push(v)
      }
      return Some(out)
    }
    if lb > rb {
      return None
    }
  }
  if l.length() < r.length() {
    let prefix = slice_array(r, 0, shorter_len + 1)
    if prefix[prefix.length() - 1].to_int() < TERMINATOR.to_int() {
      return None
    }
    let suffix = slice_array(r, shorter_len + 1, r.length())
    let new_suffix = new_before(Bytes::from_array(suffix))
    let out : Array[Byte] = []
    for v in prefix {
      out.push(v)
    }
    for v in new_suffix {
      out.push(v)
    }
    return Some(out)
  }
  if l.length() == r.length() {
    return None
  }
  let prefix = slice_array(l, 0, shorter_len + 1)
  if prefix[prefix.length() - 1].to_int() >= TERMINATOR.to_int() {
    return None
  }
  let suffix = slice_array(l, shorter_len + 1, l.length())
  let new_suffix = new_after(Bytes::from_array(suffix))
  let out : Array[Byte] = []
  for v in prefix {
    out.push(v)
  }
  for v in new_suffix {
    out.push(v)
  }
  Some(out)
}
