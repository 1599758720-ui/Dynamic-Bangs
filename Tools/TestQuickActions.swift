import AppKit
import Foundation
import SwiftUI

private final class TestKeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@main
struct TestQuickActions {
    static func main() throws {
        verifyContractAndBuiltIns()
        verifySearchRankingAndNoLaunch()
        try verifySyntheticAppDiscovery()
        verifySelectionSteppingAndReconciliation()
        verifyLiveApplicationsScanBounded()
        MainActor.assumeIsolated {
            verifyViewKeyboardFocusAndReturnInPanel()
        }
        print("PASS: QuickActions contract, Chinese/English/Pinyin/acronym ranking, symlink & background-shim filtering, selection reconciliation, bounded live app discovery, and NSPanel focus/arrow/Return dispatch")
    }

    private static func verifyContractAndBuiltIns() {
        let sampleURL = URL(fileURLWithPath: "/Applications/Safari.app")
        let allActions: [QuickAction] = [
            .dashboard, .music, .spectrum, .timer, .tasks,
            .files, .capture, .widgets, .settings, .app(sampleURL),
        ]
        precondition(Set(allActions).count == 10, "All 10 QuickAction cases must be distinct and Hashable")

        let builtInActions = Set(QuickActionsCatalog.builtInItems.map(\.action))
        let expectedBuiltIns: Set<QuickAction> = [
            .dashboard, .music, .spectrum, .timer, .tasks,
            .files, .capture, .widgets, .settings,
        ]
        precondition(builtInActions == expectedBuiltIns, "Built-in catalog must cover all 9 non-app QuickAction cases")

        // Verify exact SwiftUI API contract: `struct QuickActionsView: View { let onSelect: (QuickAction) -> Void }`
        var captured: QuickAction?
        let view = QuickActionsView { action in captured = action }
        view.onSelect(.timer)
        precondition(captured == .timer, "QuickActionsView.onSelect property contract must remain callable directly")
    }

    private static func verifySearchRankingAndNoLaunch() {
        let mockApps: [QuickActionsAppEntry] = [
            QuickActionsAppEntry(
                url: URL(fileURLWithPath: "/Applications/NeteaseMusic.app"),
                title: "网易云音乐",
                bundleStem: "NeteaseMusic",
                locationLabel: "应用程序",
                bundleIdentifier: "com.netease.163music",
                searchTerms: ["网易云音乐", "NeteaseMusic", "163music"]
            ),
            QuickActionsAppEntry(
                url: URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"),
                title: "Activity Monitor",
                bundleStem: "Activity Monitor",
                locationLabel: "实用工具",
                bundleIdentifier: "com.apple.ActivityMonitor",
                searchTerms: ["Activity Monitor", "ActivityMonitor"]
            ),
            QuickActionsAppEntry(
                url: URL(fileURLWithPath: "/Applications/Obsidian.app"),
                title: "Obsidian",
                bundleStem: "Obsidian",
                locationLabel: "应用程序",
                bundleIdentifier: "md.obsidian",
                searchTerms: ["Obsidian"]
            ),
        ]

        // Empty query shows all 9 built-in destinations followed by bounded browse apps.
        let browse = QuickActionsCatalog.items(query: "   ", applications: mockApps, browseAppLimit: 2)
        precondition(browse.count == 11, "Empty query must return 9 built-in actions + capped browse apps")
        precondition(browse.first?.action == .dashboard)

        // Exact Chinese built-in match outranks broader keyword matches.
        let musicResults = QuickActionsCatalog.items(query: "音乐", applications: mockApps)
        precondition(musicResults.first?.action == .music, "Exact built-in title '音乐' must rank first")
        precondition(
            musicResults.contains(where: { $0.action == .app(URL(fileURLWithPath: "/Applications/NeteaseMusic.app")) }),
            "Localized app '网易云音乐' must also match '音乐'"
        )

        // English stem matches localized Chinese app without launching anything.
        let neteaseByStem = QuickActionsCatalog.items(query: "netease", applications: mockApps)
        precondition(
            neteaseByStem.contains(where: { $0.action == .app(URL(fileURLWithPath: "/Applications/NeteaseMusic.app")) }),
            "English bundle stem must match localized app entry"
        )

        // Pinyin and English keywords match Chinese built-in features.
        precondition(QuickActionsCatalog.items(query: "fanqiezhong", applications: mockApps).first?.action == .timer)
        precondition(QuickActionsCatalog.items(query: "pomodoro", applications: mockApps).first?.action == .timer)
        precondition(QuickActionsCatalog.items(query: "suji", applications: mockApps).first?.action == .capture)
        precondition(QuickActionsCatalog.items(query: "频谱", applications: mockApps).first?.action == .spectrum)
        precondition(QuickActionsCatalog.items(query: "任务", applications: mockApps).first?.action == .tasks)
        precondition(QuickActionsCatalog.items(query: "暂存", applications: mockApps).first?.action == .files)
        precondition(QuickActionsCatalog.items(query: "缩略", applications: mockApps).first?.action == .widgets)
        precondition(QuickActionsCatalog.items(query: "偏好设置", applications: mockApps).first?.action == .settings)

        // Acronym match ("am" -> "Activity Monitor").
        let acronymResults = QuickActionsCatalog.items(query: "am", applications: mockApps)
        precondition(
            acronymResults.contains(where: { $0.title == "Activity Monitor" }),
            "Initialism 'am' must match 'Activity Monitor'"
        )

        // Non-matching query yields empty array cleanly.
        precondition(QuickActionsCatalog.items(query: "不存在的超级应用XYZ999", applications: mockApps).isEmpty)
    }

    private static func verifySyntheticAppDiscovery() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("CoteDOs-quickactions-test-" + UUID().uuidString)
        let primaryApps = root.appendingPathComponent("Applications", isDirectory: true)
        let secondaryApps = root.appendingPathComponent("UserApps", isDirectory: true)
        let realTargetRoot = root.appendingPathComponent("Cryptex", isDirectory: true)
        try fm.createDirectory(at: primaryApps, withIntermediateDirectories: true)
        try fm.createDirectory(at: secondaryApps, withIntermediateDirectories: true)
        try fm.createDirectory(at: realTargetRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        // 1. Standard app with nested helper .app inside Contents/Helpers (must NOT descend into package).
        let alphaApp = try makeMockAppBundle(
            in: primaryApps,
            bundleFileName: "AlphaStudio.app",
            bundleID: "com.example.alpha",
            displayName: "Alpha 创作台",
            backgroundOnly: false
        )
        let nestedHelpers = alphaApp.appendingPathComponent("Contents/Helpers", isDirectory: true)
        try fm.createDirectory(at: nestedHelpers, withIntermediateDirectories: true)
        _ = try makeMockAppBundle(
            in: nestedHelpers,
            bundleFileName: "AlphaHelper.app",
            bundleID: "com.example.alpha.helper",
            displayName: "Internal Helper",
            backgroundOnly: false
        )

        // 2. Duplicate bundle ID in secondary directory must be deduplicated in favor of primary directory.
        _ = try makeMockAppBundle(
            in: secondaryApps,
            bundleFileName: "AlphaStudioCopy.app",
            bundleID: "com.example.alpha",
            displayName: "Alpha Duplicate",
            backgroundOnly: false
        )

        // 3. Symlinked .app (mirrors macOS /Applications/Safari.app -> Preboot Cryptex).
        let cryptexSafari = try makeMockAppBundle(
            in: realTargetRoot,
            bundleFileName: "SafariMock.app",
            bundleID: "com.example.safarimock",
            displayName: "Safari 模拟",
            backgroundOnly: false
        )
        let symlinkSafari = primaryApps.appendingPathComponent("SafariMock.app")
        try fm.createSymbolicLink(at: symlinkSafari, withDestinationURL: cryptexSafari)

        // 4. Faceless background-only shim (`LSBackgroundOnly = true`) must be excluded.
        _ = try makeMockAppBundle(
            in: primaryApps,
            bundleFileName: "URLShim.app",
            bundleID: "com.example.shim",
            displayName: "URL Shim",
            backgroundOnly: true
        )

        // 5. Non-directory `.app` file and `.zip` archive must be ignored.
        try Data("not a bundle".utf8).write(to: primaryApps.appendingPathComponent("Broken.app"))
        try fm.createDirectory(at: primaryApps.appendingPathComponent("Empty.app"), withIntermediateDirectories: true)
        try Data("archive".utf8).write(to: primaryApps.appendingPathComponent("Archive.zip"))

        let discovered = QuickActionsCatalog.discoverApplications(in: [primaryApps, secondaryApps], limit: 50)
        let urls = discovered.map(\.url.lastPathComponent)
        precondition(urls == ["AlphaStudio.app", "SafariMock.app"], "Unexpected discovered bundles: \(urls)")
        precondition(
            discovered.first(where: { $0.bundleStem == "SafariMock" })?.url.standardizedFileURL == symlinkSafari.standardizedFileURL,
            "Symlinked .app must preserve its user-facing Applications URL rather than Cryptex target path"
        )
    }

    private static func makeMockAppBundle(
        in directory: URL,
        bundleFileName: String,
        bundleID: String,
        displayName: String,
        backgroundOnly: Bool
    ) throws -> URL {
        let fm = FileManager.default
        let appURL = directory.appendingPathComponent(bundleFileName, isDirectory: true)
        let contents = appURL.appendingPathComponent("Contents", isDirectory: true)
        try fm.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleDisplayName": displayName,
            "CFBundleName": bundleFileName.replacingOccurrences(of: ".app", with: ""),
            "CFBundlePackageType": "APPL",
            "LSBackgroundOnly": backgroundOnly,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return appURL
    }

    private static func verifySelectionSteppingAndReconciliation() {
        let items = QuickActionsCatalog.builtInItems
        precondition(items.count == 9)

        let first = items[0].id
        let second = items[1].id
        let third = items[2].id
        let last = items[items.count - 1].id

        // Clamped stepping at top and bottom.
        precondition(QuickActionsCatalog.steppedSelection(current: first, in: items, delta: -1) == first)
        precondition(QuickActionsCatalog.steppedSelection(current: first, in: items, delta: 1) == second)
        precondition(QuickActionsCatalog.steppedSelection(current: second, in: items, delta: 1) == third)
        precondition(QuickActionsCatalog.steppedSelection(current: last, in: items, delta: 1) == last)
        precondition(QuickActionsCatalog.steppedSelection(current: nil, in: items, delta: 1) == first)
        precondition(QuickActionsCatalog.steppedSelection(current: nil, in: [], delta: 1) == nil)

        // Preserves existing keyboard choice when async app catalog arrives, resets when query changes.
        precondition(QuickActionsCatalog.reconciledSelection(current: third, in: items, resetToFirst: false) == third)
        precondition(QuickActionsCatalog.reconciledSelection(current: third, in: items, resetToFirst: true) == first)
        precondition(QuickActionsCatalog.reconciledSelection(current: "missing", in: items, resetToFirst: false) == first)
    }

    private static func verifyLiveApplicationsScanBounded() {
        let liveApps = QuickActionsCatalog.discoverApplications(limit: 40)
        precondition(!liveApps.isEmpty, "Live macOS Applications scan must discover installed apps")
        precondition(liveApps.count <= 40, "Discovery must honor explicit upper bound")
        precondition(
            liveApps.contains(where: { $0.bundleStem == "Safari" || $0.bundleStem == "Calculator" || $0.bundleStem == "Terminal" }),
            "Live scan must find standard macOS applications from public Applications directories"
        )
    }

    @MainActor
    private static func verifyViewKeyboardFocusAndReturnInPanel() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        var selectedActions: [QuickAction] = []
        let panel = TestKeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 245),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.appearance = NSAppearance(named: .darkAqua)

        let view = QuickActionsView(
            customAppLoader: {
                [
                    QuickActionsAppEntry(
                        url: URL(fileURLWithPath: "/Applications/Safari.app"),
                        title: "Safari",
                        bundleStem: "Safari",
                        locationLabel: "应用程序",
                        bundleIdentifier: "com.apple.Safari",
                        searchTerms: ["Safari"]
                    )
                ]
            },
            onSelect: { action in
                selectedActions.append(action)
            }
        )
        panel.contentView = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
        panel.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.18))

        precondition(panel.isKeyWindow, "Test Notch-like NSPanel must become key")
        precondition(panel.firstResponder is NSTextView, "Search TextField must receive initial keyboard focus on mount")

        // Step down twice from `.dashboard` -> `.music` -> `.spectrum`, then step up once -> `.music`, then Return.
        sendKey(to: panel, keyCode: 125, characters: "\u{F701}") // Down
        sendKey(to: panel, keyCode: 125, characters: "\u{F701}") // Down
        sendKey(to: panel, keyCode: 126, characters: "\u{F700}") // Up
        sendKey(to: panel, keyCode: 36, characters: "\r")        // Return
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))

        precondition(selectedActions == [.music], "Expected Down, Down, Up, Return to select .music, got \(selectedActions)")

        // Enter a live search query via the focused field editor (`Safari`), verify filtering does NOT launch/fire,
        // then verify Return selects `.app(/Applications/Safari.app)`.
        guard let editor = panel.firstResponder as? NSTextView else {
            fatalError("Expected NSTextView field editor as first responder")
        }
        editor.insertText("Safari", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        precondition(selectedActions.count == 1, "Typing a query must never auto-open or invoke onSelect")

        sendKey(to: panel, keyCode: 36, characters: "\r")
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        precondition(
            selectedActions == [.music, .app(URL(fileURLWithPath: "/Applications/Safari.app"))],
            "Return after typing 'Safari' must select .app(/Applications/Safari.app), got \(selectedActions)"
        )

        // Non-matching query + Return must be a safe no-op.
        editor.insertText("不存在的应用_ZZZ_404", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        sendKey(to: panel, keyCode: 36, characters: "\r")
        RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        precondition(selectedActions.count == 2, "Return on empty results must not invoke onSelect")

        panel.orderOut(nil)
    }

    @MainActor
    private static func sendKey(to window: NSWindow, keyCode: UInt16, characters: String) {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ) else {
            fatalError("Failed to synthesize NSEvent")
        }
        window.sendEvent(event)
    }
}
