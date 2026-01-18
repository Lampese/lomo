///|
test "columnar bool rle roundtrip" {
  let values : Array[Bool] = [true, true, false, false, false, true]
  let bytes = @encoding.encode_bool_rle(values)
  let decoded = match @encoding.decode_bool_rle(bytes) {
    Ok(v) => v
    Err(err) => fail("\{err}")
  }
  assert_eq(decoded, values)
}

///|
test "columnar rle u32 roundtrip" {
  let values : Array[Int] = [1, 1, 2, 3, 3, 3, 4]
  let bytes = @encoding.encode_rle_u32(values)
  let decoded = match @encoding.decode_rle_u32(bytes) {
    Ok(v) => v
    Err(err) => fail("\{err}")
  }
  assert_eq(decoded, values)
}

///|
test "columnar delta rle roundtrip" {
  let values : Array[Int] = [5, 4, 4, 10, 9]
  let bytes = @encoding.encode_delta_rle_u32(values)
  let decoded = match @encoding.decode_delta_rle_u32(bytes) {
    Ok(v) => v
    Err(err) => fail("\{err}")
  }
  assert_eq(decoded, values)
}

///|
test "columnar delta-of-delta roundtrip" {
  let values : Array[Int64] = [1000, 1001, 1005, 1004, 1010]
  let bytes = @encoding.encode_delta_of_delta_i64(values)
  let (decoded, rest) = match
    @encoding.take_n_delta_of_delta_i64(bytes, values.length()) {
    Ok(v) => v
    Err(err) => fail("\{err}")
  }
  guard rest.length() == 0 else { fail("delta-of-delta trailing bytes") }
  assert_eq(decoded, values)
}
