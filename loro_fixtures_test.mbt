///|
fn[T] expect_ok(res : Result[T, @types.LoroError], label : String) -> T raise {
  match res {
    Ok(value) => value
    Err(err) => fail("\{label} failed: \{err}")
  }
}

///|
fn[T] expect_some(value : T?, label : String) -> T raise {
  match value {
    Some(v) => v
    None => fail("missing \{label}")
  }
}

///|
fn expect_map(
  value : @types.LoroValue,
  label : String,
) -> Map[String, @types.LoroValue] raise {
  match value {
    @types.LoroValue::Map(map) => map
    _ => fail("expected map: \{label}")
  }
}

///|
fn expect_list(
  value : @types.LoroValue,
  label : String,
) -> Array[@types.LoroValue] raise {
  match value {
    @types.LoroValue::List(items) => items
    _ => fail("expected list: \{label}")
  }
}

///|
fn expect_string(value : @types.LoroValue, label : String) -> String raise {
  match value {
    @types.LoroValue::String(s) => s
    _ => fail("expected string: \{label}")
  }
}

///|
fn expect_bool(value : @types.LoroValue, label : String) -> Bool raise {
  match value {
    @types.LoroValue::Bool(v) => v
    _ => fail("expected bool: \{label}")
  }
}

///|
fn map_entry(
  map : Map[String, @types.LoroValue],
  key : String,
  label : String,
) -> @types.LoroValue raise {
  expect_some(map.get(key), "\{label}.\{key}")
}

///|
fn list_entry(
  items : Array[@types.LoroValue],
  index : Int,
  label : String,
) -> @types.LoroValue raise {
  if index < 0 || index >= items.length() {
    fail("index \{index} out of range for \{label}")
  }
  items[index]
}

///|
fn delta_has_bool_attr(
  delta : Array[@types.LoroValue],
  key : String,
  expected : Bool,
) -> Bool {
  for item in delta {
    match item {
      @types.LoroValue::Map(map) =>
        match map.get("attributes") {
          Some(@types.LoroValue::Map(attrs)) =>
            match attrs.get(key) {
              Some(@types.LoroValue::Bool(value)) =>
                if value == expected {
                  return true
                } else {
                  ()
                }
              _ => ()
            }
          _ => ()
        }
      _ => ()
    }
  }
  false
}

///|
fn delta_has_string_attr(
  delta : Array[@types.LoroValue],
  key : String,
  expected : String,
) -> Bool {
  for item in delta {
    match item {
      @types.LoroValue::Map(map) =>
        match map.get("attributes") {
          Some(@types.LoroValue::Map(attrs)) =>
            match attrs.get(key) {
              Some(@types.LoroValue::String(value)) =>
                if value == expected {
                  return true
                } else {
                  ()
                }
              _ => ()
            }
          _ => ()
        }
      _ => ()
    }
  }
  false
}

///|
fn tree_node_title(node : @types.LoroValue, label : String) -> String raise {
  let map = expect_map(node, label)
  let meta_value = map_entry(map, "meta", label)
  let meta = expect_map(meta_value, "\{label}.meta")
  let title_value = map_entry(meta, "title", label)
  expect_string(title_value, "\{label}.meta.title")
}

///|
fn decoded_text_insert_pos(
  changes : Array[@encoding.DecodedChange],
  text : String,
) -> Int? {
  for change in changes {
    for op in change.ops {
      match op.content {
        @op.RawOpContent::List(list_op) =>
          match list_op {
            @op.ListOp::Insert(slice~, pos~) =>
              match slice {
                @op.ListSlice::RawStr(str~, unicode_len=_) =>
                  if str == text {
                    return Some(pos)
                  } else {
                    ()
                  }
                _ => ()
              }
            _ => ()
          }
        _ => ()
      }
    }
  }
  None
}

///|
fn assert_fixture_state(doc : LoroDoc) -> Unit raise {
  let note = doc.get_text("note")
  let text = expect_ok(doc.text_to_string(note), "text_to_string")
  assert_eq(text, "Hello World 世界")
  let delta = expect_ok(doc.text_to_delta(note), "text_to_delta")
  guard delta_has_bool_attr(delta, "bold", true) else {
    fail("missing bold attribute in delta")
  }
  guard delta_has_string_attr(delta, "link", "https://example.com") else {
    fail("missing link attribute in delta")
  }
  let deep = doc.get_deep_value()
  let root = expect_map(deep, "root")
  let profile = expect_map(map_entry(root, "profile", "root"), "profile")
  assert_eq(
    expect_string(map_entry(profile, "name", "profile"), "profile.name"),
    "Ada",
  )
  assert_eq(
    expect_string(map_entry(profile, "role", "profile"), "profile.role"),
    "writer",
  )
  guard expect_bool(map_entry(profile, "active", "profile"), "profile.active") else {
    fail("profile.active mismatch")
  }
  let tags = expect_list(map_entry(profile, "tags", "profile"), "profile.tags")
  assert_eq(
    expect_string(list_entry(tags, 0, "profile.tags"), "tags[0]"),
    "crdt",
  )
  assert_eq(
    expect_string(list_entry(tags, 1, "profile.tags"), "tags[1]"),
    "moonbit",
  )
  assert_eq(
    expect_string(map_entry(profile, "bio", "profile"), "profile.bio"),
    "loro",
  )
  let items = expect_list(map_entry(root, "items", "root"), "items")
  guard items.length() == 4 else { fail("items length") }
  assert_eq(expect_string(list_entry(items, 0, "items"), "items[0]"), "alpha")
  assert_eq(expect_string(list_entry(items, 1, "items"), "items[1]"), "gamma")
  assert_eq(
    expect_string(list_entry(items, 2, "items"), "items[2]"),
    "list text",
  )
  let item_map = expect_map(list_entry(items, 3, "items"), "items[3]")
  assert_eq(
    expect_string(map_entry(item_map, "k", "items[3]"), "items[3].k"),
    "v",
  )
  let movable = expect_list(map_entry(root, "movable", "root"), "movable")
  guard movable.length() == 3 else { fail("movable length") }
  assert_eq(expect_string(list_entry(movable, 0, "movable"), "movable[0]"), "c")
  assert_eq(
    expect_string(list_entry(movable, 1, "movable"), "movable[1]"),
    "alpha",
  )
  let movable_nested = expect_list(
    list_entry(movable, 2, "movable"),
    "movable[2]",
  )
  assert_eq(
    expect_string(list_entry(movable_nested, 0, "movable[2]"), "movable[2][0]"),
    "nested",
  )
  let peer2_map = expect_map(map_entry(root, "peer2_map", "root"), "peer2_map")
  assert_eq(
    expect_string(
      map_entry(peer2_map, "status", "peer2_map"),
      "peer2_map.status",
    ),
    "online",
  )
  assert_eq(
    expect_string(map_entry(peer2_map, "notes", "peer2_map"), "peer2_map.notes"),
    "hi from peer2",
  )
  let peer2_list = expect_list(
    map_entry(root, "peer2_list", "root"),
    "peer2_list",
  )
  assert_eq(
    expect_string(list_entry(peer2_list, 0, "peer2_list"), "peer2_list[0]"),
    "p2",
  )
  assert_eq(
    expect_string(map_entry(root, "peer2_text", "root"), "peer2_text"),
    "peer2",
  )
  let big_map = expect_map(map_entry(root, "big_map", "root"), "big_map")
  assert_eq(
    expect_string(map_entry(big_map, "k0", "big_map"), "big_map.k0"),
    "v0",
  )
  assert_eq(
    expect_string(map_entry(big_map, "k199", "big_map"), "big_map.k199"),
    "v199",
  )
  assert_eq(
    expect_string(map_entry(big_map, "notes", "big_map"), "big_map.notes"),
    "big map notes",
  )
  let big_list = expect_list(map_entry(root, "big_list", "root"), "big_list")
  guard big_list.length() >= 190 else { fail("big_list length") }
  assert_eq(
    expect_string(list_entry(big_list, 0, "big_list"), "big_list[0]"),
    "item-0",
  )
  let big_list_meta = expect_map(
    list_entry(big_list, 100, "big_list"),
    "big_list[100]",
  )
  assert_eq(
    expect_string(
      map_entry(big_list_meta, "seed", "big_list[100]"),
      "big_list[100].seed",
    ),
    "ok",
  )
  let big_text = expect_string(map_entry(root, "big_text", "root"), "big_text")
  guard big_text.length() > 8000 else { fail("big_text length") }
  let counter = doc.get_counter("counter")
  let counter_value = expect_ok(doc.counter_value(counter), "counter_value")
  guard counter_value == 2.0 else { fail("counter mismatch") }
  let peer2_counter = doc.get_counter("peer2_counter")
  let peer2_counter_value = expect_ok(
    doc.counter_value(peer2_counter),
    "peer2_counter_value",
  )
  guard peer2_counter_value == 4.0 else { fail("peer2 counter mismatch") }
  let tree = doc.get_tree("outline")
  let tree_value = expect_ok(doc.tree_get_value_with_meta(tree), "tree value")
  let roots = expect_list(tree_value, "tree roots")
  guard roots.length() == 1 else { fail("tree root count") }
  let root_node = roots[0]
  assert_eq(tree_node_title(root_node, "root node"), "Root")
  let root_map = expect_map(root_node, "root node")
  let root_children = expect_list(
    map_entry(root_map, "children", "root node"),
    "root children",
  )
  guard root_children.length() == 2 else { fail("root children count") }
  assert_eq(tree_node_title(root_children[0], "root child 0"), "B")
  assert_eq(tree_node_title(root_children[1], "root child 1"), "A")
  let child_a = expect_map(root_children[1], "child A")
  let child_a_children = expect_list(
    map_entry(child_a, "children", "child A"),
    "child A children",
  )
  guard child_a_children.length() == 1 else { fail("child A children count") }
  assert_eq(tree_node_title(child_a_children[0], "child A1"), "A1")
  let child_a_meta = expect_map(
    map_entry(child_a, "meta", "child A"),
    "child A meta",
  )
  let child_a_tags = expect_list(
    map_entry(child_a_meta, "tags", "child A meta"),
    "child A tags",
  )
  assert_eq(
    expect_string(
      list_entry(child_a_tags, 0, "child A tags"),
      "child A tags[0]",
    ),
    "x",
  )
  assert_eq(
    expect_string(
      list_entry(child_a_tags, 1, "child A tags"),
      "child A tags[1]",
    ),
    "y",
  )
  let big_tree = doc.get_tree("big_tree")
  let big_tree_value = expect_ok(
    doc.tree_get_value_with_meta(big_tree),
    "big tree value",
  )
  let big_roots = expect_list(big_tree_value, "big tree roots")
  guard big_roots.length() == 1 else { fail("big tree root count") }
  let big_root_map = expect_map(big_roots[0], "big tree root")
  let big_root_children = expect_list(
    map_entry(big_root_map, "children", "big tree root"),
    "big tree children",
  )
  guard big_root_children.length() == 10 else { fail("big tree child count") }
}

///|
test "loro fixture: decoded updates include chinese insert" {
  let payload = expect_ok(
    @encoding.decode_payload(loro_fixture_updates),
    "decode payload",
  )
  let changes = match payload {
    @encoding.DecodedPayload::Updates(cs) => cs
    _ => fail("expected updates payload")
  }
  let pos = match decoded_text_insert_pos(changes, " 世界") {
    Some(p) => p
    None => fail("missing text insert op")
  }
  guard pos == 17 else { fail("unexpected text insert position: \{pos}") }
}

///|
test "loro fixture: import updates" {
  let doc = LoroDoc::new()
  ignore(expect_ok(doc.import_bytes(loro_fixture_updates), "import updates"))
  assert_fixture_state(doc)
}

///|
test "loro fixture: import snapshot" {
  let doc = LoroDoc::new()
  ignore(expect_ok(doc.import_bytes(loro_fixture_snapshot), "import snapshot"))
  assert_fixture_state(doc)
}

///|
test "loro fixture: import shallow snapshot" {
  let doc = LoroDoc::new()
  ignore(
    expect_ok(
      doc.import_bytes(loro_fixture_shallow_snapshot),
      "import shallow snapshot",
    ),
  )
  assert_fixture_state(doc)
}
