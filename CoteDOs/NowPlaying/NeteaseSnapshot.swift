import Foundation

/// Decode only NetEase's system Now Playing record. Never attribute another
/// player's metadata or commands to a merely open NetEase window.
struct NeteaseSnapshot {
    static let bundleID = "com.netease.163music"
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var position: Double
    var playing: Bool
    var shuffling: Bool
    var artwork: Data?

    static func decode(_ data: Data, now: Date = Date()) -> NeteaseSnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let payload = (root["payload"] as? [String: Any]) ?? root
        guard payload["bundleIdentifier"] as? String == bundleID
                || payload["parentApplicationBundleIdentifier"] as? String == bundleID,
              let title = payload["title"] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        func number(_ key: String) -> Double {
            let v = (payload[key] as? NSNumber)?.doubleValue ?? 0
            return v.isFinite ? v : 0
        }
        let duration = max(0, number("duration"))
        let playing = payload["playing"] as? Bool ?? false
        var position = max(0, number("elapsedTimeNow"))
        if payload["elapsedTimeNow"] == nil {
            position = max(0, number("elapsedTime"))
            let timestamp = number("timestamp")
            if playing, timestamp > 0 {
                position += min(30, max(0, now.timeIntervalSince1970 - timestamp))
            }
        }
        if duration > 0 { position = min(position, duration) }
        var artwork: Data?
        if let base64 = payload["artworkData"] as? String, base64.utf8.count <= 12_000_000 {
            artwork = Data(base64Encoded: base64)
        }
        return NeteaseSnapshot(title: title, artist: payload["artist"] as? String ?? "",
                               album: payload["album"] as? String ?? "", duration: duration,
                               position: position, playing: playing,
                               shuffling: number("shuffleMode") > 1, artwork: artwork)
    }
}
