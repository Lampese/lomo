///|
fn[T] aw_expect_ok(
  res : Result[T, @types.LoroError],
  label : String,
) -> T raise {
  match res {
    Ok(value) => value
    Err(err) => fail("\{label} failed: \{err}")
  }
}

///|
fn[T] aw_expect_some(value : T?, label : String) -> T raise {
  match value {
    Some(v) => v
    None => fail("missing \{label}")
  }
}

///|
fn aw_expect_map(
  value : @types.LoroValue,
  label : String,
) -> Map[String, @types.LoroValue] raise {
  match value {
    @types.LoroValue::Map(map) => map
    _ => fail("expected map: \{label}")
  }
}

///|
fn aw_expect_list(
  value : @types.LoroValue,
  label : String,
) -> Array[@types.LoroValue] raise {
  match value {
    @types.LoroValue::List(items) => items
    _ => fail("expected list: \{label}")
  }
}

///|
fn aw_map_entry(
  map : Map[String, @types.LoroValue],
  key : String,
  label : String,
) -> @types.LoroValue raise {
  expect_some(map.get(key), "\{label}.\{key}")
}

///|
test "awareness fixture simple" {
  let store = EphemeralStore::new(1000)
  ignore(aw_expect_ok(store.apply(awareness_fixture_simple), "apply"))
  let state = aw_expect_some(store.get("1"), "peer 1 state")
  let map = aw_expect_map(state, "state")
  match aw_map_entry(map, "n", "state") {
    @types.LoroValue::Null => ()
    _ => fail("expected null")
  }
  match aw_map_entry(map, "b", "state") {
    @types.LoroValue::Bool(true) => ()
    _ => fail("expected bool true")
  }
  match aw_map_entry(map, "i", "state") {
    @types.LoroValue::I64(1) => ()
    _ => fail("expected i64 1")
  }
  match aw_map_entry(map, "f", "state") {
    @types.LoroValue::F64(v) => if v != 1.5 { fail("expected f64 1.5") }
    _ => fail("expected f64")
  }
  match aw_map_entry(map, "s", "state") {
    @types.LoroValue::String("hi") => ()
    _ => fail("expected string")
  }
  match aw_map_entry(map, "bin", "state") {
    @types.LoroValue::Bytes(bytes) => {
      let expected : Bytes = [1, 2, 3]
      guard bytes == expected else { fail("expected bytes") }
    }
    _ => fail("expected bytes")
  }
  let list = aw_expect_list(aw_map_entry(map, "list", "state"), "state.list")
  guard list.length() == 3 else { fail("list length") }
  match list[0] {
    @types.LoroValue::I64(1) => ()
    _ => fail("list[0]")
  }
  match list[1] {
    @types.LoroValue::String("a") => ()
    _ => fail("list[1]")
  }
  match list[2] {
    @types.LoroValue::Bool(false) => ()
    _ => fail("list[2]")
  }
  let inner = aw_expect_map(aw_map_entry(map, "map", "state"), "state.map")
  match aw_map_entry(inner, "k", "state.map") {
    @types.LoroValue::String("v") => ()
    _ => fail("map.k")
  }
}

///|
test "awareness fixture multi" {
  let store = EphemeralStore::new(1000)
  ignore(aw_expect_ok(store.apply(awareness_fixture_multi), "apply"))
  let a = aw_expect_map(aw_expect_some(store.get("1"), "peer 1"), "peer1")
  let b = aw_expect_map(aw_expect_some(store.get("2"), "peer 2"), "peer2")
  match aw_map_entry(a, "a", "peer1") {
    @types.LoroValue::I64(1) => ()
    _ => fail("peer1.a")
  }
  match aw_map_entry(b, "b", "peer2") {
    @types.LoroValue::I64(2) => ()
    _ => fail("peer2.b")
  }
}

///|
test "awareness fixture clock ordering" {
  let store = EphemeralStore::new(1000)
  ignore(aw_expect_ok(store.apply(awareness_fixture_peer_v2), "apply v2"))
  ignore(aw_expect_ok(store.apply(awareness_fixture_peer_v1), "apply v1"))
  let state = aw_expect_map(aw_expect_some(store.get("1"), "peer 1"), "peer1")
  match aw_map_entry(state, "v", "peer1") {
    @types.LoroValue::I64(2) => ()
    _ => fail("expected v=2")
  }
}
