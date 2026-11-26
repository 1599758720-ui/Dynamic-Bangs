import SwiftUI

/// Artwork owns its animation clock; playback/FFT ticks never rebuild the workbench.
struct MusicArtwork: View {
    let url: URL?
    let playing: Bool
    var size: CGFloat = 56
    var appearance: MusicAppearance = .vinyl
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var accumulated: Double = 0
    @State private var startedAt: Date?

    var body: some View {
        Group {
            if appearance == .vinyl {
                TimelineView(.animation(minimumInterval: 1.0 / 24, paused: startedAt == nil || reduceMotion)) { context in
                    disc.rotationEffect(.degrees(angle(at: context.date)))
                }
            } else {
                cover.clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.18).stroke(.white.opacity(0.14), lineWidth: 0.5))
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.35), radius: size * 0.09, y: size * 0.04)
        .accessibilityHidden(true)
        .onAppear { updateClock() }
        .onChange(of: playing) { _, _ in updateClock() }
        .onChange(of: reduceMotion) { _, _ in updateClock() }
        .onChange(of: appearance) { _, _ in updateClock() }
        .onDisappear { accumulate() }
    }
    private var disc: some View {
        ZStack {
            Circle().fill(Color(white: 0.035))
            Circle().fill(AngularGradient(colors: [.white.opacity(0.20), .clear, .white.opacity(0.04), .clear, .white.opacity(0.20)], center: .center))
            Canvas { context, bounds in
                for fraction in stride(from: 0.62, through: 0.94, by: 0.055) {
                    let diameter = bounds.width * fraction
                    let rect = CGRect(x: (bounds.width - diameter) / 2, y: (bounds.height - diameter) / 2, width: diameter, height: diameter)
                    context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.13)), lineWidth: 0.5)
                }
            }
            cover.frame(width: size * 0.56, height: size * 0.56).clipShape(Circle())
                .overlay(Circle().stroke(.black.opacity(0.5), lineWidth: size * 0.025))
            Circle().fill(.black).frame(width: max(2, size * 0.07), height: max(2, size * 0.07))
                .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 0.7))
        }.overlay(Circle().stroke(.white.opacity(0.15), lineWidth: 0.7))
    }
    private var cover: some View {
        AsyncImage(url: url, transaction: Transaction(animation: reduceMotion ? nil : .easeOut(duration: 0.18))) { phase in
            if let image = phase.image { image.resizable().scaledToFill() }
            else {
                Rectangle().fill(LinearGradient(colors: [Color(white: 0.19), Color(white: 0.09)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Image(systemName: "music.note").font(.system(size: size * 0.22, weight: .medium)).foregroundStyle(.white.opacity(0.8)))
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
    }
    private func angle(at date: Date) -> Double {
        accumulated + (startedAt.map { max(0, date.timeIntervalSince($0)) * 18 } ?? 0)
    }
    private func accumulate() { accumulated = angle(at: Date()).truncatingRemainder(dividingBy: 360); startedAt = nil }
    private func updateClock() {
        accumulate()
        if playing && !reduceMotion && appearance == .vinyl { startedAt = Date() }
    }
}
