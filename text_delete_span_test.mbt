///|
test "text delete spans across gaps" {
  let doc = LoroDoc::new()
  doc.set_peer_id(1)
  let text = doc.get_text("text")
  let ensure_ok = (res : Result[Unit, @types.LoroError]) => match res {
    Ok(_) => ()
    Err(err) => fail("\{err}")
  }
  ensure_ok(doc.text_insert(text, 0, "ABCDEFG"))
  ensure_ok(doc.text_delete(text, 2, 2))
  let value = match doc.text_to_string(text) {
    Ok(v) => v
    Err(err) => fail("\{err}")
  }
  guard value == "ABEFG" else { fail("unexpected text after delete") }
  ensure_ok(doc.text_delete(text, 0, value.length()))
  let value2 = match doc.text_to_string(text) {
    Ok(v) => v
    Err(err) => fail("\{err}")
  }
  guard value2 == "" else { fail("expected empty text") }
}
