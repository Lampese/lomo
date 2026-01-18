///|
test "basic list/map/text edits" {
  let doc = LoroDoc::new()
  let list = doc.get_list("list")
  let map = doc.get_map("map")
  let text = doc.get_text("text")
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  ensure_ok(doc.list_push(list, @types.LoroValue::I64(1)))
  ensure_ok(doc.list_push(list, @types.LoroValue::String("a")))
  ensure_ok(doc.map_set(map, "k", @types.LoroValue::Bool(true)))
  ensure_ok(doc.text_insert(text, 0, "hi"))
  let value = doc.get_deep_value()
  match value {
    @types.LoroValue::Map(root) => {
      match root.get("text") {
        Some(@types.LoroValue::String(s)) => assert_eq(s, "hi")
        _ => fail("missing text")
      }
      match root.get("map") {
        Some(@types.LoroValue::Map(m)) =>
          match m.get("k") {
            Some(@types.LoroValue::Bool(true)) => ()
            _ => fail("missing map entry")
          }
        _ => fail("missing map container")
      }
      match root.get("list") {
        Some(@types.LoroValue::List(items)) => {
          guard items.length() == 2 else { fail("list length") }
        }
        _ => fail("missing list container")
      }
    }
    _ => fail("expected root map")
  }
}

///|
test "export/import updates" {
  let doc1 = LoroDoc::new()
  let list = doc1.get_list("list")
  let map = doc1.get_map("map")
  let text = doc1.get_text("text")
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  ensure_ok(doc1.list_push(list, @types.LoroValue::I64(42)))
  ensure_ok(doc1.map_set(map, "k", @types.LoroValue::String("v")))
  ensure_ok(doc1.text_insert(text, 0, "sync"))
  let bytes = match doc1.export_updates() {
    Ok(b) => b
    Err(err) => fail("export failed: \{err}")
  }
  let doc2 = LoroDoc::new()
  match doc2.import_updates(bytes) {
    Ok(_) => ()
    Err(err) => fail("import failed: \{err}")
  }
  let value = doc2.get_deep_value()
  match value {
    @types.LoroValue::Map(root) => {
      match root.get("text") {
        Some(@types.LoroValue::String(s)) => assert_eq(s, "sync")
        _ => fail("missing text")
      }
      match root.get("map") {
        Some(@types.LoroValue::Map(m)) =>
          match m.get("k") {
            Some(@types.LoroValue::String("v")) => ()
            _ => fail("missing map entry")
          }
        _ => fail("missing map container")
      }
      match root.get("list") {
        Some(@types.LoroValue::List(items)) => {
          guard items.length() == 1 else { fail("list length") }
        }
        _ => fail("missing list container")
      }
    }
    _ => fail("expected root map")
  }
}

///|
test "transaction batches ops" {
  let doc = LoroDoc::new()
  let list = doc.get_list("list")
  let map = doc.get_map("map")
  let text = doc.get_text("text")
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  ensure_ok(doc.begin_transaction())
  ensure_ok(doc.list_push(list, @types.LoroValue::I64(1)))
  ensure_ok(doc.map_set(map, "k", @types.LoroValue::String("v")))
  ensure_ok(doc.text_insert(text, 0, "hi"))
  ensure_ok(doc.commit_transaction())
  let bytes = match doc.export_updates() {
    Ok(b) => b
    Err(err) => fail("export failed: \{err}")
  }
  let decoded = match @encoding.decode_changes(bytes) {
    Ok(changes) => changes
    Err(err) => fail("decode failed: \{err}")
  }
  guard decoded.length() == 1 else { fail("expected one change") }
  guard decoded[0].ops.length() == 3 else { fail("expected three ops") }
}

///|
test "commit meta encode decode" {
  let doc = LoroDoc::new()
  let list = doc.get_list("list")
  let _sub = doc.subscribe_pre_commit(meta => {
    if meta.message() is None {
      meta.set_message(Some("auto"))
    }
    meta.set_origin(Some("sys/commit"))
    true
  })
  doc.set_next_commit_message(Some("explicit"))
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  ensure_ok(doc.list_push(list, @types.LoroValue::I64(1)))
  let bytes = match doc.export_updates() {
    Ok(b) => b
    Err(err) => fail("export failed: \{err}")
  }
  let decoded = match @encoding.decode_changes(bytes) {
    Ok(changes) => changes
    Err(err) => fail("decode failed: \{err}")
  }
  guard decoded.length() == 1 else { fail("expected one change") }
  guard decoded[0].commit_msg == Some("explicit") else {
    fail("commit msg mismatch")
  }
  guard decoded[0].origin == Some("sys/commit") else { fail("origin mismatch") }
}

///|
test "undo excludes origin prefix" {
  let doc = LoroDoc::new()
  let undo = UndoManager::new(doc)
  undo.add_exclude_origin_prefix("sys/")
  let list = doc.get_list("list")
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  doc.set_next_commit_origin(Some("sys/auto"))
  ensure_ok(doc.list_push(list, @types.LoroValue::I64(1)))
  guard !undo.can_undo() else { fail("unexpected undo for sys origin") }
  doc.set_next_commit_origin(Some("user"))
  ensure_ok(doc.list_push(list, @types.LoroValue::I64(2)))
  guard undo.can_undo() else { fail("expected undo for user change") }
  match undo.undo() {
    Ok(true) => ()
    Ok(false) => fail("undo returned false")
    Err(err) => fail("\{err}")
  }
  let value = doc.get_deep_value()
  match value {
    @types.LoroValue::Map(root) =>
      match root.get("list") {
        Some(@types.LoroValue::List(items)) => {
          guard items.length() == 1 else { fail("list length after undo") }
        }
        _ => fail("missing list container")
      }
    _ => fail("expected root map")
  }
}

///|
test "subscribe root events" {
  let doc = LoroDoc::new()
  let list = doc.get_list("list")
  let events : Array[EventBatch] = []
  let _sub = doc.subscribe_root(batch => {
    events.push(batch)
    true
  })
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  ensure_ok(doc.list_push(list, @types.LoroValue::I64(1)))
  guard events.length() == 1 else { fail("expected one event batch") }
  guard events[0].events().length() > 0 else { fail("missing events") }
}

///|
test "ephemeral store encode apply" {
  let store1 = EphemeralStore::new(1000)
  store1.set("cursor", @types.LoroValue::I64(1))
  let bytes = store1.encode("cursor")
  let store2 = EphemeralStore::new(1000)
  match store2.apply(bytes) {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  match store2.get("cursor") {
    Some(@types.LoroValue::I64(1)) => ()
    _ => fail("missing cursor state")
  }
}

///|
test "undo redo list" {
  let doc = LoroDoc::new()
  let undo = UndoManager::new(doc)
  let list = doc.get_list("list")
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  ensure_ok(doc.list_push(list, @types.LoroValue::I64(1)))
  ensure_ok(doc.list_push(list, @types.LoroValue::I64(2)))
  guard undo.can_undo() else { fail("expected undo") }
  match undo.undo() {
    Ok(true) => ()
    Ok(false) => fail("undo returned false")
    Err(err) => fail("\{err}")
  }
  let value = doc.get_deep_value()
  match value {
    @types.LoroValue::Map(root) =>
      match root.get("list") {
        Some(@types.LoroValue::List(items)) => {
          guard items.length() == 1 else { fail("list length after undo") }
        }
        _ => fail("missing list container")
      }
    _ => fail("expected root map")
  }
  match undo.redo() {
    Ok(true) => ()
    Ok(false) => fail("redo returned false")
    Err(err) => fail("\{err}")
  }
  let value2 = doc.get_deep_value()
  match value2 {
    @types.LoroValue::Map(root) =>
      match root.get("list") {
        Some(@types.LoroValue::List(items)) => {
          guard items.length() == 2 else { fail("list length after redo") }
        }
        _ => fail("missing list container")
      }
    _ => fail("expected root map")
  }
}

///|
test "import bytes accepts updates" {
  let doc1 = LoroDoc::new()
  let text = doc1.get_text("text")
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  ensure_ok(doc1.text_insert(text, 0, "bytes"))
  let bytes = match doc1.export_updates() {
    Ok(b) => b
    Err(err) => fail("export failed: \{err}")
  }
  let doc2 = LoroDoc::new()
  ensure_ok(doc2.import_bytes(bytes))
  let value = doc2.get_deep_value()
  match value {
    @types.LoroValue::Map(root) =>
      match root.get("text") {
        Some(@types.LoroValue::String(s)) => assert_eq(s, "bytes")
        _ => fail("missing text")
      }
    _ => fail("expected root map")
  }
}

///|
test "export/import snapshot alias" {
  let doc1 = LoroDoc::new()
  let text = doc1.get_text("text")
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  ensure_ok(doc1.text_insert(text, 0, "snap"))
  let bytes = match doc1.export_bytes(@types.ExportMode::Snapshot) {
    Ok(b) => b
    Err(err) => fail("export failed: \{err}")
  }
  let doc2 = LoroDoc::new()
  match doc2.import_updates(bytes) {
    Ok(_) => fail("expected snapshot import error")
    Err(_) => ()
  }
  ensure_ok(doc2.import_bytes(bytes))
  let value = doc2.get_deep_value()
  match value {
    @types.LoroValue::Map(root) =>
      match root.get("text") {
        Some(@types.LoroValue::String(s)) => assert_eq(s, "snap")
        _ => fail("missing text")
      }
    _ => fail("expected root map")
  }
}

///|
test "snapshot preserves updates-from history" {
  let doc1 = LoroDoc::new()
  let list = doc1.get_list("list")
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  ensure_ok(doc1.list_push(list, @types.LoroValue::I64(1)))
  ensure_ok(doc1.list_push(list, @types.LoroValue::I64(2)))
  let snapshot = match doc1.export_bytes(@types.ExportMode::Snapshot) {
    Ok(b) => b
    Err(err) => fail("export failed: \{err}")
  }
  let doc2 = LoroDoc::new()
  ensure_ok(doc2.import_bytes(snapshot))
  let vv = doc2.version()
  ensure_ok(doc1.list_push(list, @types.LoroValue::I64(3)))
  let delta = match doc1.export_updates_from(Some(vv)) {
    Ok(b) => b
    Err(err) => fail("export failed: \{err}")
  }
  ensure_ok(doc2.import_updates(delta))
  let value = doc2.get_deep_value()
  match value {
    @types.LoroValue::Map(root) =>
      match root.get("list") {
        Some(@types.LoroValue::List(items)) => {
          guard items.length() == 3 else { fail("list length") }
          match (items[0], items[1], items[2]) {
            (
              @types.LoroValue::I64(1),
              @types.LoroValue::I64(2),
              @types.LoroValue::I64(3),
            ) => ()
            _ => fail("unexpected list contents")
          }
        }
        _ => fail("missing list container")
      }
    _ => fail("expected root map")
  }
}

///|
test "export updates from version" {
  let doc1 = LoroDoc::new()
  let list = doc1.get_list("list")
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  ensure_ok(doc1.list_push(list, @types.LoroValue::I64(1)))
  let doc2 = LoroDoc::new()
  let initial = match doc1.export_updates() {
    Ok(b) => b
    Err(err) => fail("export failed: \{err}")
  }
  ensure_ok(doc2.import_updates(initial))
  let vv = doc2.version()
  ensure_ok(doc1.list_push(list, @types.LoroValue::I64(2)))
  let delta = match doc1.export_updates_from(Some(vv)) {
    Ok(b) => b
    Err(err) => fail("export failed: \{err}")
  }
  ensure_ok(doc2.import_updates(delta))
  let value = doc2.get_deep_value()
  match value {
    @types.LoroValue::Map(root) =>
      match root.get("list") {
        Some(@types.LoroValue::List(items)) => {
          guard items.length() == 2 else { fail("list length") }
          match (items[0], items[1]) {
            (@types.LoroValue::I64(1), @types.LoroValue::I64(2)) => ()
            _ => fail("unexpected list contents")
          }
        }
        _ => fail("missing list container")
      }
    _ => fail("expected root map")
  }
}

///|
test "checkout at frontiers" {
  let doc = LoroDoc::new()
  let list = doc.get_list("list")
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  ensure_ok(doc.list_push(list, @types.LoroValue::I64(1)))
  let f1 = doc.oplog_frontiers()
  ensure_ok(doc.list_push(list, @types.LoroValue::I64(2)))
  ensure_ok(doc.checkout(f1))
  let value = doc.get_deep_value()
  match value {
    @types.LoroValue::Map(root) =>
      match root.get("list") {
        Some(@types.LoroValue::List(items)) => {
          guard items.length() == 1 else { fail("list length") }
          match items[0] {
            @types.LoroValue::I64(1) => ()
            _ => fail("unexpected list contents")
          }
        }
        _ => fail("missing list container")
      }
    _ => fail("expected root map")
  }
}

///|
test "fork at frontiers" {
  let doc = LoroDoc::new()
  let list = doc.get_list("list")
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  ensure_ok(doc.list_push(list, @types.LoroValue::I64(1)))
  let f1 = doc.oplog_frontiers()
  ensure_ok(doc.list_push(list, @types.LoroValue::I64(2)))
  let forked = match doc.fork_at(f1) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  let value = forked.get_deep_value()
  match value {
    @types.LoroValue::Map(root) =>
      match root.get("list") {
        Some(@types.LoroValue::List(items)) => {
          guard items.length() == 1 else { fail("list length") }
          match items[0] {
            @types.LoroValue::I64(1) => ()
            _ => fail("unexpected list contents")
          }
        }
        _ => fail("missing list container")
      }
    _ => fail("expected root map")
  }
}

///|
test "movable list move and set" {
  let doc = LoroDoc::new()
  let list = doc.get_movable_list("movable")
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  ensure_ok(doc.movable_list_push(list, @types.LoroValue::I64(1)))
  ensure_ok(doc.movable_list_push(list, @types.LoroValue::I64(2)))
  ensure_ok(doc.movable_list_push(list, @types.LoroValue::I64(3)))
  ensure_ok(doc.movable_list_move(list, 0, 2))
  ensure_ok(doc.movable_list_set(list, 1, @types.LoroValue::I64(10)))
  let value = doc.get_deep_value()
  match value {
    @types.LoroValue::Map(root) =>
      match root.get("movable") {
        Some(@types.LoroValue::List(items)) => {
          guard items.length() == 3 else { fail("list length") }
          match (items[0], items[1], items[2]) {
            (
              @types.LoroValue::I64(2),
              @types.LoroValue::I64(10),
              @types.LoroValue::I64(1),
            ) => ()
            _ => fail("unexpected movable list order")
          }
        }
        _ => fail("missing movable list")
      }
    _ => fail("expected root map")
  }
}

///|
test "tree create move delete" {
  let doc = LoroDoc::new()
  let tree = doc.get_tree("tree")
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  let root = match doc.tree_create(tree, None) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  let child = match doc.tree_create(tree, Some(root)) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  let meta = doc.tree_get_meta(child)
  ensure_ok(doc.map_set(meta, "name", @types.LoroValue::String("child")))
  ensure_ok(doc.tree_move(tree, child, None))
  let value = match doc.tree_get_value_with_meta(tree) {
    Ok(v) => v
    Err(err) => fail("\{err}")
  }
  match value {
    @types.LoroValue::List(items) => {
      guard items.length() == 2 else { fail("tree root count") }
      match items[1] {
        @types.LoroValue::Map(node) =>
          match node.get("meta") {
            Some(@types.LoroValue::Map(meta_map)) =>
              match meta_map.get("name") {
                Some(@types.LoroValue::String("child")) => ()
                _ => fail("missing meta name")
              }
            _ => fail("missing meta map")
          }
        _ => fail("missing tree node")
      }
    }
    _ => fail("expected tree list")
  }
}

///|
test "text richtext mark/unmark" {
  let doc = LoroDoc::new()
  let text = doc.get_text("rich")
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  ensure_ok(doc.text_insert(text, 0, "Hello world!"))
  ensure_ok(doc.text_mark(text, 0, 5, "bold", @types.LoroValue::Bool(true)))
  let value = match doc.text_get_richtext_value(text) {
    Ok(v) => v
    Err(err) => fail("\{err}")
  }
  match value {
    @types.LoroValue::List(items) => {
      guard items.length() == 2 else { fail("delta length") }
      match items[0] {
        @types.LoroValue::Map(map0) => {
          match map0.get("insert") {
            Some(@types.LoroValue::String("Hello")) => ()
            _ => fail("missing insert")
          }
          match map0.get("attributes") {
            Some(@types.LoroValue::Map(attrs)) =>
              match attrs.get("bold") {
                Some(@types.LoroValue::Bool(true)) => ()
                _ => fail("missing bold attr")
              }
            _ => fail("missing attributes map")
          }
        }
        _ => fail("missing first delta")
      }
      match items[1] {
        @types.LoroValue::Map(map1) => {
          match map1.get("insert") {
            Some(@types.LoroValue::String(" world!")) => ()
            _ => fail("missing insert")
          }
          match map1.get("attributes") {
            None => ()
            _ => fail("unexpected attributes")
          }
        }
        _ => fail("missing second delta")
      }
    }
    _ => fail("expected delta list")
  }
  ensure_ok(doc.text_unmark(text, 3, 5, "bold"))
  let value2 = match doc.text_get_richtext_value(text) {
    Ok(v) => v
    Err(err) => fail("\{err}")
  }
  match value2 {
    @types.LoroValue::List(items) => {
      guard items.length() == 2 else { fail("delta length") }
      match items[0] {
        @types.LoroValue::Map(map0) => {
          match map0.get("insert") {
            Some(@types.LoroValue::String("Hel")) => ()
            _ => fail("missing insert")
          }
          match map0.get("attributes") {
            Some(@types.LoroValue::Map(attrs)) =>
              match attrs.get("bold") {
                Some(@types.LoroValue::Bool(true)) => ()
                _ => fail("missing bold attr")
              }
            _ => fail("missing attributes map")
          }
        }
        _ => fail("missing first delta")
      }
      match items[1] {
        @types.LoroValue::Map(map1) => {
          match map1.get("insert") {
            Some(@types.LoroValue::String("lo world!")) => ()
            _ => fail("missing insert")
          }
          match map1.get("attributes") {
            None => ()
            _ => fail("unexpected attributes")
          }
        }
        _ => fail("missing second delta")
      }
    }
    _ => fail("expected delta list")
  }
}

///|
test "text style expand none" {
  let doc = LoroDoc::new()
  let text = doc.get_text("expand_none")
  let styles = @types.StyleConfigMap::new()
  styles.insert(
    "tag",
    @types.StyleConfig::with_expand(@types.ExpandType::NoExpand),
  )
  doc.config_text_style(styles)
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  ensure_ok(doc.text_insert(text, 0, "ab"))
  ensure_ok(doc.text_mark(text, 1, 2, "tag", @types.LoroValue::Bool(true)))
  ensure_ok(doc.text_insert(text, 2, "X"))
  let value = match doc.text_get_richtext_value(text) {
    Ok(v) => v
    Err(err) => fail("\{err}")
  }
  match value {
    @types.LoroValue::List(items) => {
      guard items.length() == 3 else { fail("delta length") }
      match items[0] {
        @types.LoroValue::Map(map0) =>
          match map0.get("insert") {
            Some(@types.LoroValue::String("a")) => ()
            _ => fail("missing insert")
          }
        _ => fail("missing first delta")
      }
      match items[1] {
        @types.LoroValue::Map(map1) => {
          match map1.get("insert") {
            Some(@types.LoroValue::String("b")) => ()
            _ => fail("missing insert")
          }
          match map1.get("attributes") {
            Some(@types.LoroValue::Map(attrs)) =>
              match attrs.get("tag") {
                Some(@types.LoroValue::Bool(true)) => ()
                _ => fail("missing tag attr")
              }
            _ => fail("missing attributes map")
          }
        }
        _ => fail("missing second delta")
      }
      match items[2] {
        @types.LoroValue::Map(map2) => {
          match map2.get("insert") {
            Some(@types.LoroValue::String("X")) => ()
            _ => fail("missing insert")
          }
          match map2.get("attributes") {
            None => ()
            _ => fail("unexpected attributes")
          }
        }
        _ => fail("missing third delta")
      }
    }
    _ => fail("expected delta list")
  }
}

///|
test "text utf8/utf16 ranges" {
  let doc = LoroDoc::new()
  let text = doc.get_text("utf_ranges")
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  ensure_ok(doc.text_insert(text, 0, "A😀B"))
  // UTF-16: "A"=1, "😀"=2, "B"=1 => emoji is range 1..3.
  ensure_ok(
    doc.text_mark_utf16(text, 1, 2, "bold", @types.LoroValue::Bool(true)),
  )
  // UTF-8: "A"=1, "😀"=4, "B"=1 => emoji is range 1..5.
  ensure_ok(
    doc.text_mark_utf8(text, 1, 4, "italic", @types.LoroValue::Bool(true)),
  )
  let value = match doc.text_get_richtext_value(text) {
    Ok(v) => v
    Err(err) => fail("\{err}")
  }
  match value {
    @types.LoroValue::List(items) => {
      guard items.length() == 3 else { fail("delta length") }
      match items[0] {
        @types.LoroValue::Map(map0) =>
          match map0.get("insert") {
            Some(@types.LoroValue::String("A")) => ()
            _ => fail("missing insert")
          }
        _ => fail("missing first delta")
      }
      match items[1] {
        @types.LoroValue::Map(map1) => {
          match map1.get("insert") {
            Some(@types.LoroValue::String("😀")) => ()
            _ => fail("missing insert")
          }
          match map1.get("attributes") {
            Some(@types.LoroValue::Map(attrs)) => {
              match attrs.get("bold") {
                Some(@types.LoroValue::Bool(true)) => ()
                _ => fail("missing bold attr")
              }
              match attrs.get("italic") {
                Some(@types.LoroValue::Bool(true)) => ()
                _ => fail("missing italic attr")
              }
            }
            _ => fail("missing attributes map")
          }
        }
        _ => fail("missing second delta")
      }
      match items[2] {
        @types.LoroValue::Map(map2) => {
          match map2.get("insert") {
            Some(@types.LoroValue::String("B")) => ()
            _ => fail("missing insert")
          }
          match map2.get("attributes") {
            None => ()
            _ => fail("unexpected attributes")
          }
        }
        _ => fail("missing third delta")
      }
    }
    _ => fail("expected delta list")
  }
  let slice16 = match doc.text_slice_utf16(text, 1, 2) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  assert_eq(slice16, "😀")
  let slice8 = match doc.text_slice_utf8(text, 1, 4) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  assert_eq(slice8, "😀")
  let plain = match doc.text_to_string(text) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  assert_eq(plain, "A😀B")
}

///|
test "text utf8/utf16 invalid offsets" {
  let doc = LoroDoc::new()
  let text = doc.get_text("utf_invalid")
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  ensure_ok(doc.text_insert(text, 0, "A😀B"))
  match doc.text_slice_utf16(text, 2, 1) {
    Ok(_) => fail("expected utf16 slice error")
    Err(_) => ()
  }
  match doc.text_slice_utf8(text, 3, 1) {
    Ok(_) => fail("expected utf8 slice error")
    Err(_) => ()
  }
  match doc.text_insert_utf16(text, 2, "X") {
    Ok(_) => fail("expected utf16 insert error")
    Err(_) => ()
  }
  match doc.text_insert_utf8(text, 3, "X") {
    Ok(_) => fail("expected utf8 insert error")
    Err(_) => ()
  }
  match doc.text_mark_utf16(text, 2, 1, "bold", @types.LoroValue::Bool(true)) {
    Ok(_) => fail("expected utf16 mark error")
    Err(_) => ()
  }
  match doc.text_mark_utf8(text, 3, 1, "bold", @types.LoroValue::Bool(true)) {
    Ok(_) => fail("expected utf8 mark error")
    Err(_) => ()
  }
  match doc.text_delete_utf16(text, 2, 1) {
    Ok(_) => fail("expected utf16 delete error")
    Err(_) => ()
  }
  match doc.text_delete_utf8(text, 3, 1) {
    Ok(_) => fail("expected utf8 delete error")
    Err(_) => ()
  }
}

///|
test "nested container insert" {
  let doc = LoroDoc::new()
  let map = doc.get_map("root_map")
  let list = doc.get_list("root_list")
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  let map_text_id = match
    doc.map_insert_container(map, "text", @types.ContainerType::Text) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  let list_text_id = match
    doc.list_insert_container(list, 0, @types.ContainerType::Text) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  let map_text = doc.container_text(map_text_id)
  let list_text = doc.container_text(list_text_id)
  ensure_ok(doc.text_insert(map_text, 0, "map"))
  ensure_ok(doc.text_insert(list_text, 0, "list"))
  let map_value = match doc.text_to_string(map_text) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  let list_value = match doc.text_to_string(list_text) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  assert_eq(map_value, "map")
  assert_eq(list_value, "list")
}

///|
test "deep value nested containers" {
  let doc = LoroDoc::new()
  let map = doc.get_map("root_map")
  let list = doc.get_list("root_list")
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  let map_text_id = match
    doc.map_get_or_create_container(map, "text", @types.ContainerType::Text) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  let list_text_id = match
    doc.list_push_container(list, @types.ContainerType::Text) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  let map_text = doc.container_text(map_text_id)
  let list_text = doc.container_text(list_text_id)
  ensure_ok(doc.text_insert(map_text, 0, "map"))
  ensure_ok(doc.text_insert(list_text, 0, "list"))
  let value = doc.get_deep_value()
  match value {
    @types.LoroValue::Map(root) => {
      match root.get("root_map") {
        Some(@types.LoroValue::Map(map_val)) =>
          match map_val.get("text") {
            Some(@types.LoroValue::String("map")) => ()
            _ => fail("missing nested map text")
          }
        _ => fail("missing root_map")
      }
      match root.get("root_list") {
        Some(@types.LoroValue::List(items)) => {
          guard items.length() == 1 else { fail("list length") }
          match items[0] {
            @types.LoroValue::String("list") => ()
            _ => fail("missing nested list text")
          }
        }
        _ => fail("missing root_list")
      }
    }
    _ => fail("expected root map")
  }
}

///|
test "list get or create container" {
  let doc = LoroDoc::new()
  let list = doc.get_list("gc_list")
  let first_id = match
    doc.list_get_or_create_container(list, 0, @types.ContainerType::Text) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  let second_id = match
    doc.list_get_or_create_container(list, 0, @types.ContainerType::Text) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  guard first_id == second_id else { fail("expected same container") }
}

///|
test "deep value cycle guard" {
  let doc = LoroDoc::new()
  let map = doc.get_map("cycle_map")
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  let list_id = match
    doc.map_get_or_create_container(map, "list", @types.ContainerType::List) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  let list = doc.container_list(list_id)
  ensure_ok(
    doc.list_insert(list, 0, @types.LoroValue::Container(doc.map_id(map))),
  )
  let value = doc.get_deep_value()
  match value {
    @types.LoroValue::Map(root) =>
      match root.get("cycle_map") {
        Some(@types.LoroValue::Map(map_val)) =>
          match map_val.get("list") {
            Some(@types.LoroValue::List(items)) => {
              guard items.length() == 1 else { fail("list length") }
              match items[0] {
                @types.LoroValue::Null => ()
                _ => fail("expected null for cycle")
              }
            }
            _ => fail("missing list value")
          }
        _ => fail("missing cycle map")
      }
    _ => fail("expected root map")
  }
}

///|
test "tree meta nested containers" {
  let doc = LoroDoc::new()
  let tree = doc.get_tree("tree_meta")
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  let root = match doc.tree_create(tree, None) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  let meta = doc.tree_get_meta(root)
  let list_id = match
    doc.map_get_or_create_container(meta, "items", @types.ContainerType::List) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  let list = doc.container_list(list_id)
  let text_id = match
    doc.list_push_container(list, @types.ContainerType::Text) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  let text = doc.container_text(text_id)
  ensure_ok(doc.text_insert(text, 0, "hi"))
  let value = doc.get_deep_value()
  match value {
    @types.LoroValue::Map(root_val) =>
      match root_val.get("tree_meta") {
        Some(@types.LoroValue::List(items)) => {
          guard items.length() == 1 else { fail("root length") }
          match items[0] {
            @types.LoroValue::Map(node) =>
              match node.get("meta") {
                Some(@types.LoroValue::Map(meta_val)) =>
                  match meta_val.get("items") {
                    Some(@types.LoroValue::List(meta_items)) => {
                      guard meta_items.length() == 1 else {
                        fail("meta list length")
                      }
                      match meta_items[0] {
                        @types.LoroValue::String("hi") => ()
                        _ => fail("missing nested text")
                      }
                    }
                    _ => fail("missing meta list")
                  }
                _ => fail("missing meta map")
              }
            _ => fail("missing tree node")
          }
        }
        _ => fail("missing tree_meta")
      }
    _ => fail("expected root map")
  }
}

///|
test "container type mismatch errors" {
  let doc = LoroDoc::new()
  let map = doc.get_map("type_map")
  let list = doc.get_list("type_list")
  let text_id = match
    doc.map_get_or_create_container(map, "child", @types.ContainerType::Text) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  let _ = text_id
  match
    doc.map_get_or_create_container(map, "child", @types.ContainerType::List) {
    Ok(_) => fail("expected map type mismatch error")
    Err(_) => ()
  }
  let list_text_id = match
    doc.list_get_or_create_container(list, 0, @types.ContainerType::Text) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  let _ = list_text_id
  match doc.list_get_or_create_container(list, 0, @types.ContainerType::Map) {
    Ok(_) => fail("expected list type mismatch error")
    Err(_) => ()
  }
  match doc.list_insert(list, 1, @types.LoroValue::I64(1)) {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  match doc.list_get_or_create_container(list, 1, @types.ContainerType::Text) {
    Ok(_) => fail("expected list non-container error")
    Err(_) => ()
  }
}

///|
test "deep value empty containers" {
  let doc = LoroDoc::new()
  let map = doc.get_map("empty_map")
  let list = doc.get_list("empty_list")
  let text_id = match
    doc.map_insert_container(map, "text", @types.ContainerType::Text) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  let _ = text_id
  let list_id = match
    doc.list_push_container(list, @types.ContainerType::List) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  let _ = list_id
  let value = doc.get_deep_value()
  match value {
    @types.LoroValue::Map(root) => {
      match root.get("empty_map") {
        Some(@types.LoroValue::Map(map_val)) =>
          match map_val.get("text") {
            Some(@types.LoroValue::String("")) => ()
            _ => fail("missing empty text")
          }
        _ => fail("missing empty_map")
      }
      match root.get("empty_list") {
        Some(@types.LoroValue::List(items)) => {
          guard items.length() == 1 else { fail("list length") }
          match items[0] {
            @types.LoroValue::List(inner) => {
              guard inner.length() == 0 else { fail("inner list length") }
            }
            _ => fail("missing empty list")
          }
        }
        _ => fail("missing empty_list")
      }
    }
    _ => fail("expected root map")
  }
}

///|
test "tree delete deep value" {
  let doc = LoroDoc::new()
  let tree = doc.get_tree("tree_delete")
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  let root = match doc.tree_create(tree, None) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  let child = match doc.tree_create(tree, Some(root)) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  ensure_ok(doc.tree_delete(tree, child))
  let value = doc.get_deep_value()
  match value {
    @types.LoroValue::Map(root_val) =>
      match root_val.get("tree_delete") {
        Some(@types.LoroValue::List(items)) => {
          guard items.length() == 1 else { fail("tree length") }
          match items[0] {
            @types.LoroValue::Map(node) =>
              match node.get("children") {
                Some(@types.LoroValue::List(children)) => {
                  guard children.length() == 0 else {
                    fail("expected no children")
                  }
                }
                _ => fail("missing children")
              }
            _ => fail("missing root node")
          }
        }
        _ => fail("missing tree_delete")
      }
    _ => fail("expected root map")
  }
  ensure_ok(doc.tree_delete(tree, root))
  let value2 = doc.get_deep_value()
  match value2 {
    @types.LoroValue::Map(root_val) =>
      match root_val.get("tree_delete") {
        Some(@types.LoroValue::List(items)) => {
          guard items.length() == 0 else { fail("expected empty tree") }
        }
        _ => fail("missing tree_delete")
      }
    _ => fail("expected root map")
  }
}

///|
test "deep value removed containers" {
  let doc = LoroDoc::new()
  let map = doc.get_map("remove_map")
  let list = doc.get_list("remove_list")
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  let map_text_id = match
    doc.map_insert_container(map, "text", @types.ContainerType::Text) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  let map_text = doc.container_text(map_text_id)
  ensure_ok(doc.text_insert(map_text, 0, "gone"))
  ensure_ok(doc.map_delete(map, "text"))
  let list_keep_id = match
    doc.list_push_container(list, @types.ContainerType::Text) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  let list_gone_id = match
    doc.list_push_container(list, @types.ContainerType::Text) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  let list_keep = doc.container_text(list_keep_id)
  let list_gone = doc.container_text(list_gone_id)
  ensure_ok(doc.text_insert(list_keep, 0, "keep"))
  ensure_ok(doc.text_insert(list_gone, 0, "gone"))
  ensure_ok(doc.list_delete(list, 1, 1))
  let value = doc.get_deep_value()
  match value {
    @types.LoroValue::Map(root_val) => {
      match root_val.get("remove_map") {
        Some(@types.LoroValue::Map(map_val)) => {
          guard map_val.length() == 0 else { fail("expected empty map") }
        }
        _ => fail("missing remove_map")
      }
      match root_val.get("remove_list") {
        Some(@types.LoroValue::List(items)) => {
          guard items.length() == 1 else { fail("list length") }
          match items[0] {
            @types.LoroValue::String("keep") => ()
            _ => fail("missing keep")
          }
        }
        _ => fail("missing remove_list")
      }
    }
    _ => fail("expected root map")
  }
}

///|
test "text diff alias" {
  let doc = LoroDoc::new()
  let text = doc.get_text("diff_text")
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  ensure_ok(doc.text_insert(text, 0, "Hello"))
  ensure_ok(doc.text_mark(text, 0, 5, "bold", @types.LoroValue::Bool(true)))
  let diff = match doc.text_diff(text) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  guard diff.length() == 1 else { fail("diff length") }
  match diff[0] {
    @types.LoroValue::Map(item) => {
      match item.get("insert") {
        Some(@types.LoroValue::String("Hello")) => ()
        _ => fail("missing insert")
      }
      match item.get("attributes") {
        Some(@types.LoroValue::Map(attrs)) =>
          match attrs.get("bold") {
            Some(@types.LoroValue::Bool(true)) => ()
            _ => fail("missing bold")
          }
        _ => fail("missing attributes")
      }
    }
    _ => fail("missing diff item")
  }
}

///|
test "map/list diff output" {
  let doc = LoroDoc::new()
  let list = doc.get_list("diff_list")
  let map = doc.get_map("diff_map")
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  ensure_ok(doc.list_push(list, @types.LoroValue::I64(1)))
  ensure_ok(doc.map_set(map, "k", @types.LoroValue::String("v")))
  let list_diff = match doc.list_diff(list) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  guard list_diff.length() == 1 else { fail("list diff length") }
  match list_diff[0] {
    @types.LoroValue::Map(item) =>
      match item.get("insert") {
        Some(@types.LoroValue::List(items)) => {
          guard items.length() == 1 else { fail("list insert length") }
          match items[0] {
            @types.LoroValue::I64(1) => ()
            _ => fail("missing list insert value")
          }
        }
        _ => fail("missing list insert")
      }
    _ => fail("missing list diff item")
  }
  let map_diff = match doc.map_diff(map) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  guard map_diff.length() == 1 else { fail("map diff length") }
  match map_diff[0] {
    @types.LoroValue::Map(item) => {
      match item.get("key") {
        Some(@types.LoroValue::String("k")) => ()
        _ => fail("missing map key")
      }
      match item.get("value") {
        Some(@types.LoroValue::String("v")) => ()
        _ => fail("missing map value")
      }
    }
    _ => fail("missing map diff item")
  }
}

///|
test "map/list diff nested containers" {
  let doc = LoroDoc::new()
  let map = doc.get_map("diff_map_nested")
  let list = doc.get_list("diff_list_nested")
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  let map_text_id = match
    doc.map_get_or_create_container(map, "text", @types.ContainerType::Text) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  let map_text = doc.container_text(map_text_id)
  ensure_ok(doc.text_insert(map_text, 0, "hi"))
  let map_list_id = match
    doc.map_get_or_create_container(map, "list", @types.ContainerType::List) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  let map_list = doc.container_list(map_list_id)
  let inner_text_id = match
    doc.list_push_container(map_list, @types.ContainerType::Text) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  let inner_text = doc.container_text(inner_text_id)
  ensure_ok(doc.text_insert(inner_text, 0, "lo"))
  let list_text_id = match
    doc.list_push_container(list, @types.ContainerType::Text) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  let list_text = doc.container_text(list_text_id)
  ensure_ok(doc.text_insert(list_text, 0, "one"))
  let list_map_id = match
    doc.list_push_container(list, @types.ContainerType::Map) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  let list_map = doc.container_map(list_map_id)
  ensure_ok(doc.map_set(list_map, "k", @types.LoroValue::String("v")))
  let map_diff = match doc.map_diff(map) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  let mut saw_text = false
  let mut saw_list = false
  for item in map_diff {
    match item {
      @types.LoroValue::Map(entry) =>
        match entry.get("key") {
          Some(@types.LoroValue::String("text")) =>
            match entry.get("value") {
              Some(@types.LoroValue::String("hi")) => saw_text = true
              _ => ()
            }
          Some(@types.LoroValue::String("list")) =>
            match entry.get("value") {
              Some(@types.LoroValue::List(items)) =>
                if items.length() == 1 &&
                  items[0] is @types.LoroValue::String("lo") {
                  saw_list = true
                }
              _ => ()
            }
          _ => ()
        }
      _ => ()
    }
  }
  guard saw_text && saw_list else { fail("missing nested map diff") }
  let list_diff = match doc.list_diff(list) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  guard list_diff.length() == 1 else { fail("list diff length") }
  match list_diff[0] {
    @types.LoroValue::Map(item) =>
      match item.get("insert") {
        Some(@types.LoroValue::List(items)) => {
          guard items.length() == 2 else { fail("list insert length") }
          match items[0] {
            @types.LoroValue::String("one") => ()
            _ => fail("missing list text")
          }
          match items[1] {
            @types.LoroValue::Map(map_val) =>
              match map_val.get("k") {
                Some(@types.LoroValue::String("v")) => ()
                _ => fail("missing nested map value")
              }
            _ => fail("missing nested map")
          }
        }
        _ => fail("missing list insert")
      }
    _ => fail("missing list diff item")
  }
}

///|
test "movable list diff order" {
  let doc = LoroDoc::new()
  let list = doc.get_movable_list("diff_movable")
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  ensure_ok(doc.movable_list_push(list, @types.LoroValue::I64(1)))
  ensure_ok(doc.movable_list_push(list, @types.LoroValue::I64(2)))
  ensure_ok(doc.movable_list_push(list, @types.LoroValue::I64(3)))
  ensure_ok(doc.movable_list_move(list, 0, 2))
  let diff = match doc.movable_list_diff(list) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  guard diff.length() == 1 else { fail("diff length") }
  match diff[0] {
    @types.LoroValue::Map(item) =>
      match item.get("insert") {
        Some(@types.LoroValue::List(items)) =>
          match (items[0], items[1], items[2]) {
            (
              @types.LoroValue::I64(2),
              @types.LoroValue::I64(3),
              @types.LoroValue::I64(1),
            ) => ()
            _ => fail("unexpected movable list order")
          }
        _ => fail("missing insert")
      }
    _ => fail("missing diff item")
  }
}

///|
test "concurrent map/list merge" {
  let doc1 = LoroDoc::new()
  let doc2 = LoroDoc::new()
  doc1.set_peer_id(1)
  doc2.set_peer_id(2)
  let map1 = doc1.get_map("map")
  let list1 = doc1.get_list("list")
  let map2 = doc2.get_map("map")
  let list2 = doc2.get_list("list")
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  ensure_ok(doc1.map_set(map1, "k", @types.LoroValue::String("a")))
  ensure_ok(doc2.map_set(map2, "k", @types.LoroValue::String("b")))
  ensure_ok(doc1.list_push(list1, @types.LoroValue::I64(1)))
  ensure_ok(doc2.list_push(list2, @types.LoroValue::I64(2)))
  let bytes1 = match doc1.export_updates() {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  let bytes2 = match doc2.export_updates() {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  ensure_ok(doc1.import_updates(bytes2))
  ensure_ok(doc2.import_updates(bytes1))
  let value = doc1.get_deep_value()
  match value {
    @types.LoroValue::Map(root) => {
      match root.get("map") {
        Some(@types.LoroValue::Map(map_val)) =>
          match map_val.get("k") {
            Some(@types.LoroValue::String("b")) => ()
            _ => fail("expected peer 2 to win")
          }
        _ => fail("missing map")
      }
      match root.get("list") {
        Some(@types.LoroValue::List(items)) => {
          guard items.length() == 2 else { fail("list length") }
          let mut has1 = false
          let mut has2 = false
          for item in items {
            match item {
              @types.LoroValue::I64(1) => has1 = true
              @types.LoroValue::I64(2) => has2 = true
              _ => ()
            }
          }
          guard has1 && has2 else { fail("missing list values") }
        }
        _ => fail("missing list")
      }
    }
    _ => fail("expected root map")
  }
}

///|
test "concurrent text insert merge" {
  let doc1 = LoroDoc::new()
  let doc2 = LoroDoc::new()
  doc1.set_peer_id(1)
  doc2.set_peer_id(2)
  let text1 = doc1.get_text("text")
  let text2 = doc2.get_text("text")
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  ensure_ok(doc1.text_insert(text1, 0, "A"))
  ensure_ok(doc2.text_insert(text2, 0, "B"))
  let bytes1 = match doc1.export_updates() {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  let bytes2 = match doc2.export_updates() {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  ensure_ok(doc1.import_updates(bytes2))
  ensure_ok(doc2.import_updates(bytes1))
  let value = match doc1.text_to_string(text1) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  guard value == "AB" || value == "BA" else { fail("unexpected text merge") }
}

///|
test "concurrent text insert/delete merge" {
  let doc1 = LoroDoc::new()
  let doc2 = LoroDoc::new()
  doc1.set_peer_id(1)
  doc2.set_peer_id(2)
  let text1 = doc1.get_text("text")
  let text2 = doc2.get_text("text")
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  ensure_ok(doc1.text_insert(text1, 0, "ABC"))
  let bytes1 = match doc1.export_updates() {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  ensure_ok(doc2.import_updates(bytes1))
  ensure_ok(doc1.text_insert(text1, 1, "X"))
  ensure_ok(doc2.text_delete(text2, 1, 1))
  let bytes1b = match doc1.export_updates() {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  let bytes2 = match doc2.export_updates() {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  ensure_ok(doc1.import_updates(bytes2))
  ensure_ok(doc2.import_updates(bytes1b))
  let value1 = match doc1.text_to_string(text1) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  let value2 = match doc2.text_to_string(text2) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  guard value1 == value2 else { fail("text divergence") }
}

///|
test "concurrent text delete merge" {
  let doc1 = LoroDoc::new()
  let doc2 = LoroDoc::new()
  doc1.set_peer_id(1)
  doc2.set_peer_id(2)
  let text1 = doc1.get_text("text")
  let text2 = doc2.get_text("text")
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  ensure_ok(doc1.text_insert(text1, 0, "ABCD"))
  let bytes1 = match doc1.export_updates() {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  ensure_ok(doc2.import_updates(bytes1))
  ensure_ok(doc1.text_delete(text1, 1, 1)) // delete B
  ensure_ok(doc2.text_delete(text2, 2, 1)) // delete C
  let bytes1b = match doc1.export_updates() {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  let bytes2 = match doc2.export_updates() {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  ensure_ok(doc1.import_updates(bytes2))
  ensure_ok(doc2.import_updates(bytes1b))
  let value1 = match doc1.text_to_string(text1) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  let value2 = match doc2.text_to_string(text2) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  guard value1 == "AD" && value2 == "AD" else {
    fail("unexpected delete merge")
  }
}

///|
test "counter increments" {
  let doc = LoroDoc::new()
  let counter = doc.get_counter("count")
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  ensure_ok(doc.counter_add(counter, 1.5))
  ensure_ok(doc.counter_inc(counter, 2))
  let value = match doc.counter_value(counter) {
    Ok(v) => v
    Err(err) => fail("\{err}")
  }
  guard value == 3.5 else { fail("unexpected counter value") }
}
