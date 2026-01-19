///|
test "lz4 frame roundtrip small" {
  let data : Bytes = b"hello hello hello"
  let frame = lz4_encode_frame(data)
  let decoded = match lz4_decode_frame(frame) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  guard decoded == data else { fail("lz4 frame roundtrip failed") }
}

///|
test "lz4 frame roundtrip large" {
  let buf = @buffer.new()
  for i = 0; i < 20000; i = i + 1 {
    let v = (i % 4 * 7).to_byte()
    buf.write_byte(v)
  }
  let data = buf.to_bytes()
  let frame = lz4_encode_frame(data)
  let decoded = match lz4_decode_frame(frame) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  guard decoded == data else { fail("lz4 frame roundtrip failed") }
}
