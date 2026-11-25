import Foundation
@main struct TestPresentationSettings {
 static func main() throws {
  let legacy = try JSONDecoder().decode(WidgetLayout.self, from: Data(#"{"widgets":["timer","music"],"leading":"system","trailing":"timer","showWave":false}"#.utf8))
  precondition(legacy.widgets == [.timer,.music] && !legacy.showWave)
  precondition(legacy.musicAppearance == .vinyl && legacy.swipeTracks && legacy.systemStatusEnabled)
  var custom = legacy; custom.musicAppearance = .cover; custom.swipeTracks = false; custom.systemStatusEnabled = false
  let saved = try JSONEncoder().encode(custom)
  let restored = try JSONDecoder().decode(WidgetLayout.self, from: saved)
  precondition(restored == custom)
  let future = try JSONDecoder().decode(WidgetLayout.self, from: Data(#"{"musicAppearance":"future"}"#.utf8))
  precondition(future.musicAppearance == .vinyl)
  print("PASS: local.7 layout migration preserves user choices, new controls persist, unknown appearance recovers")
 }
}
