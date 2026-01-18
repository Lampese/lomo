///|
test "loro value writer roundtrip" {
  let keys : Array[String] = ["a", "b", "c"]
  let value = @types.LoroValue::Map({
    "a": @types.LoroValue::I64(42),
    "b": @types.LoroValue::List([
      @types.LoroValue::Bool(true),
      @types.LoroValue::String("hi"),
    ]),
    "c": @types.LoroValue::String("ok"),
  })
  let id = @types.ID::new(1, 0)
  let writer = @encoding.LoroValueWriter::new()
  match writer.write_value_type_and_content(value, keys, id) {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  let bytes = writer.to_bytes()
  let reader = @encoding.LoroValueReader::new(bytes)
  let decoded = match reader.read_value_type_and_content(keys, id) {
    Ok(v) => v
    Err(err) => fail("\{err}")
  }
  match decoded {
    @types.LoroValue::Map(map) => {
      guard map.length() == 3 else { fail("map length") }
      match map.get("a") {
        Some(@types.LoroValue::I64(v)) => if v != 42 { fail("a value") }
        _ => fail("missing a")
      }
      match map.get("b") {
        Some(@types.LoroValue::List(items)) => {
          guard items.length() == 2 else { fail("b length") }
          match items[0] {
            @types.LoroValue::Bool(true) => ()
            _ => fail("b[0]")
          }
          match items[1] {
            @types.LoroValue::String(s) => if s != "hi" { fail("b[1]") }
            _ => fail("b[1]")
          }
        }
        _ => fail("missing b")
      }
      match map.get("c") {
        Some(@types.LoroValue::String(s)) => if s != "ok" { fail("c value") }
        _ => fail("missing c")
      }
    }
    _ => fail("expected map")
  }
  guard reader.remaining() == 0 else { fail("trailing bytes") }
}
