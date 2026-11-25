import AppKit
import CryptoKit

/// Streams system media metadata locally; no NetEase cookies or web API.
/// The BSD-licensed adapter is bundled and compiled from its pinned sources.
final class NeteaseSource: NowPlayingSource {
    let id: UserSettings.MediaSource = .netease
    let changeNotification: Notification.Name? = nil
    var onChange: (() -> Void)?
    private(set) var needsPlayerActivation = false
    private(set) var commandError: String?
    private var cached = NowPlayingState()
    private var updatedAt = Date()
    private var process: Process?
    private var lastStart = Date.distantPast
    private var targetedReadPending = false
    private let queue = DispatchQueue(label: "com.scott.notchmate.netease")
    private let commandQueue = DispatchQueue(label: "com.scott.notchmate.netease.commands", qos: .userInitiated)
    private var buffer = Data()

    var state: NowPlayingState {
        var value = cached
        if value.isPlaying, let duration = value.track?.duration, duration > 0 {
            value.position = min(duration, value.position + max(0, Date().timeIntervalSince(updatedAt)))
        }
        return value
    }

    func refresh(completion: @escaping (NowPlayingState) -> Void) {
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: NeteaseSnapshot.bundleID).isEmpty
        if !running {
            stop()
            cached = NowPlayingState()
        } else {
            cached.isRunning = true
            startIfNeeded()
            refreshTargeted()
        }
        completion(state)
    }

    private func refreshTargeted() {
        guard !targetedReadPending, let adapter = adapterArguments else { return }
        targetedReadPending = true
        queue.async { [weak self] in
            let data = Self.run(adapter + ["get", "--netease"])
            if let data, NeteaseSnapshot.decode(data) != nil,
               let payload = try? JSONSerialization.jsonObject(with: data) {
                let envelope: [String: Any] = ["type": "data", "targeted": true, "payload": payload]
                if var line = try? JSONSerialization.data(withJSONObject: envelope) {
                    line.append(10)
                    self?.consume(line)
                }
            }
            DispatchQueue.main.async { self?.targetedReadPending = false }
        }
    }

    private var adapterArguments: [String]? {
        guard let resources = Bundle.main.resourceURL,
              let frameworks = Bundle.main.privateFrameworksURL else { return nil }
        let script = resources.appendingPathComponent("mediaremote-adapter.pl")
        let framework = frameworks.appendingPathComponent("MediaRemoteAdapter.framework")
        guard FileManager.default.fileExists(atPath: script.path),
              FileManager.default.fileExists(atPath: framework.path) else { return nil }
        return [script.path, framework.path]
    }

    private func startIfNeeded() {
        guard process == nil, Date().timeIntervalSince(lastStart) > 3,
              let arguments = adapterArguments else { return }
        lastStart = Date()
        let child = Process()
        let output = Pipe()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        child.arguments = arguments + ["stream", "--no-diff", "--debounce=100"]
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        buffer = Data()
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            self?.queue.async { [weak self] in self?.consume(data) }
        }
        child.terminationHandler = { [weak self, weak child] _ in
            output.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                guard let self, self.process === child else { return }
                self.process = nil
                self.cached = NowPlayingState(isRunning: self.cached.isRunning)
                self.onChange?()
            }
        }
        do {
            try child.run()
            process = child
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            NSLog("CoteDOs: NetEase adapter failed: %@", error.localizedDescription)
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        guard buffer.count < 16_000_000 else { buffer.removeAll(); return }
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            // Ignore the adapter's non-data notifications, rather than
            // clearing the current song on a diagnostic or status event.
            guard let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  root["type"] as? String == "data" else { continue }
            let snapshot = NeteaseSnapshot.decode(line)
            var artworkURL: URL?
            if let artwork = snapshot?.artwork {
                let hash = SHA256.hash(data: artwork).map { String(format: "%02x", $0) }.joined()
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cotedos-netease-artwork", isDirectory: true)
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let url = folder.appendingPathComponent(hash + ".image")
                    if !FileManager.default.fileExists(atPath: url.path) { try artwork.write(to: url, options: .atomic) }
                    artworkURL = url
                } catch { NSLog("CoteDOs: artwork cache failed: %@", error.localizedDescription) }
            }
            let cover = artworkURL
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // A browser owning the global route does not prevent targeted control.
                if let snapshot {
                    self.updatedAt = Date()
                    self.cached = NowPlayingState(isRunning: true, isPlaying: snapshot.playing,
                        track: NowPlayingTrack(name: snapshot.title, artist: snapshot.artist,
                            album: snapshot.album, artworkURL: cover, duration: snapshot.duration, url: nil),
                        position: snapshot.position, isShuffling: snapshot.shuffling)
                } else {
                    // Another media app becoming the global player must not
                    // discard the dedicated NetEase snapshot.
                    self.onChange?()
                    return
                }
                self.onChange?()
            }
        }
    }

    func stop() {
        let child = process
        process = nil
        if child?.isRunning == true { child?.terminate() }
    }

    deinit { stop() }

    func playPause() { command(["send", "2"]) }
    func nextTrack() { command(["send", "4"]) }
    func previousTrack() { command(["send", "5"]) }
    func toggleShuffle() { command(["send", "6"]) }
    func seek(to seconds: TimeInterval) {
        guard seconds.isFinite else { return }
        command(["seek", String(Int64(max(0, seconds) * 1_000_000))])
    }
    func activate() {
        NSRunningApplication.runningApplications(withBundleIdentifier: NeteaseSnapshot.bundleID).first?.activate(options: [])
    }

    private func command(_ arguments: [String]) {
        guard let adapter = adapterArguments else { return }
        commandQueue.async { [weak self] in
            let operation = arguments.first == "seek" ? "netease-seek" : "netease-send"
            let result = Self.run(adapter + [operation] + arguments.dropFirst())
            DispatchQueue.main.async {
                self?.needsPlayerActivation = result == nil
                self?.commandError = result == nil ? "网易云控制未连接，请打开网易云后重试。" : nil
                self?.onChange?()
                self?.refreshTargeted()
            }
        }
    }

    private static func run(_ arguments: [String]) -> Data? {
        let child = Process()
        let pipe = Pipe()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        child.arguments = arguments
        child.standardOutput = pipe
        child.standardError = FileHandle.nullDevice
        do {
            try child.run()
            let timeout = DispatchWorkItem { if child.isRunning { child.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeout)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            child.waitUntilExit()
            timeout.cancel()
            return child.terminationStatus == 0 ? data : nil
        } catch { return nil }
    }
}
