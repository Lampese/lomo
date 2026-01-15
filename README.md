# Lomo

Lomo is a native MoonBit port of the Loro CRDT engine. It focuses on core containers and deterministic merges while keeping the API doc-centric and easy to embed in your own sync pipeline.

## What You Get

- CRDT containers: Map/List/Text/MovableList/Tree
- Transaction batching
- Binary export/import (custom format, not Rust-compatible)
- Undo/redo with grouping and origin filters
- Event subscriptions (root/container/local update/peer change)
- Presence/awareness store (ephemeral updates)

## Status

This is a usable core subset of Loro. It is production-suitable for basic collaboration workflows where you control the sync layer. Advanced APIs from the Rust project (jsonpath, cursor APIs, kv-store integration, etc.) are not implemented yet.

## Example: Local Edits + Sync + Undo

```mbt nocheck
let doc1 = LoroDoc::new()
let doc2 = LoroDoc::new()

let list1 = doc1.get_list("list")
let text1 = doc1.get_text("text")

let list2 = doc2.get_list("list")
let text2 = doc2.get_text("text")

let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
  Ok(_) => ()
  Err(err) => fail("\{err}")
}

// Local edits
ensure_ok(doc1.list_push(list1, @types.LoroValue::I64(1)))
ensure_ok(doc1.text_insert(text1, 0, "hello"))
ensure_ok(doc2.list_push(list2, @types.LoroValue::I64(2)))
ensure_ok(doc2.text_insert(text2, 0, "world"))

// Sync: export updates and import into the other doc
let bytes1 = match doc1.export_updates() { Ok(b) => b Err(e) => fail("\{e}") }
let bytes2 = match doc2.export_updates() { Ok(b) => b Err(e) => fail("\{e}") }
ensure_ok(doc1.import_updates(bytes2))
ensure_ok(doc2.import_updates(bytes1))

// Both docs converge to the same state
let s1 = match doc1.text_to_string(text1) { Ok(v) => v Err(e) => fail("\{e}") }
let s2 = match doc2.text_to_string(text2) { Ok(v) => v Err(e) => fail("\{e}") }
guard s1 == s2 else { fail("text did not converge") }

// Undo/redo (local only)
let undo = UndoManager::new(doc1)
guard undo.can_undo() else { fail("expected undo") }
ignore(undo.undo())
```

## Tests

- Tests live in `lomo/lomo_test.mbt`.
- Run: `moon test`
