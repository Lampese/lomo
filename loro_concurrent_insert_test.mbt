///|
test "concurrent reverse inserts order like loro" {
  let doc_a = LoroDoc::new()
  doc_a.set_peer_id(1)
  let doc_b = LoroDoc::new()
  doc_b.set_peer_id(2)
  let text_a = doc_a.get_text("text")
  let text_b = doc_b.get_text("text")
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  ensure_ok(doc_a.text_insert(text_a, 0, "7"))
  ensure_ok(doc_a.text_insert(text_a, 0, "6"))
  ensure_ok(doc_a.text_insert(text_a, 0, "5"))
  ensure_ok(doc_b.text_insert(text_b, 0, "4"))
  ensure_ok(doc_b.text_insert(text_b, 0, "3"))
  ensure_ok(doc_b.text_insert(text_b, 0, "2"))
  ensure_ok(doc_b.text_insert(text_b, 0, "1"))
  let updates_a = match doc_a.export_updates() {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  let updates_b = match doc_b.export_updates() {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  ensure_ok(doc_a.import_updates(updates_b))
  ensure_ok(doc_b.import_updates(updates_a))
  let value_a = match doc_a.text_to_string(text_a) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  let value_b = match doc_b.text_to_string(text_b) {
    Ok(value) => value
    Err(err) => fail("\{err}")
  }
  guard value_a == "5671234" else { fail("unexpected merge: \{value_a}") }
  guard value_b == "5671234" else { fail("unexpected merge: \{value_b}") }
}
