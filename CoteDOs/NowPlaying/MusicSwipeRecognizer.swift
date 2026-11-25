import Foundation

enum MusicSwipe: Equatable {
    case previous, next
    var title: String { self == .next ? "下一首" : "上一首" }
    var symbol: String { self == .next ? "forward.end.fill" : "backward.end.fill" }
}

/// One deliberate horizontal gesture sends one command. Momentum never repeats it.
struct MusicSwipeRecognizer {
    private var x = 0.0
    private var y = 0.0
    private var lastEvent = -Double.infinity
    private var lastFire = -Double.infinity
    private var fired = false
    mutating func reset() { x = 0; y = 0; fired = false; lastEvent = -.infinity }
    mutating func consume(dx: Double, dy: Double, time: Double, precise: Bool,
                          began: Bool = false, ended: Bool = false, momentum: Bool = false) -> MusicSwipe? {
        guard dx.isFinite, dy.isFinite, time.isFinite else { return nil }
        if momentum { return nil }
        if began || time - lastEvent > 0.28 { x = 0; y = 0; fired = false }
        lastEvent = time
        defer { if ended { x = 0; y = 0; fired = false } }
        guard !fired else { return nil }
        x += dx; y += dy
        let threshold = precise ? 32.0 : 9.0
        guard abs(x) >= threshold, abs(x) > abs(y) * 1.6, time - lastFire >= 0.65 else { return nil }
        fired = true; lastFire = time
        return x < 0 ? .next : .previous
    }
}
