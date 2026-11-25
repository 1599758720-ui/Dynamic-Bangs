import AppKit
import SwiftUI

struct NotchSettings: View {
    @ObservedObject var settings: UserSettings
    @ObservedObject private var widgets = WidgetStore.shared
    @State private var axGranted = MenuBarOverlapMonitor.hasAccessibilityPermission

    private var currentArea: MenuBarSafeArea? {
        ScreenManager.targetScreen().map(ScreenManager.safeArea(for:))
    }

    var body: some View {
        Form {
            Section("实体刘海贴合与菜单栏避让") {
                if let notch = currentArea?.notch {
                    Text("已检测实体刘海（宽 \(Int(notch.width)) 点，菜单栏高 \(Int(ScreenManager.menuBarHeight)) 点）")
                } else {
                    Text("当前屏幕无实体刘海（菜单栏高 \(Int(ScreenManager.menuBarHeight)) 点，悬浮于菜单栏下方）")
                }
                Stepper("收起高度微调：\(Int(settings.notchHeightExtra)) 点", value: $settings.notchHeightExtra, in: -1...6, step: 1)
                LabeledContent("右侧状态图标避让", value: "已启用（自动检测）")
                LabeledContent("左侧应用菜单避让", value: axGranted ? "已启用（辅助功能已授权）" : "精简宽度（授权后可按应用菜单精确避让）")
                if !axGranted {
                    Button("开启辅助功能权限…") {
                        MenuBarOverlapMonitor.requestAccessibilityPermission()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            axGranted = MenuBarOverlapMonitor.hasAccessibilityPermission
                        }
                    }
                }
                Text("收起态贴合实体刘海左右，与菜单栏同高；展开时使用菜单栏下方空间。两侧拥挤时会自动精简或让位，优先保住系统状态图标和应用菜单。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("组件与缩略显示") {
                Button("配置组件、顺序与左右缩略信息…") { WidgetPreferencesWindow.shared.show() }
                Text("默认固定贴合在实体刘海左右居中位置。双击展开工作台，按 ⌥⌘K 打开快速搜索。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("已显示：" + widgets.layout.widgets.map(\.title).joined(separator: "、"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle(String(localized: "settings.liveActivities", defaultValue: "Live Activities (Laden, Datei empfangen)"), isOn: $settings.liveActivitiesEnabled)
                Toggle(String(localized: "settings.audioRoute", defaultValue: "Audio-Ausgabe-Wechsel (AirPods, Lautsprecher)"), isOn: $settings.audioRouteActivityEnabled)
                    .disabled(!settings.liveActivitiesEnabled)
                Toggle(String(localized: "settings.hud", defaultValue: "HUD-Ersatz (Lautstärke/Helligkeit)"), isOn: $settings.hudEnabled)
                Toggle(String(localized: "settings.suppressOSD", defaultValue: "Lautstärke & Helligkeit nur in der Notch (Bedienungshilfen nötig)"), isOn: $settings.suppressSystemOSD)
                    .disabled(!settings.hudEnabled)
            } header: {
                Text(String(localized: "settings.notch.display", defaultValue: "Anzeige"))
            } footer: {
                Text(String(localized: "settings.audioRoute.hint", defaultValue: "macOS zeigt beim Verbinden von AirPods eine eigene Einblendung. Schalte den Ausgabe-Wechsel ab, wenn du sie nicht doppelt sehen willst."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button(String(localized: "settings.notch.resetPlacement", defaultValue: "Notch mittig nach oben")) {
                    NotificationCenter.default.post(name: .notchResetPlacement, object: nil)
                }
            } header: {
                Text(String(localized: "settings.notch.placement", defaultValue: "Position"))
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { axGranted = MenuBarOverlapMonitor.hasAccessibilityPermission }
    }

    private func tabBinding(_ tab: NotchViewModel.Tab) -> Binding<Bool> {
        Binding(
            get: { settings.isTabEnabled(tab) },
            set: { settings.setTab(tab, enabled: $0) }
        )
    }
}
