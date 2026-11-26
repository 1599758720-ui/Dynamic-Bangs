import Foundation

/// Destinations and app targets surfaced by `QuickActionsView`.
enum QuickAction: Hashable, Sendable {
    case dashboard
    case music
    case spectrum
    case timer
    case tasks
    case files
    case capture
    case widgets
    case settings
    case app(URL)
}

/// Semantic accent token kept decoupled from SwiftUI so catalog/search types remain pure value data.
enum QuickActionTint: Hashable, Sendable {
    case cyan
    case pink
    case purple
    case orange
    case mint
    case blue
    case green
    case neutral
}

/// Metadata for a discovered macOS `.app` bundle in an Applications directory.
/// Populated off the main thread using public Foundation filesystem/bundle APIs without launching anything.
struct QuickActionsAppEntry: Identifiable, Hashable, Sendable {
    let url: URL
    let title: String
    let bundleStem: String
    let locationLabel: String
    let bundleIdentifier: String?
    let searchTerms: [String]

    var id: String { "app:" + url.standardizedFileURL.path }

    var subtitle: String {
        if title.caseInsensitiveCompare(bundleStem) != .orderedSame, !bundleStem.isEmpty {
            return "\(bundleStem) · \(locationLabel)"
        }
        return locationLabel
    }
}

/// A single row model presented in `QuickActionsView`.
struct QuickActionItem: Identifiable, Hashable, Sendable {
    enum SourceKind: Hashable, Sendable {
        case builtIn
        case application
    }

    let id: String
    let action: QuickAction
    let title: String
    let subtitle: String
    let badge: String
    let symbol: String
    let tint: QuickActionTint
    let sourceKind: SourceKind
    let tooltip: String
    fileprivate let normalizedTitle: String
    fileprivate let normalizedSubtitle: String
    fileprivate let normalizedTerms: [String]
    fileprivate let titleWords: [String]
    fileprivate let acronym: String

    init(
        id: String,
        action: QuickAction,
        title: String,
        subtitle: String,
        badge: String,
        symbol: String,
        tint: QuickActionTint,
        sourceKind: SourceKind,
        tooltip: String? = nil,
        keywords: [String] = []
    ) {
        self.id = id
        self.action = action
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
        self.symbol = symbol
        self.tint = tint
        self.sourceKind = sourceKind
        self.tooltip = tooltip ?? "\(title) — \(subtitle)"

        let foldedTitle = QuickActionsCatalog.normalize(title)
        self.normalizedTitle = foldedTitle
        self.normalizedSubtitle = QuickActionsCatalog.normalize(subtitle)

        var terms: [String] = []
        var seen = Set<String>()
        for raw in [title] + keywords {
            let folded = QuickActionsCatalog.normalize(raw)
            if !folded.isEmpty, seen.insert(folded).inserted {
                terms.append(folded)
            }
        }
        self.normalizedTerms = terms

        let words = QuickActionsCatalog.wordTokens(from: title) + keywords.flatMap(QuickActionsCatalog.wordTokens(from:))
        var uniqueWords: [String] = []
        var seenWords = Set<String>()
        for word in words where !word.isEmpty && seenWords.insert(word).inserted {
            uniqueWords.append(word)
        }
        self.titleWords = uniqueWords

        let primaryWords = QuickActionsCatalog.wordTokens(from: title)
        self.acronym = String(primaryWords.compactMap(\.first))
    }

    var appURL: URL? {
        if case .app(let url) = action { return url }
        return nil
    }
}

/// Pure catalog, ranking, selection, and off-main local application discovery logic.
enum QuickActionsCatalog {
    static let maxDiscoveredApps = 220
    static let defaultBrowseAppLimit = 18
    static let defaultSearchResultLimit = 32
    private static let maxScannedBundles = 600
    private static let maxScannedEntriesPerRoot = 4_000
    private static let maxDirectoryDepth = 2

    static let availableSystemTools: [QuickActionItem] = [
        ("AirDrop", "dot.radiowaves.left.and.right", "/System/Library/CoreServices/Finder.app/Contents/Applications/AirDrop.app"),
        ("Siri", "waveform.circle", "/System/Applications/Siri.app"),
    ].compactMap { title, symbol, path in
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        return QuickActionItem(id: "app:" + url.path, action: .app(url), title: title,
                               subtitle: "系统应用", badge: "应用", symbol: symbol, tint: .blue,
                               sourceKind: .builtIn)
    }

    /// Built-in Côte d'OS workbench destinations and windows, matching the local Chinese UI.
    static let builtInItems: [QuickActionItem] = [
        QuickActionItem(
            id: "builtin:dashboard",
            action: .dashboard,
            title: "今日工作台",
            subtitle: "返回刘海组件总览",
            badge: "总览",
            symbol: "square.grid.2x2.fill",
            tint: .cyan,
            sourceKind: .builtIn,
            keywords: ["工作台", "总览", "主页", "首页", "卡片", "gongzuotai", "zonglan", "gzt", "zl", "dashboard", "overview", "home"]
        ),
        QuickActionItem(
            id: "builtin:music",
            action: .music,
            title: "音乐",
            subtitle: "播放控制、网易云音乐与 Apple Music",
            badge: "功能",
            symbol: "music.note",
            tint: .pink,
            sourceKind: .builtIn,
            keywords: ["网易云音乐", "网易云", "音乐播放", "播放器", "切歌", "歌曲", "yinyue", "wangyiyun", "bofang", "yy", "wyy", "music", "now playing", "netease", "spotify", "player"]
        ),
        QuickActionItem(
            id: "builtin:spectrum",
            action: .spectrum,
            title: "音频频谱",
            subtitle: "实时系统音频律动舞台",
            badge: "功能",
            symbol: "waveform",
            tint: .purple,
            sourceKind: .builtIn,
            keywords: ["频谱", "波形", "律动", "可视化", "音频", "pinpu", "yinpin", "boxing", "pp", "spectrum", "waveform", "visualizer", "audio"]
        ),
        QuickActionItem(
            id: "builtin:timer",
            action: .timer,
            title: "番茄钟",
            subtitle: "专注计时与休息阶段安排",
            badge: "功能",
            symbol: "timer",
            tint: .orange,
            sourceKind: .builtIn,
            keywords: ["专注", "计时", "倒计时", "休息", "番茄", "fanqiezhong", "zhuanzhu", "jishi", "fqz", "zz", "timer", "pomodoro", "focus"]
        ),
        QuickActionItem(
            id: "builtin:tasks",
            action: .tasks,
            title: "今日任务",
            subtitle: "查看、添加与完成每日任务",
            badge: "窗口",
            symbol: "checklist",
            tint: .mint,
            sourceKind: .builtIn,
            keywords: ["每日任务", "任务", "待办", "清单", "事项", "jinrirenwu", "meirirenwu", "renwu", "daiban", "rw", "db", "tasks", "todo", "checklist"]
        ),
        QuickActionItem(
            id: "builtin:files",
            action: .files,
            title: "文件暂存",
            subtitle: "查看与取用刘海暂存架中的文件",
            badge: "功能",
            symbol: "tray.full",
            tint: .blue,
            sourceKind: .builtIn,
            keywords: ["暂存", "文件", "暂存架", "文件架", "拖放", "中转", "wenjian", "zancun", "wj", "zc", "files", "shelf", "tray", "drop"]
        ),
        QuickActionItem(
            id: "builtin:capture",
            action: .capture,
            title: "快速速记",
            subtitle: "追加笔记到今日 Obsidian 日记",
            badge: "功能",
            symbol: "square.and.pencil",
            tint: .cyan,
            sourceKind: .builtIn,
            keywords: ["速记", "捕捉", "笔记", "日记", "记录", "灵感", "Obsidian", "kuaisusuji", "suji", "biji", "riji", "sj", "bj", "capture", "note", "daily note"]
        ),
        QuickActionItem(
            id: "builtin:widgets",
            action: .widgets,
            title: "组件与缩略显示",
            subtitle: "管理工作台卡片顺序、系统监控与收起态",
            badge: "设置",
            symbol: "slider.horizontal.3",
            tint: .green,
            sourceKind: .builtIn,
            keywords: ["组件", "小组件", "缩略显示", "编辑组件", "系统监控", "CPU", "内存", "电池", "zujian", "suolue", "xtjk", "zj", "widgets", "cards", "layout", "system"]
        ),
        QuickActionItem(
            id: "builtin:settings",
            action: .settings,
            title: "偏好设置",
            subtitle: "通用、刘海、音乐、番茄钟与 Obsidian 设置",
            badge: "设置",
            symbol: "gearshape",
            tint: .neutral,
            sourceKind: .builtIn,
            keywords: ["设置", "偏好", "选项", "配置", "通用", "刘海设置", "pianhaoshezhi", "shezhi", "peizhi", "sz", "settings", "preferences", "options", "config"]
        ),
    ]

    /// Converts a discovered `.app` entry into a displayable `QuickActionItem`.
    static func makeAppItem(from app: QuickActionsAppEntry) -> QuickActionItem {
        QuickActionItem(
            id: app.id,
            action: .app(app.url),
            title: app.title,
            subtitle: app.subtitle,
            badge: "应用",
            symbol: "app.fill",
            tint: .neutral,
            sourceKind: .application,
            tooltip: "\(app.title) — \(app.url.path)",
            keywords: app.searchTerms
        )
    }

    /// Standard local Applications directories (`~/Applications`, `/Applications`, `/System/Applications`),
    /// excluding `/Network` mounts so discovery never stalls on remote shares.
    static func defaultApplicationDirectories(fileManager: FileManager = .default) -> [URL] {
        let domains: [FileManager.SearchPathDomainMask] = [.localDomainMask, .systemDomainMask, .userDomainMask]
        var result: [URL] = []
        var seen = Set<String>()
        for domain in domains {
            for url in fileManager.urls(for: .applicationDirectory, in: domain) {
                let standardized = url.standardizedFileURL
                let path = standardized.path
                guard !path.hasPrefix("/Network/") else { continue }
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
                if seen.insert(path).inserted {
                    result.append(standardized)
                }
            }
        }
        return result
    }

    /// Scans actual Applications directories using public Foundation APIs without launching any app.
    /// Safe to run on a background task; checks `Task.isCancelled` and enforces strict depth and count bounds.
    static func discoverApplications(
        in directories: [URL]? = nil,
        limit: Int = maxDiscoveredApps,
        fileManager: FileManager = .default
    ) -> [QuickActionsAppEntry] {
        guard limit > 0 else { return [] }
        let roots = directories ?? defaultApplicationDirectories(fileManager: fileManager)

        var collected: [QuickActionsAppEntry] = []
        var seenResolvedPaths = Set<String>()
        var seenBundleIDs = Set<String>()
        var scannedBundles = 0

        for root in roots {
            if Task.isCancelled || scannedBundles >= maxScannedBundles { break }
            var rootIsDir: ObjCBool = false
            guard fileManager.fileExists(atPath: root.path, isDirectory: &rootIsDir), rootIsDir.boolValue else {
                continue
            }

            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.localizedNameKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for _ in 0..<maxScannedEntriesPerRoot {
                guard !Task.isCancelled, scannedBundles < maxScannedBundles,
                      let candidate = enumerator.nextObject() as? URL else { break }

                if enumerator.level > maxDirectoryDepth {
                    enumerator.skipDescendants()
                    continue
                }

                guard candidate.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
                    continue
                }

                // Follow symlinks (e.g. /Applications/Safari.app -> Preboot Cryptex) via fileExists(atPath:isDirectory:),
                // while preventing descent into symlinked .app directories that FileManager may not mark as packages.
                enumerator.skipDescendants()
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else {
                    continue
                }

                scannedBundles += 1
                let resolvedPath = candidate.resolvingSymlinksInPath().standardizedFileURL.path
                guard seenResolvedPaths.insert(resolvedPath).inserted else { continue }

                guard let bundle = Bundle(url: candidate),
                      bundle.bundleIdentifier != nil || bundle.executableURL != nil,
                      !isBackgroundOnly(bundle: bundle) else { continue }

                let bundleID = bundle.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let loweredID = bundleID?.lowercased(), !loweredID.isEmpty {
                    guard seenBundleIDs.insert(loweredID).inserted else { continue }
                }

                let stem = candidate.deletingPathExtension().lastPathComponent
                let localized = (try? candidate.resourceValues(forKeys: [.localizedNameKey]).localizedName)
                    .map(strippingAppExtension)
                let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    .map(strippingAppExtension)
                let bundleName = (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    .map(strippingAppExtension)

                let title = [localized, displayName, stem, bundleName]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first { !$0.isEmpty } ?? stem

                var aliases: [String] = []
                for candidateTerm in [stem, localized, displayName, bundleName] {
                    if let term = candidateTerm?.trimmingCharacters(in: .whitespacesAndNewlines), !term.isEmpty {
                        aliases.append(term)
                    }
                }
                if let bundleID, let tail = bundleID.split(separator: ".").last {
                    aliases.append(String(tail))
                }

                collected.append(
                    QuickActionsAppEntry(
                        url: candidate.standardizedFileURL,
                        title: title,
                        bundleStem: stem,
                        locationLabel: locationCategory(for: candidate),
                        bundleIdentifier: bundleID,
                        searchTerms: aliases
                    )
                )
            }
        }

        collected.sort { lhs, rhs in
            let order = lhs.title.localizedStandardCompare(rhs.title)
            if order != .orderedSame { return order == .orderedAscending }
            return lhs.url.path < rhs.url.path
        }

        if collected.count > limit {
            return Array(collected.prefix(limit))
        }
        return collected
    }

    /// Produces the bounded list of items for either empty-query browsing or active filtering.
    /// Pure function: never launches apps or mutates external state.
    static func items(
        query: String,
        applications: [QuickActionsAppEntry],
        browseAppLimit: Int = defaultBrowseAppLimit,
        searchResultLimit: Int = defaultSearchResultLimit
    ) -> [QuickActionItem] {
        let appItems = applications.map(makeAppItem(from:))
        return filterItems(
            query: query,
            builtIns: builtInItems,
            appItems: appItems,
            browseAppLimit: browseAppLimit,
            searchResultLimit: searchResultLimit
        )
    }

    /// Filters pre-built `QuickActionItem` arrays so repeated keystrokes avoid rebuilding `QuickActionItem` metadata.
    static func filterItems(
        query: String,
        builtIns: [QuickActionItem] = builtInItems,
        appItems: [QuickActionItem],
        browseAppLimit: Int = defaultBrowseAppLimit,
        searchResultLimit: Int = defaultSearchResultLimit
    ) -> [QuickActionItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let cappedApps = browseAppLimit > 0 ? Array(appItems.prefix(browseAppLimit)) : []
            return builtIns + cappedApps
        }

        let tokens = trimmed
            .split(whereSeparator: \.isWhitespace)
            .map { normalize(String($0)) }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else {
            let cappedApps = browseAppLimit > 0 ? Array(appItems.prefix(browseAppLimit)) : []
            return builtIns + cappedApps
        }

        let allCandidates = builtIns + appItems
        var scored: [(item: QuickActionItem, score: Int, originalIndex: Int)] = []
        scored.reserveCapacity(min(allCandidates.count, searchResultLimit * 2))

        for (index, candidate) in allCandidates.enumerated() {
            if let matchScore = score(item: candidate, queryTokens: tokens) {
                scored.append((candidate, matchScore, index))
            }
        }

        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.item.sourceKind != rhs.item.sourceKind {
                return lhs.item.sourceKind == .builtIn
            }
            if lhs.item.title.count != rhs.item.title.count {
                return lhs.item.title.count < rhs.item.title.count
            }
            let cmp = lhs.item.title.localizedStandardCompare(rhs.item.title)
            if cmp != .orderedSame { return cmp == .orderedAscending }
            return lhs.originalIndex < rhs.originalIndex
        }

        let limit = max(1, searchResultLimit)
        return scored.prefix(limit).map(\.item)
    }

    /// Steps keyboard selection up (`delta < 0`) or down (`delta > 0`), clamped cleanly to the list bounds.
    static func steppedSelection(
        current: QuickActionItem.ID?,
        in items: [QuickActionItem],
        delta: Int
    ) -> QuickActionItem.ID? {
        guard !items.isEmpty else { return nil }
        guard let current, let currentIndex = items.firstIndex(where: { $0.id == current }) else {
            return delta < 0 ? items.last?.id : items.first?.id
        }
        let nextIndex = min(max(0, currentIndex + delta), items.count - 1)
        return items[nextIndex].id
    }

    /// Reconciles selection when results update:
    /// - `resetToFirst == true` (user edited query): selects the top-ranked result.
    /// - `resetToFirst == false` (async app list arrived): preserves an existing valid selection, else selects first.
    static func reconciledSelection(
        current: QuickActionItem.ID?,
        in items: [QuickActionItem],
        resetToFirst: Bool
    ) -> QuickActionItem.ID? {
        guard !items.isEmpty else { return nil }
        if !resetToFirst, let current, items.contains(where: { $0.id == current }) {
            return current
        }
        return items.first?.id
    }

    // MARK: - Scoring & Normalization Helpers

    fileprivate static func normalize(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
    }

    fileprivate static func wordTokens(from text: String) -> [String] {
        // Split camelCase ("NeteaseMusic" -> ["Netease", "Music"]) and non-alphanumeric separators.
        var separated = ""
        separated.reserveCapacity(text.count + 4)
        var previousWasLower = false
        for scalar in text.unicodeScalars {
            let isUpper = CharacterSet.uppercaseLetters.contains(scalar)
            let isLower = CharacterSet.lowercaseLetters.contains(scalar)
            if isUpper && previousWasLower {
                separated.append(" ")
            }
            if CharacterSet.alphanumerics.contains(scalar) {
                separated.unicodeScalars.append(scalar)
            } else {
                separated.append(" ")
            }
            previousWasLower = isLower
        }
        return separated
            .split(whereSeparator: \.isWhitespace)
            .map { normalize(String($0)) }
            .filter { !$0.isEmpty }
    }

    private static func score(item: QuickActionItem, queryTokens: [String]) -> Int? {
        var total = item.sourceKind == .builtIn ? 18 : 0
        for token in queryTokens {
            guard let tokenScore = scoreSingleToken(token, against: item) else {
                return nil
            }
            total += tokenScore
        }
        return total
    }

    private static func scoreSingleToken(_ token: String, against item: QuickActionItem) -> Int? {
        if item.normalizedTitle == token {
            return 1_000
        }
        if item.normalizedTitle.hasPrefix(token) {
            return 780 - min(80, max(0, item.normalizedTitle.count - token.count))
        }
        if item.titleWords.contains(where: { $0 == token }) {
            return 660
        }
        if item.normalizedTerms.contains(where: { $0 == token }) {
            return 640
        }
        if item.titleWords.contains(where: { $0.hasPrefix(token) }) {
            return 560
        }
        if item.normalizedTerms.contains(where: { $0.hasPrefix(token) }) {
            return 520
        }
        if token.count >= 2, !item.acronym.isEmpty, item.acronym.hasPrefix(token) {
            return 460
        }
        if item.normalizedTitle.contains(token) {
            return 380
        }
        if item.normalizedTerms.contains(where: { $0.contains(token) }) {
            return 280
        }
        if item.normalizedSubtitle.contains(token) {
            return 190
        }
        if token.count >= 2, isASCIIToken(token),
           item.normalizedTerms.contains(where: { isSubsequence(token, of: $0) }) {
            return 120
        }
        return nil
    }

    private static func isASCIIToken(_ token: String) -> Bool {
        token.unicodeScalars.allSatisfy { $0.isASCII && CharacterSet.alphanumerics.contains($0) }
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        guard needle.count <= haystack.count else { return false }
        var needleIterator = needle.makeIterator()
        guard var target = needleIterator.next() else { return true }
        for char in haystack where char == target {
            if let next = needleIterator.next() {
                target = next
            } else {
                return true
            }
        }
        return false
    }

    private static func strippingAppExtension(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasSuffix(".app"), trimmed.count > 4 {
            return String(trimmed.dropLast(4))
        }
        return trimmed
    }

    private static func isBackgroundOnly(bundle: Bundle) -> Bool {
        guard let raw = bundle.object(forInfoDictionaryKey: "LSBackgroundOnly") else { return false }
        if let boolValue = raw as? Bool { return boolValue }
        if let numberValue = raw as? NSNumber { return numberValue.boolValue }
        if let stringValue = raw as? String {
            return stringValue == "1" || stringValue.caseInsensitiveCompare("true") == .orderedSame
        }
        return false
    }

    private static func locationCategory(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        if path.contains("/Utilities/") {
            return "实用工具"
        }
        if path.hasPrefix("/System/Applications/") {
            return "系统应用"
        }
        if path.hasPrefix(NSHomeDirectory() + "/Applications/") {
            return "个人应用"
        }
        return "应用程序"
    }
}
