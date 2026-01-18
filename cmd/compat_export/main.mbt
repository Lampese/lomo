///|
fn bytes_to_hex(bytes : Bytes) -> String {
  let hex : Array[Char] = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
  ]
  let sb = StringBuilder::new()
  for b in bytes {
    let v = b.to_int()
    let hi = (v >> 4) & 0xF
    let lo = v & 0xF
    sb.write_char(hex[hi])
    sb.write_char(hex[lo])
  }
  sb.to_string()
}

///|
fn[T] expect_ok(res : Result[T, @types.LoroError], label : String) -> T? {
  match res {
    Ok(value) => Some(value)
    Err(err) => {
      println("\{label} failed: \{err}")
      None
    }
  }
}

///|
fn main {
  let doc = @lomo.LoroDoc::new()
  doc.set_peer_id(1UL)
  let root = doc.get_map("root")
  let list = doc.get_list("list")
  let mlist = doc.get_movable_list("mlist")
  let text = doc.get_text("text")
  let tree = doc.get_tree("tree")
  let counter = doc.get_counter("counter")
  let ensure_ok = (res : Result[Unit, @types.LoroError], label : String) => match
    res {
    Ok(_) => true
    Err(err) => {
      println("\{label} failed: \{err}")
      false
    }
  }
  if !ensure_ok(
      doc.map_set(root, "title", @types.LoroValue::String("Loro")),
      "map set title",
    ) {
    return
  }
  let items_id = match
    expect_ok(
      doc.map_insert_container(root, "items", @types.ContainerType::List),
      "map insert items",
    ) {
    Some(value) => value
    None => return
  }
  let items = @container.ListHandler::new(items_id)
  if !ensure_ok(doc.list_push(items, @types.LoroValue::I64(1)), "items push 1") {
    return
  }
  if !ensure_ok(
      doc.list_push(items, @types.LoroValue::String("two")),
      "items push two",
    ) {
    return
  }
  if !ensure_ok(
      doc.list_push(list, @types.LoroValue::String("a")),
      "list push a",
    ) {
    return
  }
  if !ensure_ok(
      doc.list_push(list, @types.LoroValue::String("b")),
      "list push b",
    ) {
    return
  }
  let nested_id = match
    expect_ok(
      doc.list_insert_container(list, 1, @types.ContainerType::Map),
      "list insert container",
    ) {
    Some(value) => value
    None => return
  }
  let nested_map = @container.MapHandler::new(nested_id)
  if !ensure_ok(
      doc.map_set(nested_map, "nested", @types.LoroValue::Bool(true)),
      "nested map set",
    ) {
    return
  }
  if !ensure_ok(
      doc.list_set(list, 2, @types.LoroValue::String("b2")),
      "list set b2",
    ) {
    return
  }
  if !ensure_ok(doc.list_delete(list, 0, 1), "list delete") {
    return
  }
  if !ensure_ok(
      doc.movable_list_push(mlist, @types.LoroValue::String("m1")),
      "mlist push m1",
    ) {
    return
  }
  if !ensure_ok(
      doc.movable_list_push(mlist, @types.LoroValue::String("m2")),
      "mlist push m2",
    ) {
    return
  }
  if !ensure_ok(doc.movable_list_move(mlist, 0, 1), "mlist move") {
    return
  }
  if !ensure_ok(
      doc.movable_list_set(mlist, 1, @types.LoroValue::String("m1x")),
      "mlist set",
    ) {
    return
  }
  if !ensure_ok(doc.movable_list_delete(mlist, 0, 1), "mlist delete") {
    return
  }
  if !ensure_ok(doc.text_insert(text, 0, "Hello world"), "text insert") {
    return
  }
  if !ensure_ok(
      doc.text_mark(text, 0, 5, "bold", @types.LoroValue::Bool(true)),
      "text mark",
    ) {
    return
  }
  if !ensure_ok(doc.text_delete(text, 5, 1), "text delete") {
    return
  }
  let root1 = match expect_ok(doc.tree_create(tree, None), "tree create root") {
    Some(value) => value
    None => return
  }
  let root2 = match
    expect_ok(doc.tree_create(tree, None), "tree create root2") {
    Some(value) => value
    None => return
  }
  let child = match
    expect_ok(doc.tree_create(tree, Some(root1)), "tree create child") {
    Some(value) => value
    None => return
  }
  let meta = doc.tree_get_meta(child)
  if !ensure_ok(
      doc.map_set(meta, "name", @types.LoroValue::String("child")),
      "tree meta",
    ) {
    return
  }
  if !ensure_ok(doc.tree_move(tree, child, Some(root2)), "tree move") {
    return
  }
  if !ensure_ok(doc.tree_delete(tree, root1), "tree delete") {
    return
  }
  if !ensure_ok(doc.counter_inc(counter, 2), "counter inc 2") {
    return
  }
  if !ensure_ok(doc.counter_inc(counter, 3), "counter inc 3") {
    return
  }
  let updates = match expect_ok(doc.export_loro_updates(), "export updates") {
    Some(value) => value
    None => return
  }
  let snapshot = match
    expect_ok(doc.export_loro_snapshot(), "export snapshot") {
    Some(value) => value
    None => return
  }
  println("updates \{bytes_to_hex(updates)}")
  println("snapshot \{bytes_to_hex(snapshot)}")
}
