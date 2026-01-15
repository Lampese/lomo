///|
// Map set operation (value None indicates deletion).
pub struct MapSet {
  key : String
  value : @types.LoroValue?
} derive(Show)

///|
pub fn MapSet::new(key : String, value : @types.LoroValue?) -> MapSet {
  MapSet::{ key, value }
}

///|
pub fn MapSet::key(self : MapSet) -> String {
  self.key
}

///|
pub fn MapSet::value(self : MapSet) -> @types.LoroValue? {
  self.value
}
