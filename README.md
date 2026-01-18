# Lomo

Lomo is a native MoonBit port of the Loro CRDT engine. It preserves Loro's
container semantics and deterministic merge behavior while keeping the core
embeddable: you own networking and storage, Lomo owns merges, update encoding,
undo, and presence primitives.

## Goals

- Loro-compatible containers and merge semantics in pure MoonBit.
- Rust Loro FastUpdates/FastSnapshot binary compatibility (in progress).
- Deterministic convergence with version-vector based sync.
- Explicit APIs that fit server-side or embedded use.
- Minimal dependencies and stable naming aligned with Loro.

## Non-goals (for now)

- Legacy Loro encodings (OutdatedRle/OutdatedSnapshot).
- Cursor/jsonpath APIs and storage adapters.
- Built-in networking or persistence.

## Feature coverage (0.0.1)

- Containers: Map, List, Text, MovableList, Tree, Counter (including nested containers).
- Text: UTF-8/UTF-16 insert/delete/mark/unmark, deltas, diffs.
- Transactions and commit metadata (message + origin).
- Export/import: updates, snapshots, version vectors, frontiers.
- Undo/redo with grouping and origin-prefix filters.
- Subscriptions: root/container/local update/peer id/pre-commit hooks.
- Ephemeral presence store with encode/apply.

## Sync model

- Each document maintains a version vector (`doc.version()`).
- Use `export_updates_from(Some(vv))` for incremental sync.
- Use `export_bytes(@types.ExportMode::Snapshot)` to ship full state.
- Apply with `import_updates` or `import_bytes`.

## Example: Local edits, merge, snapshot, undo

```mbt
let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
  Ok(_) => ()
  Err(err) => fail("\{err}")
}

let doc1 = LoroDoc::new()
let doc2 = LoroDoc::new()
doc1.set_peer_id(1)
doc2.set_peer_id(2)

let list1 = doc1.get_list("todos")
let map1 = doc1.get_map("profile")
let text1 = doc1.get_text("note")

doc1.set_next_commit_origin(Some("client:alpha"))
doc1.set_next_commit_message(Some("seed profile"))
ensure_ok(doc1.begin_transaction())
ensure_ok(doc1.map_set(map1, "name", @types.LoroValue::String("Ada")))
ensure_ok(doc1.map_set(map1, "role", @types.LoroValue::String("writer")))
ensure_ok(doc1.list_push(list1, @types.LoroValue::String("draft")))
ensure_ok(doc1.text_insert(text1, 0, "Hello Lomo"))
ensure_ok(doc1.commit_transaction())

let list2 = doc2.get_list("todos")
let text2 = doc2.get_text("note")
ensure_ok(doc2.list_push(list2, @types.LoroValue::String("review")))
ensure_ok(doc2.text_insert(text2, 0, "Hey! "))

let bytes1 = match doc1.export_updates() { Ok(b) => b Err(e) => fail("\{e}") }
let bytes2 = match doc2.export_updates() { Ok(b) => b Err(e) => fail("\{e}") }
ensure_ok(doc1.import_updates(bytes2))
ensure_ok(doc2.import_updates(bytes1))

let merged1 = match doc1.text_to_string(text1) { Ok(v) => v Err(e) => fail("\{e}") }
let merged2 = match doc2.text_to_string(text2) { Ok(v) => v Err(e) => fail("\{e}") }
guard merged1 == merged2 else { fail("text did not converge") }

let snapshot = match doc1.export_bytes(@types.ExportMode::Snapshot) {
  Ok(b) => b
  Err(e) => fail("\{e}")
}
let doc3 = LoroDoc::new()
ensure_ok(doc3.import_bytes(snapshot))

let undo = UndoManager::new(doc1)
undo.add_exclude_origin_prefix("remote:")
ignore(undo.undo())
```

## Example: Presence (EphemeralStore)

```mbt
let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
  Ok(_) => ()
  Err(err) => fail("\{err}")
}

let presence1 = EphemeralStore::new(15_000)
let presence2 = EphemeralStore::new(15_000)

presence1.set(
  "user:alpha",
  @types.LoroValue::Map({ "cursor": @types.LoroValue::I64(12) }),
)

let payload = presence1.encode_all()
ensure_ok(presence2.apply(payload))
```

## Example: Tree structure and metadata

```mbt
let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
  Ok(_) => ()
  Err(err) => fail("\{err}")
}

let doc = LoroDoc::new()
let tree = doc.get_tree("outline")

let root = match doc.tree_create(tree, None) {
  Ok(id) => id
  Err(e) => fail("\{e}")
}
let a = match doc.tree_create(tree, Some(root)) {
  Ok(id) => id
  Err(e) => fail("\{e}")
}
let b = match doc.tree_create(tree, Some(root)) {
  Ok(id) => id
  Err(e) => fail("\{e}")
}

// Attach metadata to a node via its meta map container.
let root_meta = doc.tree_get_meta(root)
ensure_ok(doc.map_set(root_meta, "title", @types.LoroValue::String("Chapter 1")))

// Reorder: move b before a under the same parent.
ensure_ok(doc.tree_move_before(tree, b, a))

let tree_value = match doc.tree_get_value_with_meta(tree) {
  Ok(v) => v
  Err(e) => fail("\{e}")
}
ignore(tree_value)
```

## Example: RichText marks and deltas

```mbt
let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
  Ok(_) => ()
  Err(err) => fail("\{err}")
}

let doc = LoroDoc::new()
let text = doc.get_text("body")

ensure_ok(doc.text_insert(text, 0, "Hello rich text"))
ensure_ok(
  doc.text_mark(
    text,
    0,
    5,
    "bold",
    @types.LoroValue::Bool(true),
  ),
)

let delta = match doc.text_to_delta(text) {
  Ok(v) => v
  Err(e) => fail("\{e}")
}
ignore(delta)
```

## Example: Nested containers

```mbt
let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
  Ok(_) => ()
  Err(err) => fail("\{err}")
}

let doc = LoroDoc::new()
let root = doc.get_map("root")

let list_id = match doc.map_insert_container(
  root,
  "items",
  @types.ContainerType::List,
) {
  Ok(id) => id
  Err(e) => fail("\{e}")
}
let items = @container.ListHandler::new(list_id)
ensure_ok(doc.list_push(items, @types.LoroValue::String("one")))

let note_id = match doc.list_insert_container(
  items,
  1,
  @types.ContainerType::Text,
) {
  Ok(id) => id
  Err(e) => fail("\{e}")
}
let note = @container.TextHandler::new(note_id)
ensure_ok(doc.text_insert(note, 0, "embedded text"))

let deep = doc.get_deep_value()
ignore(deep)
```

## Tests

- Tests live in `lomo/lomo_test.mbt`.
- Run: `moon test`
