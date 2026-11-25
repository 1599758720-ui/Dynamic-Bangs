import Foundation

@main
struct TestNeteaseSnapshot {
    static func main() throws {
        let base: [String: Any] = ["bundleIdentifier": "com.netease.163music",
            "title": "中文歌曲", "artist": "歌手", "duration": 200,
            "elapsedTime": 10, "timestamp": 1000, "playing": true,
            "artworkData": Data([1, 2, 3]).base64EncodedString()]
        func decode(_ value: [String: Any]) -> NeteaseSnapshot? {
            NeteaseSnapshot.decode(try! JSONSerialization.data(withJSONObject: value),
                                   now: Date(timeIntervalSince1970: 1005))
        }
        let live = decode(base)!
        precondition(live.title == "中文歌曲" && live.artist == "歌手")
        precondition(live.position == 15 && live.playing && live.artwork == Data([1, 2, 3]))
        var paused = base; paused["playing"] = false
        precondition(decode(paused)!.position == 10)
        var other = base; other["bundleIdentifier"] = "com.spotify.client"
        precondition(decode(other) == nil)
        var missing = base; missing["title"] = "  "
        precondition(decode(missing) == nil)
        var bounded = base; bounded["elapsedTimeNow"] = 500
        precondition(decode(bounded)!.position == 200)
        let event: [String: Any] = ["type": "data", "diff": false, "payload": base]
        precondition(decode(event)!.title == "中文歌曲")
        precondition(NeteaseSnapshot.decode(Data("invalid".utf8)) == nil)
        print("PASS: metadata, artwork, paused position, source isolation, empty title, bounds, stream envelope, invalid JSON")
    }
}
