///|
// JSON-like data model for container values.
pub(all) enum LoroValue {
  Null
  Bool(Bool)
  I64(Int64)
  F64(Double)
  String(String)
  Bytes(Bytes)
  List(Array[LoroValue])
  Map(Map[String, LoroValue])
  Container(ContainerID)
} derive(Show)

///|
pub fn LoroValue::is_container(self : LoroValue) -> Bool {
  match self {
    Container(_) => true
    _ => false
  }
}

///|
pub fn LoroValue::into_container(self : LoroValue) -> ContainerID? {
  match self {
    Container(id) => Some(id)
    _ => None
  }
}
