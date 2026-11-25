import AppKit
import Intents
import SwiftUI

/// The lock screen exposes only the lock state. Desktop content is never mirrored there.
final class SystemStatus: ObservableObject {
    static let shared = SystemStatus()
    @Published private(set) var isLocked = false
    @Published private(set) var focusActive: Bool?
    @Published private(set) var focusAuthorization = INFocusStatusAuthorizationStatus.notDetermined
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var started = false
    private var awake = true
    private weak var activities: ActivityManager?

    func start(activities: ActivityManager) {
        guard !started else { return }
        started = true
        self.activities = activities
        isLocked = Self.readLocked()
        let center = DistributedNotificationCenter.default()
        observe("com.apple.screenIsLocked", center: center) { $0.setLocked(true) }
        observe("com.apple.screenIsUnlocked", center: center) { $0.setLocked(false) }
        observe("_NSDoNotDisturbEnabledNotification", center: center) { $0.applyFocus(true, announce: true) }
        observe("_NSDoNotDisturbDisabledNotification", center: center) { $0.applyFocus(false, announce: true) }
        observe("com.apple.donotdisturb.state.changed", center: center) { $0.refreshFocus() }
        refreshFocus()
        startTimer()
    }
    private func observe(_ name: String, center: DistributedNotificationCenter, action: @escaping (SystemStatus) -> Void) {
        observers.append(center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
            if let self { action(self) }
        })
    }
    func stop() {
        observers.forEach(DistributedNotificationCenter.default().removeObserver)
        observers.removeAll(); timer?.invalidate(); timer = nil; started = false
    }
    func setScreensAwake(_ value: Bool) {
        awake = value
        timer?.invalidate(); timer = nil
        if value { setLocked(Self.readLocked()); refreshFocus(); startTimer() }
    }
    private func startTimer() {
        guard awake, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refreshFocus() }
        timer?.tolerance = 1
    }
    func requestFocusAccess() {
        if INFocusStatusCenter.default.authorizationStatus == .denied {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Focus") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        INFocusStatusCenter.default.requestAuthorization { [weak self] _ in
            DispatchQueue.main.async { self?.refreshFocus() }
        }
    }
    func refreshFocus() {
        let center = INFocusStatusCenter.default
        let status = center.authorizationStatus
        if focusAuthorization != status { focusAuthorization = status }
        if status == .authorized, let value = center.focusStatus.isFocused { applyFocus(value) }
    }
    private func applyFocus(_ active: Bool, announce: Bool = false) {
        guard focusActive != active else { return }
        let previouslyKnown = focusActive != nil
        focusActive = active
        guard previouslyKnown || announce, !isLocked else { return }
        presentFocus(active)
    }
    private func presentFocus(_ active: Bool) {
        guard WidgetStore.shared.layout.systemStatusEnabled else { return }
        activities?.present(NotchActivity(kind: .focus, priority: 5, icon: active ? "moon.fill" : "moon",
            tint: active ? .purple : .white, title: active ? "专注已开启" : "专注已关闭", autoDismiss: 2.5))
    }
    private func setLocked(_ value: Bool) {
        guard isLocked != value else { return }
        var transaction = Transaction(animation: value || Motion.isReduced ? nil : NotchStyle.spring)
        transaction.disablesAnimations = value
        // Strip desktop content immediately before the panel moves above the login window.
        withTransaction(transaction) { isLocked = value }
        if !value {
            refreshFocus()
            if WidgetStore.shared.layout.systemStatusEnabled {
                activities?.present(NotchActivity(kind: .unlocked, priority: 6, icon: "lock.open.fill", tint: .green,
                    title: "已解锁", autoDismiss: 2))
            }
        }
    }
    func preview() {
        activities?.present(NotchActivity(kind: .focus, priority: 5, icon: "moon.fill", tint: .purple,
            title: "专注提示预览", autoDismiss: 2.5))
    }
    static func readLocked() -> Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return (session?["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue ?? false
    }
}
