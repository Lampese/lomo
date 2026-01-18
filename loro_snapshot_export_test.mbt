///|
fn[T] ls_expect_ok(
  res : Result[T, @types.LoroError],
  label : String,
) -> T raise {
  match res {
    Ok(value) => value
    Err(err) => fail("\{label} failed: \{err}")
  }
}

///|
fn ls_expect_map(
  value : @types.LoroValue,
  label : String,
) -> Map[String, @types.LoroValue] raise {
  match value {
    @types.LoroValue::Map(map) => map
    _ => fail("expected map: \{label}")
  }
}

///|
fn ls_expect_list(
  value : @types.LoroValue,
  label : String,
) -> Array[@types.LoroValue] raise {
  match value {
    @types.LoroValue::List(items) => items
    _ => fail("expected list: \{label}")
  }
}

///|
fn ls_expect_string(value : @types.LoroValue, label : String) -> String raise {
  match value {
    @types.LoroValue::String(s) => s
    _ => fail("expected string: \{label}")
  }
}

///|
fn ls_expect_bool(value : @types.LoroValue, label : String) -> Bool raise {
  match value {
    @types.LoroValue::Bool(v) => v
    _ => fail("expected bool: \{label}")
  }
}

///|
fn ls_expect_i64(value : @types.LoroValue, label : String) -> Int64 raise {
  match value {
    @types.LoroValue::I64(v) => v
    _ => fail("expected i64: \{label}")
  }
}

///|
fn ls_expect_f64(value : @types.LoroValue, label : String) -> Double raise {
  match value {
    @types.LoroValue::F64(v) => v
    _ => fail("expected f64: \{label}")
  }
}

///|
fn ls_map_entry(
  map : Map[String, @types.LoroValue],
  key : String,
  label : String,
) -> @types.LoroValue raise {
  match map.get(key) {
    Some(value) => value
    None => fail("missing \{label}.\{key}")
  }
}

///|
test "export/import loro snapshot roundtrip" {
  let doc1 = LoroDoc::new()
  let root = doc1.get_map("root")
  let list = doc1.get_list("list")
  let mlist = doc1.get_movable_list("mlist")
  let text = doc1.get_text("text")
  let tree = doc1.get_tree("tree")
  let counter = doc1.get_counter("counter")
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  ensure_ok(doc1.map_set(root, "title", @types.LoroValue::String("Loro")))
  let items_id = ls_expect_ok(
    doc1.map_insert_container(root, "items", @types.ContainerType::List),
    "map insert container",
  )
  let items = @container.ListHandler::new(items_id)
  ensure_ok(doc1.list_push(items, @types.LoroValue::I64(1)))
  ensure_ok(doc1.list_push(items, @types.LoroValue::String("two")))
  ensure_ok(doc1.list_push(list, @types.LoroValue::String("a")))
  ensure_ok(doc1.list_push(list, @types.LoroValue::String("b")))
  let nested_id = ls_expect_ok(
    doc1.list_insert_container(list, 1, @types.ContainerType::Map),
    "list insert container",
  )
  let nested_map = @container.MapHandler::new(nested_id)
  ensure_ok(doc1.map_set(nested_map, "nested", @types.LoroValue::Bool(true)))
  ensure_ok(doc1.list_set(list, 2, @types.LoroValue::String("b2")))
  ensure_ok(doc1.list_delete(list, 0, 1))
  ensure_ok(doc1.movable_list_push(mlist, @types.LoroValue::String("m1")))
  ensure_ok(doc1.movable_list_push(mlist, @types.LoroValue::String("m2")))
  ensure_ok(doc1.movable_list_move(mlist, 0, 1))
  ensure_ok(doc1.movable_list_set(mlist, 1, @types.LoroValue::String("m1x")))
  ensure_ok(doc1.movable_list_delete(mlist, 0, 1))
  ensure_ok(doc1.text_insert(text, 0, "Hello world"))
  ensure_ok(doc1.text_mark(text, 0, 5, "bold", @types.LoroValue::Bool(true)))
  ensure_ok(doc1.text_delete(text, 5, 1))
  let root1 = ls_expect_ok(doc1.tree_create(tree, None), "tree create root")
  let root2 = ls_expect_ok(doc1.tree_create(tree, None), "tree create root2")
  let child = ls_expect_ok(
    doc1.tree_create(tree, Some(root1)),
    "tree create child",
  )
  let meta = doc1.tree_get_meta(child)
  ensure_ok(doc1.map_set(meta, "name", @types.LoroValue::String("child")))
  ensure_ok(doc1.tree_move(tree, child, Some(root2)))
  ensure_ok(doc1.tree_delete(tree, root1))
  ensure_ok(doc1.counter_inc(counter, 2))
  ensure_ok(doc1.counter_inc(counter, 3))
  let snapshot = ls_expect_ok(
    doc1.export_loro_snapshot(),
    "export loro snapshot",
  )
  let doc2 = LoroDoc::new()
  ensure_ok(doc2.import_bytes(snapshot))
  let deep = doc2.get_deep_value()
  let root_map = ls_expect_map(deep, "root")
  let root_value = ls_expect_map(
    ls_map_entry(root_map, "root", "root"),
    "root.map",
  )
  let title = ls_map_entry(root_value, "title", "root.map")
  guard ls_expect_string(title, "root.title") == "Loro" else {
    fail("title mismatch")
  }
  let items_value = ls_expect_list(
    ls_map_entry(root_value, "items", "root.map"),
    "items",
  )
  guard items_value.length() == 2 else { fail("items length") }
  guard ls_expect_i64(items_value[0], "items[0]") == 1 else { fail("items[0]") }
  guard ls_expect_string(items_value[1], "items[1]") == "two" else {
    fail("items[1]")
  }
  let list_value = ls_expect_list(
    ls_map_entry(root_map, "list", "root"),
    "list",
  )
  guard list_value.length() == 2 else { fail("list length") }
  let nested = ls_expect_map(list_value[0], "list[0]")
  let nested_value = ls_map_entry(nested, "nested", "list[0]")
  guard ls_expect_bool(nested_value, "list[0].nested") else {
    fail("nested bool")
  }
  guard ls_expect_string(list_value[1], "list[1]") == "b2" else {
    fail("list[1]")
  }
  let mlist_value = ls_expect_list(
    ls_map_entry(root_map, "mlist", "root"),
    "mlist",
  )
  guard mlist_value.length() == 1 else { fail("mlist length") }
  guard ls_expect_string(mlist_value[0], "mlist[0]") == "m1x" else {
    fail("mlist[0]")
  }
  let text_value = ls_map_entry(root_map, "text", "root")
  guard ls_expect_string(text_value, "text") == "Helloworld" else {
    fail("text mismatch")
  }
  let counter_value = ls_map_entry(root_map, "counter", "root")
  guard ls_expect_f64(counter_value, "counter") == 5.0 else {
    fail("counter mismatch")
  }
  let tree_value = ls_expect_list(
    ls_map_entry(root_map, "tree", "root"),
    "tree",
  )
  guard tree_value.length() == 1 else { fail("tree roots length") }
  let tree_root = ls_expect_map(tree_value[0], "tree[0]")
  let children = ls_expect_list(
    ls_map_entry(tree_root, "children", "tree[0]"),
    "children",
  )
  guard children.length() == 1 else { fail("tree child length") }
  let text2 = doc2.get_text("text")
  let rich = match doc2.text_get_richtext_value(text2) {
    Ok(v) => v
    Err(err) => fail("\{err}")
  }
  let delta = ls_expect_list(rich, "richtext")
  guard delta.length() >= 1 else { fail("richtext empty") }
  let first = ls_expect_map(delta[0], "delta[0]")
  let attrs = match first.get("attributes") {
    Some(@types.LoroValue::Map(map)) => map
    _ => fail("missing attributes")
  }
  guard attrs.get("bold") is Some(@types.LoroValue::Bool(true)) else {
    fail("missing bold attr")
  }
}
