///|
fn[T] lu_expect_ok(
  res : Result[T, @types.LoroError],
  label : String,
) -> T raise {
  match res {
    Ok(value) => value
    Err(err) => fail("\{label} failed: \{err}")
  }
}

///|
fn lu_expect_map(
  value : @types.LoroValue,
  label : String,
) -> Map[String, @types.LoroValue] raise {
  match value {
    @types.LoroValue::Map(map) => map
    _ => fail("expected map: \{label}")
  }
}

///|
fn lu_expect_list(
  value : @types.LoroValue,
  label : String,
) -> Array[@types.LoroValue] raise {
  match value {
    @types.LoroValue::List(items) => items
    _ => fail("expected list: \{label}")
  }
}

///|
fn lu_expect_string(value : @types.LoroValue, label : String) -> String raise {
  match value {
    @types.LoroValue::String(s) => s
    _ => fail("expected string: \{label}")
  }
}

///|
fn lu_expect_bool(value : @types.LoroValue, label : String) -> Bool raise {
  match value {
    @types.LoroValue::Bool(v) => v
    _ => fail("expected bool: \{label}")
  }
}

///|
fn lu_expect_i64(value : @types.LoroValue, label : String) -> Int64 raise {
  match value {
    @types.LoroValue::I64(v) => v
    _ => fail("expected i64: \{label}")
  }
}

///|
fn lu_expect_f64(value : @types.LoroValue, label : String) -> Double raise {
  match value {
    @types.LoroValue::F64(v) => v
    _ => fail("expected f64: \{label}")
  }
}

///|
fn lu_map_entry(
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
test "export/import loro updates roundtrip" {
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
  let items_id = lu_expect_ok(
    doc1.map_insert_container(root, "items", @types.ContainerType::List),
    "map insert container",
  )
  let items = @container.ListHandler::new(items_id)
  ensure_ok(doc1.list_push(items, @types.LoroValue::I64(1)))
  ensure_ok(doc1.list_push(items, @types.LoroValue::String("two")))
  ensure_ok(doc1.list_push(list, @types.LoroValue::String("a")))
  ensure_ok(doc1.list_push(list, @types.LoroValue::String("b")))
  let nested_id = lu_expect_ok(
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
  ensure_ok(doc1.text_insert(text, 0, "Hello"))
  ensure_ok(doc1.text_mark(text, 0, 5, "bold", @types.LoroValue::Bool(true)))
  ensure_ok(doc1.text_delete(text, 2, 2))
  let root1 = lu_expect_ok(doc1.tree_create(tree, None), "tree create root")
  let root2 = lu_expect_ok(doc1.tree_create(tree, None), "tree create root2")
  let child = lu_expect_ok(
    doc1.tree_create(tree, Some(root1)),
    "tree create child",
  )
  ensure_ok(doc1.tree_move(tree, child, Some(root2)))
  ensure_ok(doc1.tree_delete(tree, root1))
  ensure_ok(doc1.counter_inc(counter, 2))
  ensure_ok(doc1.counter_inc(counter, 3))
  let doc2 = LoroDoc::new()
  let bytes1 = lu_expect_ok(doc1.export_updates(), "export updates")
  ensure_ok(doc2.import_updates(bytes1))
  let root2_map = doc2.get_map("root")
  let list2 = doc2.get_list("list")
  let text2 = doc2.get_text("text")
  ensure_ok(doc2.map_set(root2_map, "peer", @types.LoroValue::String("b")))
  ensure_ok(doc2.list_push(list2, @types.LoroValue::String("x")))
  ensure_ok(doc2.text_insert(text2, 0, "B"))
  let bytes2 = lu_expect_ok(doc2.export_updates(), "export updates 2")
  ensure_ok(doc1.import_updates(bytes2))
  let loro_bytes = lu_expect_ok(
    doc1.export_loro_updates(),
    "export loro updates",
  )
  let doc3 = LoroDoc::new()
  ensure_ok(doc3.import_bytes(loro_bytes))
  let deep = doc3.get_deep_value()
  let root_map = lu_expect_map(deep, "root")
  let root_value = lu_expect_map(
    lu_map_entry(root_map, "root", "root"),
    "root.map",
  )
  let title = lu_map_entry(root_value, "title", "root.map")
  guard lu_expect_string(title, "root.title") == "Loro" else {
    fail("title mismatch")
  }
  let peer = lu_map_entry(root_value, "peer", "root.map")
  guard lu_expect_string(peer, "root.peer") == "b" else {
    fail("peer mismatch")
  }
  let items = lu_expect_list(
    lu_map_entry(root_value, "items", "root.map"),
    "items",
  )
  guard items.length() == 2 else { fail("items length") }
  guard lu_expect_i64(items[0], "items[0]") == 1 else { fail("items[0]") }
  guard lu_expect_string(items[1], "items[1]") == "two" else {
    fail("items[1]")
  }
  let list_value = lu_expect_list(
    lu_map_entry(root_map, "list", "root"),
    "list",
  )
  guard list_value.length() == 3 else { fail("list length") }
  let nested = lu_expect_map(list_value[0], "list[0]")
  let nested_value = lu_map_entry(nested, "nested", "list[0]")
  guard lu_expect_bool(nested_value, "list[0].nested") else {
    fail("nested bool")
  }
  guard lu_expect_string(list_value[1], "list[1]") == "b2" else {
    fail("list[1]")
  }
  guard lu_expect_string(list_value[2], "list[2]") == "x" else {
    fail("list[2]")
  }
  let mlist_value = lu_expect_list(
    lu_map_entry(root_map, "mlist", "root"),
    "mlist",
  )
  guard mlist_value.length() == 1 else { fail("mlist length") }
  guard lu_expect_string(mlist_value[0], "mlist[0]") == "m1x" else {
    fail("mlist[0]")
  }
  let text_value = lu_map_entry(root_map, "text", "root")
  guard lu_expect_string(text_value, "text") == "BHeo" else {
    fail("text mismatch")
  }
  let counter_value = lu_map_entry(root_map, "counter", "root")
  guard lu_expect_f64(counter_value, "counter") == 5.0 else {
    fail("counter mismatch")
  }
  let tree_value = lu_expect_list(
    lu_map_entry(root_map, "tree", "root"),
    "tree",
  )
  guard tree_value.length() == 1 else { fail("tree roots length") }
  let tree_root = lu_expect_map(tree_value[0], "tree[0]")
  let children = lu_expect_list(
    lu_map_entry(tree_root, "children", "tree[0]"),
    "children",
  )
  guard children.length() == 1 else { fail("tree child length") }
}
