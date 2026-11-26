import AppKit
import SwiftUI

/// Quick-search surface for Côte d'OS inside the notch workbench.
///
/// Exposes built-in workbench destinations alongside a bounded, off-main index of
/// local macOS applications. Selecting an item via Return or pointer click reports
/// the chosen `QuickAction` through `onSelect`; filtering never launches apps.
struct QuickActionsView: View {
    let onSelect: (QuickAction) -> Void
    private let customAppLoader: (@Sendable () async -> [QuickActionsAppEntry])?

    @State private var query = ""
    @State private var appItems: [QuickActionItem] = []
    @State private var displayedItems: [QuickActionItem] = Self.workbenchItems
    @State private var isLoadingApps = true
    @State private var selectedID: QuickActionItem.ID? = QuickActionsCatalog.builtInItems.first?.id
    @State private var keyboardScrollID: QuickActionItem.ID?
    @State private var isMounted = false
    @FocusState private var isSearchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(onSelect: @escaping (QuickAction) -> Void) {
        self.onSelect = onSelect
        self.customAppLoader = nil
    }

    init(
        customAppLoader: @escaping @Sendable () async -> [QuickActionsAppEntry],
        onSelect: @escaping (QuickAction) -> Void
    ) {
        self.onSelect = onSelect
        self.customAppLoader = customAppLoader
    }

    private static var workbenchItems: [QuickActionItem] {
        QuickActionsCatalog.builtInItems + QuickActionsCatalog.availableSystemTools
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 7) {
            searchBar
            resultsBody
            footerBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .defaultFocus($isSearchFocused, true)
        .onAppear {
            isMounted = true
            requestInitialFocus()
        }
        .onDisappear {
            isMounted = false
        }
        .task {
            await loadApplicationsIfNeeded()
        }
        .onChange(of: query) { _, newQuery in
            applyResults(for: newQuery, appItems: appItems, resetSelectionToFirst: true)
        }
        .onKeyPress(keys: [.upArrow, .downArrow], phases: [.down, .repeat]) { keyPress in
            guard !Self.hasMarkedTextInKeyWindow() else { return .ignored }
            let delta = keyPress.key == .downArrow ? 1 : -1
            stepSelection(by: delta)
            return .handled
        }
        .onKeyPress(.return) {
            guard !isSearchFocused, !Self.hasMarkedTextInKeyWindow() else { return .ignored }
            activateCurrentSelection()
            return .handled
        }
    }

    // MARK: - Subviews

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(NotchStyle.Typography.cardSymbol)
                .foregroundStyle(isSearchFocused ? NotchStyle.controlInk.opacity(0.92) : NotchStyle.secondary)
                .accessibilityHidden(true)

            TextField("搜索工作台功能或本机应用…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(NotchStyle.primaryText)
                .focused($isSearchFocused)
                .accessibilityLabel("快速搜索")
                .accessibilityHint("输入名称筛选工作台功能与本机应用，按上下方向键选择，按回车打开")
                .onSubmit {
                    activateCurrentSelection()
                }

            if isLoadingApps && !displayedItems.isEmpty {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel("正在读取本机应用")
            }

            if !query.isEmpty {
                Button(action: clearQuery) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12.5))
                        .foregroundStyle(NotchStyle.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空搜索")
                .help("清空搜索内容")
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 36)
        .background(NotchStyle.controlInk.opacity(isSearchFocused ? NotchStyle.Opacity.hover : NotchStyle.Opacity.control),
                    in: RoundedRectangle(cornerRadius: NotchStyle.Radius.control))
        .overlay {
            if isSearchFocused {
                RoundedRectangle(cornerRadius: NotchStyle.Radius.control)
                    .strokeBorder(NotchStyle.systemBlue.opacity(0.58), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .animation(reduceMotion ? nil : NotchStyle.Motion.hover, value: isSearchFocused)
    }

    @ViewBuilder
    private var resultsBody: some View {
        if displayedItems.isEmpty {
            if isLoadingApps {
                loadingStateView
            } else {
                emptyResultsView
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 5) {
                        ForEach(displayedItems) { item in
                            QuickActionRowView(
                                item: item,
                                isSelected: selectedID == item.id,
                                onActivate: activateItem
                            )
                            .id(item.id)
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.automatic)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: keyboardScrollID) { _, targetID in
                    guard let targetID else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                        proxy.scrollTo(targetID)
                    }
                }
            }
        }
    }

    private var loadingStateView: some View {
        VStack(spacing: 7) {
            ProgressView()
                .controlSize(.small)
            Text("正在扫描本机应用…")
                .font(.system(size: 12))
                .foregroundStyle(NotchStyle.controlInk.opacity(0.86))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var emptyResultsView: some View {
        VStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(NotchStyle.tertiary)
                .accessibilityHidden(true)
            Text("未找到“\(trimmedQuery)”")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(NotchStyle.controlInk.opacity(0.88))
                .lineLimit(1)
            Text("可输入“音乐”“番茄钟”“速记”或已安装应用名称")
                .font(.system(size: 10.5))
                .foregroundStyle(NotchStyle.secondary)
                .lineLimit(1)
            Button("清空搜索", action: clearQuery)
                .buttonStyle(NotchButtonStyle())
                .font(.system(size: 10.5))
                .padding(.top, 2)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var footerBar: some View {
        if !displayedItems.isEmpty {
            HStack {
                if !trimmedQuery.isEmpty {
                    Text("显示 \(displayedItems.count) 项")
                }
                Spacer(minLength: 6)
                Text("↑↓ 选择 · ↩ 打开")
                    .accessibilityHidden(true)
            }
            .font(.system(size: 10))
            .foregroundStyle(NotchStyle.secondary)
            .frame(height: 15)
        }
    }

    // MARK: - Actions & Focus

    private func requestInitialFocus() {
        if !isSearchFocused {
            isSearchFocused = true
        }
        DispatchQueue.main.async {
            guard isMounted, !isSearchFocused else { return }
            isSearchFocused = true
        }
    }

    private func clearQuery() {
        query = ""
        isSearchFocused = true
    }

    private func stepSelection(by delta: Int) {
        guard let nextID = QuickActionsCatalog.steppedSelection(
            current: selectedID,
            in: displayedItems,
            delta: delta
        ) else { return }
        selectedID = nextID
        keyboardScrollID = nextID
    }

    private func activateCurrentSelection() {
        guard !displayedItems.isEmpty else { return }
        let chosen = displayedItems.first(where: { $0.id == selectedID }) ?? displayedItems[0]
        selectedID = chosen.id
        onSelect(chosen.action)
    }

    private func activateItem(_ item: QuickActionItem) {
        selectedID = item.id
        onSelect(item.action)
    }

    private func applyResults(
        for currentQuery: String,
        appItems: [QuickActionItem],
        resetSelectionToFirst: Bool
    ) {
        let builtIns = Self.workbenchItems
        let builtInIDs = Set(builtIns.map(\.id))
        let updated = QuickActionsCatalog.filterItems(
            query: currentQuery, builtIns: builtIns, appItems: appItems.filter { !builtInIDs.contains($0.id) }
        )
        displayedItems = updated
        let reconciled = QuickActionsCatalog.reconciledSelection(
            current: selectedID,
            in: updated,
            resetToFirst: resetSelectionToFirst
        )
        selectedID = reconciled
        if resetSelectionToFirst {
            keyboardScrollID = reconciled
        }
    }

    private func loadApplicationsIfNeeded() async {
        if let customAppLoader {
            isLoadingApps = true
            let entries = await customAppLoader()
            guard !Task.isCancelled else { return }
            let mapped = entries.map(QuickActionsCatalog.makeAppItem(from:))
            appItems = mapped
            isLoadingApps = false
            applyResults(for: query, appItems: mapped, resetSelectionToFirst: false)
            return
        }

        if let cached = QuickActionsAppStore.shared.cachedAppItems, !QuickActionsAppStore.shared.isStale {
            appItems = cached
            isLoadingApps = false
            applyResults(for: query, appItems: cached, resetSelectionToFirst: false)
            return
        }

        if let stale = QuickActionsAppStore.shared.cachedAppItems {
            appItems = stale
            applyResults(for: query, appItems: stale, resetSelectionToFirst: false)
        }

        isLoadingApps = true
        let fresh = await QuickActionsAppStore.shared.loadAppItems()
        guard !Task.isCancelled else { return }
        appItems = fresh
        isLoadingApps = false
        applyResults(for: query, appItems: fresh, resetSelectionToFirst: false)
    }

    /// Preserves native Chinese/Japanese/Korean IME candidate arrow & Return handling while marked text is active.
    private static func hasMarkedTextInKeyWindow() -> Bool {
        guard let textView = NSApp?.keyWindow?.firstResponder as? NSTextView else {
            return false
        }
        return textView.hasMarkedText()
    }
}

// MARK: - Row View (Isolated Invalidation Boundary)

private struct QuickActionRowView: View {
    let item: QuickActionItem
    let isSelected: Bool
    let onActivate: (QuickActionItem) -> Void

    var body: some View {
        Button {
            onActivate(item)
        } label: {
            HStack(spacing: 10) {
                QuickActionLeadingIcon(item: item, isSelected: isSelected)

                VStack(alignment: .leading, spacing: 1.5) {
                    Text(item.title)
                        .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(NotchStyle.primaryText)
                        .lineLimit(1)
                    Text(item.subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(isSelected ? NotchStyle.controlInk.opacity(0.76) : NotchStyle.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                HStack(spacing: 4) {
                    Text(item.badge)
                        .font(.system(size: 10))
                    if isSelected {
                        Image(systemName: "return")
                            .font(.system(size: 9, weight: .semibold))
                    }
                }
                .foregroundStyle(isSelected ? NotchStyle.controlInk.opacity(0.90) : NotchStyle.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        }
        .buttonStyle(QuickActionRowButtonStyle(isSelected: isSelected))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.title)，\(item.subtitle)")
        .accessibilityValue(item.badge)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(item.tooltip)
    }
}

private struct QuickActionRowButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        StyledRow(configuration: configuration, isSelected: isSelected)
    }

    private struct StyledRow: View {
        let configuration: Configuration
        let isSelected: Bool
        @State private var isHovering = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
        @Environment(\.colorSchemeContrast) private var contrast

        var body: some View {
            let emphasized = differentiateWithoutColor || contrast == .increased
            let shape = RoundedRectangle(cornerRadius: NotchStyle.Radius.control)
            configuration.label
                .background {
                    if isSelected {
                        shape.fill(NotchStyle.controlInk.opacity(emphasized ? 0.20 : NotchStyle.Opacity.selected))
                    } else if isHovering || configuration.isPressed {
                        shape.fill(NotchStyle.controlInk.opacity(configuration.isPressed
                            ? NotchStyle.Opacity.pressed : NotchStyle.Opacity.hover))
                    }
                }
                .overlay {
                    if isSelected && emphasized {
                        shape.strokeBorder(NotchStyle.hairline(.increased), lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(shape)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.992 : 1)
                .onHover { isHovering = $0 }
                .animation(reduceMotion ? nil : NotchStyle.Motion.hover, value: isHovering)
                .animation(reduceMotion ? nil : NotchStyle.spring, value: configuration.isPressed)
        }
    }
}

private struct QuickActionLeadingIcon: View {
    let item: QuickActionItem
    let isSelected: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if let appURL = item.appURL {
            QuickActionAppIconView(url: appURL)
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
        } else {
            Image(systemName: item.symbol)
                .font(NotchStyle.Typography.cardSymbol)
                .foregroundStyle(isSelected ? NotchStyle.primaryText : NotchStyle.headerSymbol(contrast))
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)
        }
    }
}

private struct QuickActionAppIconView: View {
    let url: URL
    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let resolved = icon ?? QuickActionsAppStore.shared.cachedIcon(for: url) {
                Image(nsImage: resolved)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NotchStyle.secondary)
                    .frame(width: 26, height: 26)
            }
        }
        .task(id: url) {
            if icon == nil {
                icon = QuickActionsAppStore.shared.icon(for: url)
            }
        }
    }
}

// MARK: - In-Memory App & Icon Cache

@MainActor
private final class QuickActionsAppStore {
    static let shared = QuickActionsAppStore()

    private static let refreshTTL: TimeInterval = 60
    private(set) var cachedAppItems: [QuickActionItem]?
    private var lastLoadedAt: Date?
    private var inFlightTask: Task<[QuickActionItem], Never>?
    private let iconCache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 96
        return cache
    }()

    var isStale: Bool {
        guard let lastLoadedAt else { return true }
        return Date().timeIntervalSince(lastLoadedAt) > Self.refreshTTL
    }

    func loadAppItems() async -> [QuickActionItem] {
        if let existing = inFlightTask {
            return await existing.value
        }
        let task = Task.detached(priority: .utility) { () -> [QuickActionItem] in
            let entries = QuickActionsCatalog.discoverApplications()
            return entries.map(QuickActionsCatalog.makeAppItem(from:))
        }
        inFlightTask = task
        let items = await task.value
        inFlightTask = nil
        if !Task.isCancelled {
            cachedAppItems = items
            lastLoadedAt = Date()
        }
        return items
    }

    func cachedIcon(for url: URL) -> NSImage? {
        iconCache.object(forKey: url as NSURL)
    }

    func icon(for url: URL) -> NSImage {
        let key = url as NSURL
        if let hit = iconCache.object(forKey: key) {
            return hit
        }
        let fetched = NSWorkspace.shared.icon(forFile: url.path)
        fetched.size = NSSize(width: 28, height: 28)
        iconCache.setObject(fetched, forKey: key)
        return fetched
    }
}

#if DEBUG
struct QuickActionsView_Previews: PreviewProvider {
    static var previews: some View {
        let mockApps = [
            QuickActionsAppEntry(
                url: URL(fileURLWithPath: "/Applications/NeteaseMusic.app"),
                title: "网易云音乐",
                bundleStem: "NeteaseMusic",
                locationLabel: "应用程序",
                bundleIdentifier: "com.netease.163music",
                searchTerms: ["网易云音乐", "NeteaseMusic", "163music"]
            ),
            QuickActionsAppEntry(
                url: URL(fileURLWithPath: "/Applications/Obsidian.app"),
                title: "Obsidian",
                bundleStem: "Obsidian",
                locationLabel: "应用程序",
                bundleIdentifier: "md.obsidian",
                searchTerms: ["Obsidian"]
            ),
            QuickActionsAppEntry(
                url: URL(fileURLWithPath: "/Applications/Safari.app"),
                title: "Safari",
                bundleStem: "Safari",
                locationLabel: "应用程序",
                bundleIdentifier: "com.apple.Safari",
                searchTerms: ["Safari"]
            ),
        ]
        QuickActionsView(customAppLoader: { mockApps }) { _ in }
            .padding(16)
            .frame(width: 560, height: 245)
            .background(Color.black)
            .environment(\.colorScheme, .dark)
    }
}
#endif
