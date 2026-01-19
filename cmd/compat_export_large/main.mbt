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
fn repeat_char(ch : Char, count : Int) -> String {
  let sb = StringBuilder::new()
  for _i = 0; _i < count; _i = _i + 1 {
    sb.write_char(ch)
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
  let doc1 = @lomo.LoroDoc::new()
  doc1.set_peer_id(1UL)
  let root1 = doc1.get_map("root")
  let big1 = repeat_char('a', 1500)
  match
    expect_ok(
      doc1.map_set(root1, "p1", @types.LoroValue::String(big1)),
      "map set p1",
    ) {
    Some(_) => ()
    None => return
  }
  let doc2 = @lomo.LoroDoc::new()
  doc2.set_peer_id(2UL)
  let root2 = doc2.get_map("root")
  let big2 = repeat_char('a', 1500)
  match
    expect_ok(
      doc2.map_set(root2, "p2", @types.LoroValue::String(big2)),
      "map set p2",
    ) {
    Some(_) => ()
    None => return
  }
  let updates1 = match expect_ok(doc1.export_updates(), "export updates 1") {
    Some(value) => value
    None => return
  }
  match expect_ok(doc2.import_updates(updates1), "import updates 1") {
    Some(_) => ()
    None => return
  }
  let updates2 = match expect_ok(doc2.export_updates(), "export updates 2") {
    Some(value) => value
    None => return
  }
  match expect_ok(doc1.import_updates(updates2), "import updates 2") {
    Some(_) => ()
    None => return
  }
  let snapshot = match
    expect_ok(doc1.export_loro_snapshot(), "export snapshot") {
    Some(value) => value
    None => return
  }
  println("snapshot_large \{bytes_to_hex(snapshot)}")
}
