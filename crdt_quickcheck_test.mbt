///|
enum OpValue {
  Bool(Bool)
  Int(Int)
  Str(String)
} derive(Show)

///|
enum DocOp {
  MapSet(String, OpValue)
  MapDelete(String)
  ListInsert(Int, OpValue)
  ListPush(OpValue)
  ListSet(Int, OpValue)
  ListDelete(Int, Int)
  TextInsert(Int, String)
  TextDelete(Int, Int)
} derive(Show)

///|
struct DocHandles {
  map : @container.MapHandler
  list : @container.ListHandler
  text : @container.TextHandler
}

///|
fn doc_handles(doc : LoroDoc) -> DocHandles {
  DocHandles::{
    map: doc.get_map("root"),
    list: doc.get_list("list"),
    text: doc.get_text("text"),
  }
}

///|
fn op_value_to_loro(value : OpValue) -> @types.LoroValue {
  match value {
    OpValue::Bool(v) => @types.LoroValue::Bool(v)
    OpValue::Int(v) => @types.LoroValue::I64(Int64::from_int(v))
    OpValue::Str(v) => @types.LoroValue::String(v)
  }
}

///|
fn clamp_index(idx : Int, len : Int) -> Int {
  let positive = if idx < 0 { -idx } else { idx }
  if positive > len { len } else { positive }
}

///|
fn existing_index(idx : Int, len : Int) -> Int {
  let positive = if idx < 0 { -idx } else { idx }
  if positive >= len { len - 1 } else { positive }
}

///|
fn positive_len(value : Int) -> Int {
  if value < 0 { -value } else { value }
}

///|
fn list_len(
  doc : LoroDoc,
  list : @container.ListHandler,
) -> Result[Int, @types.LoroError] {
  match doc.list_diff(list) {
    Ok(values) => Ok(values.length())
    Err(err) => Err(err)
  }
}

///|
fn text_len(
  doc : LoroDoc,
  text : @container.TextHandler,
) -> Result[Int, @types.LoroError] {
  match doc.text_to_string(text) {
    Ok(value) => Ok(value.length())
    Err(err) => Err(err)
  }
}

///|
fn maps_equal(
  left : Map[String, @types.LoroValue],
  right : Map[String, @types.LoroValue],
) -> Bool {
  if left.length() != right.length() {
    false
  } else {
    for key, value in left {
      match right.get(key) {
        Some(other) =>
          if !value_equal(value, other) {
            return false
          }
        None => return false
      }
    }
    true
  }
}

///|
fn arrays_equal(
  left : Array[@types.LoroValue],
  right : Array[@types.LoroValue],
) -> Bool {
  if left.length() != right.length() {
    false
  } else {
    for i in 0..<left.length() {
      if !value_equal(left[i], right[i]) {
        return false
      }
    }
    true
  }
}

///|
fn value_equal(
  left : @types.LoroValue,
  right : @types.LoroValue,
) -> Bool {
  match (left, right) {
    (@types.LoroValue::Null, @types.LoroValue::Null) => true
    (@types.LoroValue::Bool(a), @types.LoroValue::Bool(b)) => a == b
    (@types.LoroValue::I64(a), @types.LoroValue::I64(b)) => a == b
    (@types.LoroValue::F64(a), @types.LoroValue::F64(b)) => a == b
    (@types.LoroValue::String(a), @types.LoroValue::String(b)) => a == b
    (@types.LoroValue::Bytes(a), @types.LoroValue::Bytes(b)) => a == b
    (@types.LoroValue::List(a), @types.LoroValue::List(b)) =>
      arrays_equal(a, b)
    (@types.LoroValue::Map(a), @types.LoroValue::Map(b)) =>
      maps_equal(a, b)
    (@types.LoroValue::Container(a), @types.LoroValue::Container(b)) =>
      a == b
    _ => false
  }
}

///|
fn apply_op(
  doc : LoroDoc,
  handles : DocHandles,
  op : DocOp,
) -> Bool {
  match op {
    DocOp::MapSet(key, value) =>
      match doc.map_set(handles.map, key, op_value_to_loro(value)) {
        Ok(_) => true
        Err(_) => false
      }
    DocOp::MapDelete(key) =>
      match doc.map_delete(handles.map, key) {
        Ok(_) => true
        Err(_) => false
      }
    DocOp::ListInsert(index, value) =>
      match list_len(doc, handles.list) {
        Ok(len) =>
          match doc.list_insert(
            handles.list,
            clamp_index(index, len),
            op_value_to_loro(value),
          ) {
            Ok(_) => true
            Err(_) => false
          }
        Err(_) => false
      }
    DocOp::ListPush(value) =>
      match doc.list_push(handles.list, op_value_to_loro(value)) {
        Ok(_) => true
        Err(_) => false
      }
    DocOp::ListSet(index, value) =>
      match list_len(doc, handles.list) {
        Ok(len) =>
          if len == 0 {
            true
          } else {
            match doc.list_set(
              handles.list,
              existing_index(index, len),
              op_value_to_loro(value),
            ) {
              Ok(_) => true
              Err(_) => false
            }
          }
        Err(_) => false
      }
    DocOp::ListDelete(index, span) =>
      match list_len(doc, handles.list) {
        Ok(len) =>
          if len == 0 {
            true
          } else {
            let start = clamp_index(index, len)
            let width = positive_len(span)
            let end = start + width
            if width == 0 || start >= len {
              true
            } else {
              let actual = if end > len { len - start } else { width }
              match doc.list_delete(handles.list, start, actual) {
                Ok(_) => true
                Err(_) => false
              }
            }
          }
        Err(_) => false
      }
    DocOp::TextInsert(index, chunk) =>
      match text_len(doc, handles.text) {
        Ok(len) =>
          match doc.text_insert(
            handles.text,
            clamp_index(index, len),
            chunk,
          ) {
            Ok(_) => true
            Err(_) => false
          }
        Err(_) => false
      }
    DocOp::TextDelete(index, span) =>
      match text_len(doc, handles.text) {
        Ok(len) =>
          if len == 0 {
            true
          } else {
            let start = clamp_index(index, len)
            let width = positive_len(span)
            if width == 0 || start >= len {
              true
            } else {
              let end = start + width
              let actual = if end > len { len - start } else { width }
              match doc.text_delete(handles.text, start, actual) {
                Ok(_) => true
                Err(_) => false
              }
            }
          }
        Err(_) => false
      }
  }
}

///|
fn apply_ops(
  doc : LoroDoc,
  handles : DocHandles,
  ops : Array[DocOp],
) -> Bool {
  for op in ops {
    if !apply_op(doc, handles, op) {
      return false
    }
  }
  true
}

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
  let len_gen = @quickcheck.int_range(0, max_len)
  len_gen.bind(len => char_gen.array_with_size(len).fmap(chars_to_string))
}

///|
fn gen_value() -> @quickcheck.Gen[OpValue] {
  let bools =
    @quickcheck.one_of_array([false, true]).fmap(v => OpValue::Bool(v))
  let ints = @quickcheck.int_range(-3, 6).fmap(v => OpValue::Int(v))
  let strings = gen_ascii_string(4).fmap(v => OpValue::Str(v))
  @quickcheck.one_of([bools, ints, strings])
}

///|
fn gen_op() -> @quickcheck.Gen[DocOp] {
  let value = gen_value()
  let key = gen_ascii_string(3)
  let index = @quickcheck.int_range(0, 8)
  let len = @quickcheck.int_range(0, 4)
  let text = gen_ascii_string(5)
  @quickcheck.one_of([
    @quickcheck.liftA2((k, v) => DocOp::MapSet(k, v), key, value),
    key.fmap(k => DocOp::MapDelete(k)),
    @quickcheck.liftA2((i, v) => DocOp::ListInsert(i, v), index, value),
    value.fmap(v => DocOp::ListPush(v)),
    @quickcheck.liftA2((i, v) => DocOp::ListSet(i, v), index, value),
    @quickcheck.liftA2((i, span) => DocOp::ListDelete(i, span), index, len),
    @quickcheck.liftA2((pos, chunk) => DocOp::TextInsert(pos, chunk), index, text),
    @quickcheck.liftA2((pos, span) => DocOp::TextDelete(pos, span), index, len),
  ])
}

///|
fn gen_ops(max_len : Int) -> @quickcheck.Gen[Array[DocOp]] {
  let len_gen = @quickcheck.int_range(1, max_len)
  len_gen.bind(len => gen_op().array_with_size(len))
}

///|
test "quickcheck: replicas converge after exchanging updates" {
  let prop = @quickcheck.forall(
    @quickcheck.tuple(gen_ops(6), gen_ops(6)),
    pair => {
      let (ops_a, ops_b) = pair
      let doc_a = LoroDoc::new()
      doc_a.set_peer_id(1)
      let handles_a = doc_handles(doc_a)
      let doc_b = LoroDoc::new()
      doc_b.set_peer_id(2)
      let handles_b = doc_handles(doc_b)
      if !apply_ops(doc_a, handles_a, ops_a) {
        false
      } else if !apply_ops(doc_b, handles_b, ops_b) {
        false
      } else {
        match doc_a.export_updates() {
          Ok(bytes_a) =>
            match doc_b.export_updates() {
              Ok(bytes_b) =>
                match doc_a.import_updates(bytes_b) {
                  Ok(_) =>
                    match doc_b.import_updates(bytes_a) {
                      Ok(_) =>
                        value_equal(doc_a.get_deep_value(), doc_b.get_deep_value())
                      Err(_) => false
                    }
                  Err(_) => false
                }
              Err(_) => false
            }
          Err(_) => false
        }
      }
    },
  )
  @quickcheck.quick_check(prop, max_success=60)
}

///|
test "quickcheck: importing identical update batches is idempotent" {
  let prop = @quickcheck.forall(gen_ops(8), ops => {
    let source = LoroDoc::new()
    source.set_peer_id(9)
    let handles = doc_handles(source)
    if !apply_ops(source, handles, ops) {
      false
    } else {
      match source.export_updates() {
        Ok(bytes) => {
          let value = source.get_deep_value()
          let replica = LoroDoc::new()
          replica.set_peer_id(10)
          match replica.import_updates(bytes) {
            Ok(_) => {
              let once_value = replica.get_deep_value()
              match replica.import_updates(bytes) {
                Ok(_) => {
                  let twice_value = replica.get_deep_value()
                  value_equal(value, once_value) && value_equal(once_value, twice_value)
                }
                Err(_) => false
              }
            }
            Err(_) => false
          }
        }
        Err(_) => false
      }
    }
  })
  @quickcheck.quick_check(prop, max_success=60)
}

///|
test "quickcheck: snapshot plus delta reconstructs final state" {
  let prop = @quickcheck.forall(
    @quickcheck.tuple(gen_ops(5), gen_ops(4)),
    pair => {
      let (base_ops, tail_ops) = pair
      let doc = LoroDoc::new()
      doc.set_peer_id(20)
      let handles = doc_handles(doc)
      if !apply_ops(doc, handles, base_ops) {
        false
      } else {
        let version = doc.version()
        match doc.export_bytes(@types.ExportMode::Snapshot) {
          Ok(snapshot) =>
            if !apply_ops(doc, handles, tail_ops) {
              false
            } else {
              match doc.export_updates_from(Some(version)) {
                Ok(delta) => {
                  let final_value = doc.get_deep_value()
                  let restored = LoroDoc::new()
                  restored.set_peer_id(21)
                  match restored.import_bytes(snapshot) {
                    Ok(_) =>
                      match restored.import_updates(delta) {
                        Ok(_) =>
                          value_equal(final_value, restored.get_deep_value())
                        Err(_) => false
                      }
                    Err(_) => false
                  }
                }
                Err(_) => false
              }
            }
          Err(_) => false
        }
      }
    },
  )
  @quickcheck.quick_check(prop, max_success=60)
}
