import SwiftUI

extension DashboardWidget {
    var tint: Color {
        switch self { case .music: return .pink; case .timer: return .orange
        case .tasks: return .mint; case .system: return .green }
    }
}

struct UsageRing: View {
    let value: Double?
    let color: Color
    var lineWidth: CGFloat = 3
    var endColor: Color?
    var glowing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: lineWidth)
            if let value, value > 0 {
                Circle().trim(from: 0, to: min(1, value))
                    .stroke(AngularGradient(colors: [color, endColor ?? color], center: .center),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .padding(lineWidth / 2)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: glowing ? color.opacity(0.40) : .clear, radius: 4)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: value)
        .accessibilityHidden(true)
    }
}

struct CompactSystemRings: View {
    @ObservedObject private var metrics = SystemMetrics.shared
    var body: some View {
        ZStack {
            UsageRing(value: metrics.cpu, color: .green, lineWidth: 2.5).frame(width: 21, height: 21)
            UsageRing(value: metrics.memory?.fraction, color: .yellow, lineWidth: 2.5).frame(width: 13, height: 13)
        }
        .frame(width: 26, height: 26)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("CPU 与内存双环")
        .accessibilityValue("CPU \(percentage(metrics.cpu))，内存 \(percentage(metrics.memory?.fraction))")
        .help("外圈 CPU \(percentage(metrics.cpu)) · 内圈内存 \(percentage(metrics.memory?.fraction))")
    }
}

struct CompactBattery: View {
    @ObservedObject private var metrics = SystemMetrics.shared
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: batterySymbol(metrics.battery))
                .foregroundStyle(metrics.battery?.charging == true ? .green : .white)
            Text(percentage(metrics.battery?.fraction)).monospacedDigit()
        }
        .font(.system(size: 11, weight: .medium))
        .accessibilityElement(children: .combine).accessibilityLabel("电池")
    }
}

struct SystemWidgetContent: View {
    @ObservedObject private var metrics = SystemMetrics.shared
    private let emerald = Color(red: 0.32, green: 0.88, blue: 0.57)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    UsageRing(value: metrics.cpu, color: emerald, lineWidth: 5.5)
                        .frame(width: 68, height: 68)
                    UsageRing(value: metrics.memory?.fraction, color: NotchStyle.amber, lineWidth: 5.5)
                        .frame(width: 48, height: 48)
                }
                VStack(alignment: .leading, spacing: 6) {
                    reading("CPU", value: percentage(metrics.cpu), color: emerald)
                    reading("内存", value: percentage(metrics.memory?.fraction), color: NotchStyle.amber)
                    Text(memoryUsage)
                        .font(.system(size: 9)).monospacedDigit()
                        .foregroundStyle(NotchStyle.secondary).lineLimit(1).minimumScaleFactor(0.8)
                        .help("内存按活动、固定与压缩内存估算。")
                }
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: 6) {
                Image(systemName: batterySymbol(metrics.battery))
                    .foregroundStyle(metrics.battery?.charging == true ? emerald : .white)
                if let battery = metrics.battery {
                    Text(percentage(battery.fraction)).fontWeight(.semibold).monospacedDigit()
                    Spacer(minLength: 2)
                    Text(battery.charging ? "充电中" : (battery.onAC ? "已接电源" : "电池"))
                        .foregroundStyle(NotchStyle.secondary)
                } else {
                    Text("未检测到电池").foregroundStyle(NotchStyle.secondary)
                    Spacer(minLength: 2)
                }
            }
            .font(.system(size: 10))
            .padding(.horizontal, 10).frame(height: 28)
            .background(.white.opacity(0.095), in: Capsule())
            .accessibilityElement(children: .combine)
        }
    }

    private var memoryUsage: String {
        guard let memory = metrics.memory else { return "正在读取…" }
        let bytesPerGB = 1_073_741_824.0
        let used = (Double(memory.used) / bytesPerGB).formatted(.number.precision(.fractionLength(1)))
        let total = (Double(memory.total) / bytesPerGB).formatted(.number.precision(.fractionLength(0...1)))
        return "\(used) / \(total) GB"
    }

    private func reading(_ name: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 4, height: 4)
            Text(name).foregroundStyle(NotchStyle.secondary).fixedSize()
            Spacer(minLength: 1)
            Text(value).monospacedDigit().fontWeight(.bold).fixedSize()
        }
        .font(.system(size: 11))
        .accessibilityElement(children: .combine)
    }
}

private func batterySymbol(_ battery: BatteryReading?) -> String {
    guard let battery else { return "battery.0percent" }
    if battery.charging { return "battery.100percent.bolt" }
    switch battery.fraction {
    case 0.875...: return "battery.100percent"
    case 0.625...: return "battery.75percent"
    case 0.375...: return "battery.50percent"
    case 0.125...: return "battery.25percent"
    default: return "battery.0percent"
    }
}

func percentage(_ value: Double?) -> String {
    value.map { "\(Int(($0 * 100).rounded()))%" } ?? "—"
}
