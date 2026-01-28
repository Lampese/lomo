///|
fn chars_to_string(chars : Array[Char]) -> String {
  let builder = StringBuilder::new()
  for c in chars {
    builder.write_char(c)
  }
  builder.to_string()
}

///|
fn gen_ascii_string(max_len : Int) -> @quickcheck.Gen[String] {
  let char_gen = @quickcheck.one_of_array([
    'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l',
  ])
  let len_gen = @quickcheck.int_range(1, max_len)
  len_gen.bind(len => char_gen.array_with_size(len).fmap(chars_to_string))
}

///|
test "loro insert simple" {
  let doc = LoroDoc::new()
  doc.set_peer_id(0)
  doc.text_insert(doc.get_text("text"), 0, "hello").unwrap()
  doc.text_insert(doc.get_text("text"), 1, "hx").unwrap()
  inspect(
    doc.get_deep_value(),
    content=(
      #|Map({"text": String("hhxello")})
    ),
  )
  let doc2 = LoroDoc::new()
  doc2.set_peer_id(1)
  doc2.text_insert(doc2.get_text("text"), 0, "world").unwrap()
  doc.import_updates(doc2.export_updates().unwrap()).unwrap()
  doc2.import_updates(doc.export_updates().unwrap()).unwrap()
  inspect(
    doc.get_deep_value(),
    content=(
      #|Map({"text": String("hworldhxello")})
    ),
  )
  inspect(
    doc2.get_deep_value(),
    content=(
      #|Map({"text": String("hworldhxello")})
    ),
  )
}

///|
fn @types.LoroValue::get_length(
  self : @types.LoroValue,
  txt : String,
) -> Int raise {
  match self {
    Map(root) =>
      match root.get(txt) {
        Some(@types.LoroValue::String(s)) => s.length()
        _ => fail("missing \{txt} \{root}")
      }
    _ => fail("not a map")
  }
}

///|
test "loro random long inserts converge" {
  let string_gen = gen_ascii_string(24)
  // deterministic pseudo-random payloads and indices
  let strings_a = string_gen.samples(size=32, seed=1234)
  let strings_b = string_gen.samples(size=32, seed=5678)
  let pos_gen = @quickcheck.int_bound(4096)
  let positions_a = pos_gen.samples(size=strings_a.length(), seed=42)
  let positions_b = pos_gen.samples(size=strings_b.length(), seed=1337)
  let doc_a = LoroDoc::new()
  doc_a.set_peer_id(0)
  let text_a = doc_a.get_text("text")
  doc_a.text_insert(text_a, 0, "1").unwrap()
  let doc_b = LoroDoc::new()
  doc_b.set_peer_id(1)
  doc_b.text_insert(text_a, 0, "1").unwrap()
  let text_b = doc_b.get_text("text")
  let text_len = (docX : LoroDoc) => docX.get_deep_value().get_length("text")
  let apply_sequence = (
    doc : LoroDoc,
    text : @container.TextHandler,
    parts : Array[String],
    seeds : Array[Int],
  ) => {
    guard parts.length() == seeds.length() else { fail("seed length mismatch") }
    for i in 0..<parts.length() {
      let len = text_len(doc)
      let pos = seeds[i] % (len + 1)
      println("Inserting '\{parts[i]}' at position \{pos} (text length \{len})")
      doc.text_insert(text, pos, parts[i]).unwrap_or_error()
    }
  }
  apply_sequence(doc_a, text_a, strings_a, positions_a)
  apply_sequence(doc_b, text_b, strings_b, positions_b)
  let updates_a = doc_a.export_updates().unwrap_or_error()
  let updates_b = doc_b.export_updates().unwrap_or_error()
  doc_a.import_updates(updates_b).unwrap_or_error()
  doc_b.import_updates(updates_a).unwrap_or_error()
  let deep_a = doc_a.get_deep_value()
  let deep_b = doc_b.get_deep_value()
  let r = match (deep_a, deep_b) {
    (Map(r1), Map(r2)) if r1.get("text") is Some(String(s1)) &&
      r2.get("text") is Some(String(s2)) => s1 == s2
    _ => false
  }
  assert_true(r)
}
