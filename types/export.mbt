///|
// Export mode selector for encoded payloads.
pub(all) enum ExportMode {
  Snapshot
  Updates(VersionVector?)
}

///|
pub fn ExportMode::snapshot() -> ExportMode {
  ExportMode::Snapshot
}

///|
pub fn ExportMode::updates(from : VersionVector?) -> ExportMode {
  ExportMode::Updates(from)
}
