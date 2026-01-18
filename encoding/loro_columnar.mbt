///|
const MAX_RLE_COUNT : Int = 1000000000

///|
const MAX_DELTA_OF_DELTA : Int64 = 1048576

///|
pub fn encode_bool_rle(values : Array[Bool]) -> Bytes {
  if values.length() == 0 {
    return b""
  }
  let counts : Array[Int] = []
  let mut current = false
  if values[0] != current {
    counts.push(0)
    current = !current
  }
  let mut idx = 0
  while idx < values.length() {
    let mut run = 0
    while idx + run < values.length() && values[idx + run] == current {
      run = run + 1
    }
    counts.push(run)
    idx = idx + run
    current = !current
  }
  let writer = PostcardWriter::new()
  for count in counts {
    writer.write_varint_usize(count)
  }
  writer.to_bytes()
}

///|
fn encode_any_rle_int64(
  values : Array[Int64],
  write_value : (PostcardWriter, Int64) -> Unit,
) -> Bytes {
  let writer = PostcardWriter::new()
  if values.length() == 0 {
    return writer.to_bytes()
  }
  let mut i = 0
  while i < values.length() {
    let value = values[i]
    let mut run = 1
    while i + run < values.length() && values[i + run] == value {
      run = run + 1
    }
    if run >= 2 {
      writer.write_varint_isize(run)
      write_value(writer, value)
      i = i + run
    } else {
      let start = i
      i = i + 1
      while i < values.length() {
        let next = values[i]
        let mut next_run = 1
        while i + next_run < values.length() && values[i + next_run] == next {
          next_run = next_run + 1
        }
        if next_run >= 2 {
          break
        }
        i = i + 1
      }
      let literal_len = i - start
      writer.write_varint_isize(-literal_len)
      for j = start; j < i; j = j + 1 {
        write_value(writer, values[j])
      }
    }
  }
  writer.to_bytes()
}

///|
pub fn encode_rle_u32(values : Array[Int]) -> Bytes {
  let write_value = (writer : PostcardWriter, value : Int64) => writer.write_varint_u32(
    value.to_int().reinterpret_as_uint(),
  )
  let items = values.map(v => v.to_int64())
  encode_any_rle_int64(items, write_value)
}

///|
pub fn encode_rle_u8(values : Array[Byte]) -> Bytes {
  let write_value = (writer : PostcardWriter, value : Int64) => writer.write_u8(
    value.to_int().to_byte(),
  )
  let items = values.map(v => v.to_int64())
  encode_any_rle_int64(items, write_value)
}

///|
pub fn encode_delta_rle_u32(values : Array[Int]) -> Bytes {
  let deltas : Array[Int64] = []
  let mut prev : Int64 = 0
  for value in values {
    let current = value.to_int64()
    deltas.push(current - prev)
    prev = current
  }
  let write_value = (writer : PostcardWriter, value : Int64) => writer.write_varint_i64(
    value,
  )
  encode_any_rle_int64(deltas, write_value)
}

///|
pub fn encode_delta_rle_i32(values : Array[Int]) -> Bytes {
  encode_delta_rle_u32(values)
}

///|
pub fn encode_delta_rle_usize(values : Array[Int]) -> Bytes {
  encode_delta_rle_u32(values)
}

///|
pub fn encode_delta_of_delta_i64(values : Array[Int64]) -> Bytes {
  let writer = PostcardWriter::new()
  if values.length() == 0 {
    writer.write_option_i64(None)
    writer.write_u8(0)
    return writer.to_bytes()
  }
  writer.write_option_i64(Some(values[0]))
  let bits = BitWriter::new()
  let mut prev_value = values[0]
  let mut prev_delta : Int64 = 0
  let min_7 = Int64::from_int(-63)
  let max_7 = Int64::from_int(64)
  let min_9 = Int64::from_int(-255)
  let max_9 = Int64::from_int(256)
  let min_12 = Int64::from_int(-2047)
  let max_12 = Int64::from_int(2048)
  let min_21 = Int64::from_int(-1048575)
  let max_21 = Int64::from_int(1048576)
  for i = 1; i < values.length(); i = i + 1 {
    let value = values[i]
    let delta = value - prev_value
    let dod = delta - prev_delta
    if dod == 0 {
      bits.write_bit(0)
    } else {
      bits.write_bit(1)
      if dod >= min_7 && dod <= max_7 {
        bits.write_bit(0)
        let raw = (dod + Int64::from_int(63)).reinterpret_as_uint64()
        bits.write_bits(raw, 7)
      } else if dod >= min_9 && dod <= max_9 {
        bits.write_bits(0x2UL, 2)
        let raw = (dod + Int64::from_int(255)).reinterpret_as_uint64()
        bits.write_bits(raw, 9)
      } else if dod >= min_12 && dod <= max_12 {
        bits.write_bits(0x6UL, 3)
        let raw = (dod + Int64::from_int(2047)).reinterpret_as_uint64()
        bits.write_bits(raw, 12)
      } else if dod >= min_21 && dod <= max_21 {
        bits.write_bits(0xEUL, 4)
        let raw = (dod + Int64::from_int(1048575)).reinterpret_as_uint64()
        bits.write_bits(raw, 21)
      } else {
        bits.write_bits(0x1FUL, 5)
        bits.write_bits(dod.reinterpret_as_uint64(), 64)
      }
    }
    prev_delta = prev_delta + dod
    prev_value = value
  }
  let (bits_bytes, last_used_bit) = bits.finalize()
  writer.write_u8(last_used_bit.to_byte())
  writer.write_bytes(bits_bytes)
  writer.to_bytes()
}

///|
pub fn encode_delta_of_delta_u32(values : Array[Int]) -> Bytes {
  let items = values.map(v => v.to_int64())
  encode_delta_of_delta_i64(items)
}

///|
pub fn take_n_bool_rle(
  bytes : Bytes,
  n : Int,
) -> Result[(Array[Bool], Bytes), @types.LoroError] {
  let reader = PostcardReader::new(bytes)
  let out : Array[Bool] = []
  let mut count = 0
  let mut last = true
  while out.length() < n {
    if count == 0 {
      let next = match reader.try_read_varint_usize() {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      match next {
        None => return Err(@types.LoroError::DecodeError("bool rle underrun"))
        Some(value) => {
          if value > MAX_RLE_COUNT {
            return Err(@types.LoroError::DecodeError("bool rle too large"))
          }
          count = value
          last = !last
        }
      }
    }
    if count == 0 {
      continue
    }
    count = count - 1
    out.push(last)
  }
  Ok((out, reader.remaining_bytes()))
}

///|
pub fn decode_bool_rle(bytes : Bytes) -> Result[Array[Bool], @types.LoroError] {
  let reader = PostcardReader::new(bytes)
  let out : Array[Bool] = []
  let mut count = 0
  let mut last = true
  while true {
    if count == 0 {
      let next = match reader.try_read_varint_usize() {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      match next {
        None => break
        Some(value) => {
          if value > MAX_RLE_COUNT {
            return Err(@types.LoroError::DecodeError("bool rle too large"))
          }
          count = value
          last = !last
        }
      }
    }
    if count == 0 {
      continue
    }
    count = count - 1
    out.push(last)
  }
  if reader.remaining() != 0 {
    return Err(@types.LoroError::DecodeError("bool rle trailing bytes"))
  }
  Ok(out)
}

///|
fn take_n_any_rle_int64(
  bytes : Bytes,
  n : Int,
  read_value : (PostcardReader) -> Result[Int64, @types.LoroError],
) -> Result[(Array[Int64], Bytes), @types.LoroError] {
  let reader = PostcardReader::new(bytes)
  let out : Array[Int64] = []
  let mut count = 0
  let mut literal = false
  let mut last : Int64? = None
  while out.length() < n {
    if count == 0 {
      let next = match reader.try_read_varint_isize() {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      match next {
        None => return Err(@types.LoroError::DecodeError("rle underrun"))
        Some(value) => {
          if value == 0 {
            return Err(@types.LoroError::DecodeError("invalid rle count"))
          }
          let abs = abs_int(value)
          if abs > MAX_RLE_COUNT {
            return Err(@types.LoroError::DecodeError("rle too large"))
          }
          if value > 0 {
            count = value
            literal = false
            let v = match read_value(reader) {
              Ok(val) => val
              Err(err) => return Err(err)
            }
            last = Some(v)
          } else {
            count = abs
            literal = true
          }
        }
      }
    }
    count = count - 1
    if literal {
      let v = match read_value(reader) {
        Ok(val) => val
        Err(err) => return Err(err)
      }
      out.push(v)
    } else {
      match last {
        Some(v) => out.push(v)
        None => return Err(@types.LoroError::DecodeError("rle missing value"))
      }
    }
  }
  Ok((out, reader.remaining_bytes()))
}

///|
fn decode_any_rle_int64(
  bytes : Bytes,
  read_value : (PostcardReader) -> Result[Int64, @types.LoroError],
) -> Result[Array[Int64], @types.LoroError] {
  let reader = PostcardReader::new(bytes)
  let out : Array[Int64] = []
  let mut count = 0
  let mut literal = false
  let mut last : Int64? = None
  while true {
    if count == 0 {
      let next = match reader.try_read_varint_isize() {
        Ok(v) => v
        Err(err) => return Err(err)
      }
      match next {
        None => break
        Some(value) => {
          if value == 0 {
            return Err(@types.LoroError::DecodeError("invalid rle count"))
          }
          let abs = abs_int(value)
          if abs > MAX_RLE_COUNT {
            return Err(@types.LoroError::DecodeError("rle too large"))
          }
          if value > 0 {
            count = value
            literal = false
            let v = match read_value(reader) {
              Ok(val) => val
              Err(err) => return Err(err)
            }
            last = Some(v)
          } else {
            count = abs
            literal = true
          }
        }
      }
    }
    count = count - 1
    if literal {
      let v = match read_value(reader) {
        Ok(val) => val
        Err(err) => return Err(err)
      }
      out.push(v)
    } else {
      match last {
        Some(v) => out.push(v)
        None => return Err(@types.LoroError::DecodeError("rle missing value"))
      }
    }
  }
  if reader.remaining() != 0 {
    return Err(@types.LoroError::DecodeError("rle trailing bytes"))
  }
  Ok(out)
}

///|
pub fn take_n_any_rle_usize(
  bytes : Bytes,
  n : Int,
) -> Result[(Array[Int], Bytes), @types.LoroError] {
  let read_value = (reader : PostcardReader) => match
    reader.read_varint_usize() {
    Ok(v) => Ok(v.to_int64())
    Err(err) => Err(err)
  }
  let (vals, rest) = match take_n_any_rle_int64(bytes, n, read_value) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok((vals.map(v => v.to_int()), rest))
}

///|
pub fn take_n_any_rle_u32(
  bytes : Bytes,
  n : Int,
) -> Result[(Array[Int], Bytes), @types.LoroError] {
  let read_value = (reader : PostcardReader) => match reader.read_varint_u32() {
    Ok(v) => Ok(v.to_int64())
    Err(err) => Err(err)
  }
  let (vals, rest) = match take_n_any_rle_int64(bytes, n, read_value) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok((vals.map(v => v.to_int()), rest))
}

///|
pub fn decode_rle_u32(bytes : Bytes) -> Result[Array[Int], @types.LoroError] {
  let read_value = (reader : PostcardReader) => match reader.read_varint_u32() {
    Ok(v) => Ok(v.to_int64())
    Err(err) => Err(err)
  }
  let vals = match decode_any_rle_int64(bytes, read_value) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(vals.map(v => v.to_int()))
}

///|
pub fn decode_rle_u8(bytes : Bytes) -> Result[Array[Byte], @types.LoroError] {
  let read_value = (reader : PostcardReader) => match reader.read_u8() {
    Ok(v) => Ok(v.to_int64())
    Err(err) => Err(err)
  }
  let vals = match decode_any_rle_int64(bytes, read_value) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok(vals.map(v => v.to_int().to_byte()))
}

///|
pub fn decode_delta_rle_u32(
  bytes : Bytes,
) -> Result[Array[Int], @types.LoroError] {
  let read_value = (reader : PostcardReader) => match reader.read_varint_i64() {
    Ok(v) => Ok(v)
    Err(err) => Err(err)
  }
  let deltas = match decode_any_rle_int64(bytes, read_value) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let out : Array[Int] = []
  let mut abs : Int64 = 0
  for d in deltas {
    abs = abs + d
    out.push(abs.to_int())
  }
  Ok(out)
}

///|
pub fn decode_delta_rle_i32(
  bytes : Bytes,
) -> Result[Array[Int], @types.LoroError] {
  decode_delta_rle_u32(bytes)
}

///|
pub fn decode_delta_rle_usize(
  bytes : Bytes,
) -> Result[Array[Int], @types.LoroError] {
  decode_delta_rle_u32(bytes)
}

///|
pub fn take_n_delta_of_delta_i64(
  bytes : Bytes,
  n : Int,
) -> Result[(Array[Int64], Bytes), @types.LoroError] {
  let decoder = match DeltaOfDeltaDecoder::new(bytes) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  decoder.take_n_finalize(n)
}

///|
pub fn take_n_delta_of_delta_u32(
  bytes : Bytes,
  n : Int,
) -> Result[(Array[Int], Bytes), @types.LoroError] {
  let (vals, rest) = match take_n_delta_of_delta_i64(bytes, n) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  Ok((vals.map(v => v.to_int()), rest))
}

///|
pub fn take_n_delta_rle_u32(
  bytes : Bytes,
  n : Int,
) -> Result[(Array[Int], Bytes), @types.LoroError] {
  let read_value = (reader : PostcardReader) => match reader.read_varint_i64() {
    Ok(v) => Ok(v)
    Err(err) => Err(err)
  }
  let (deltas, rest) = match take_n_any_rle_int64(bytes, n, read_value) {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  let out : Array[Int] = []
  let mut abs : Int64 = 0
  for d in deltas {
    abs = abs + d
    out.push(abs.to_int())
  }
  Ok((out, rest))
}

///|
priv struct DeltaOfDeltaDecoder {
  bits : Bytes
  last_used_bit : Int
  mut index : Int
  mut current_bits_index : Int
  mut head : Int64?
  mut prev_value : Int64
  mut prev_delta : Int64
}

///|
fn DeltaOfDeltaDecoder::new(
  bytes : Bytes,
) -> Result[DeltaOfDeltaDecoder, @types.LoroError] {
  let reader = PostcardReader::new(bytes)
  let head = match reader.read_option_i64() {
    Ok(v) => v
    Err(err) => return Err(err)
  }
  if reader.remaining() == 0 {
    return Err(@types.LoroError::DecodeError("delta-of-delta missing bits"))
  }
  let last_used_bit = match reader.read_u8() {
    Ok(v) => v.to_int()
    Err(err) => return Err(err)
  }
  let bits = reader.remaining_bytes()
  Ok(DeltaOfDeltaDecoder::{
    bits,
    last_used_bit,
    index: 0,
    current_bits_index: 0,
    head,
    prev_value: 0,
    prev_delta: 0,
  })
}

///|
fn DeltaOfDeltaDecoder::try_next(
  self : DeltaOfDeltaDecoder,
) -> Result[Int64?, @types.LoroError] {
  match self.head {
    Some(value) => {
      self.head = None
      self.prev_value = value
      Ok(Some(value))
    }
    None => {
      let flag = match self.read_bits(1) {
        Some(v) => v
        None => return Ok(None)
      }
      if flag == 0 {
        self.prev_value = self.prev_value + self.prev_delta
        return Ok(Some(self.prev_value))
      }
      let bit1 = match self.read_bits(1) {
        Some(v) => v
        None => return Err(@types.LoroError::DecodeError("delta bits missing"))
      }
      let (num_bits, bias) = if bit1 == 0 {
        (7, Int64::from_int(63))
      } else {
        let bit2 = match self.read_bits(1) {
          Some(v) => v
          None =>
            return Err(@types.LoroError::DecodeError("delta bits missing"))
        }
        if bit2 == 0 {
          (9, Int64::from_int(255))
        } else {
          let bit3 = match self.read_bits(1) {
            Some(v) => v
            None =>
              return Err(@types.LoroError::DecodeError("delta bits missing"))
          }
          if bit3 == 0 {
            (12, Int64::from_int(2047))
          } else {
            let bit4 = match self.read_bits(1) {
              Some(v) => v
              None =>
                return Err(@types.LoroError::DecodeError("delta bits missing"))
            }
            if bit4 == 0 {
              (21, MAX_DELTA_OF_DELTA - Int64::from_int(1))
            } else {
              (64, Int64::from_int(0))
            }
          }
        }
      }
      let raw = match self.read_bits(num_bits) {
        Some(v) => v
        None => return Err(@types.LoroError::DecodeError("delta bits missing"))
      }
      let delta = raw.reinterpret_as_int64() - bias
      self.prev_delta = self.prev_delta + delta
      self.prev_value = self.prev_value + self.prev_delta
      Ok(Some(self.prev_value))
    }
  }
}

///|
fn DeltaOfDeltaDecoder::take_n_finalize(
  self : DeltaOfDeltaDecoder,
  n : Int,
) -> Result[(Array[Int64], Bytes), @types.LoroError] {
  let out : Array[Int64] = []
  for i = 0; i < n; i = i + 1 {
    let next = match self.try_next() {
      Ok(v) => v
      Err(err) => return Err(err)
    }
    match next {
      Some(v) => out.push(v)
      None =>
        return Err(@types.LoroError::DecodeError("delta-of-delta underrun"))
    }
  }
  Ok((out, self.finalize()))
}

///|
fn DeltaOfDeltaDecoder::finalize(self : DeltaOfDeltaDecoder) -> Bytes {
  if self.bits.length() == 0 {
    return self.bits
  }
  if self.current_bits_index > 0 {
    self.index = self.index + 1
  }
  if self.index >= self.bits.length() {
    return b""
  }
  self.bits.sub(start=self.index, end=self.bits.length()).to_bytes()
}

///|
fn DeltaOfDeltaDecoder::read_bits(
  self : DeltaOfDeltaDecoder,
  count : Int,
) -> UInt64? {
  if self.index >= self.bits.length() {
    return None
  }
  let total_bits = (self.bits.length() - 1) * 8 + self.last_used_bit
  let read_bits = self.index * 8 + self.current_bits_index
  let remaining_bits = total_bits - read_bits
  if remaining_bits < count {
    return None
  }
  let current_byte_remaining = 8 - self.current_bits_index
  if count <= current_byte_remaining {
    let current = self.bits[self.index].to_uint()
    let shift = current_byte_remaining - count
    let after_shift = current >> shift
    let mask = 0xFFU >> (8 - count)
    let ans = after_shift & mask
    self.current_bits_index = self.current_bits_index + count
    if self.current_bits_index == 8 {
      self.index = self.index + 1
      self.current_bits_index = 0
    }
    return Some(ans.to_uint64())
  }
  let mut ans = (self.bits[self.index].to_uint() &
  (0xFFU >> (8 - current_byte_remaining))).to_uint64()
  self.index = self.index + 1
  self.current_bits_index = 0
  let mut rest = count - current_byte_remaining
  while rest > 8 {
    ans = (ans << 8) | self.bits[self.index].to_uint64()
    self.index = self.index + 1
    rest = rest - 8
  }
  ans = (ans << rest) |
    (self.bits[self.index].to_uint() >> (8 - rest)).to_uint64()
  self.current_bits_index = self.current_bits_index + rest
  if self.current_bits_index == 8 {
    self.index = self.index + 1
    self.current_bits_index = 0
  }
  Some(ans)
}

///|
fn abs_int(value : Int) -> Int {
  if value >= 0 {
    value
  } else {
    -value
  }
}

///|
priv struct BitWriter {
  buf : @buffer.Buffer
  mut current : UInt
  mut used : Int
}

///|
fn BitWriter::new() -> BitWriter {
  BitWriter::{ buf: @buffer.new(), current: 0U, used: 0 }
}

///|
fn BitWriter::write_bit(self : BitWriter, bit : UInt) -> Unit {
  if bit != 0U {
    let shift = 7 - self.used
    self.current = self.current | (1U << shift)
  }
  self.used = self.used + 1
  if self.used == 8 {
    self.buf.write_byte(self.current.reinterpret_as_int().to_byte())
    self.current = 0U
    self.used = 0
  }
}

///|
fn BitWriter::write_bits(self : BitWriter, value : UInt64, count : Int) -> Unit {
  for offset = 0; offset < count; offset = offset + 1 {
    let shift = count - 1 - offset
    let bit = (value >> shift) & 1UL
    self.write_bit(bit.to_uint())
  }
}

///|
fn BitWriter::finalize(self : BitWriter) -> (Bytes, Int) {
  if self.used > 0 {
    self.buf.write_byte(self.current.reinterpret_as_int().to_byte())
  }
  let bytes = self.buf.to_bytes()
  let last_used_bit = if bytes.length() == 0 {
    0
  } else if self.used == 0 {
    8
  } else {
    self.used
  }
  (bytes, last_used_bit)
}
