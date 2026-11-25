import AppKit
import SwiftUI

/// A pointing-hand cursor while hovering, for clickable non-button surfaces.
struct PointingHandCursor: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        content.onHover { inside in
            if enabled, inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

extension View {
    func pointingHandCursor(enabled: Bool) -> some View {
        modifier(PointingHandCursor(enabled: enabled))
    }
}

/// Transport button with a hover highlight (visible when expanded).
struct ControlButton: View {
    let systemName: String
    var size: CGFloat
    var diameter: CGFloat = 32
    var color: Color = .white
    var filled = false
    /// Spoken name. Required rather than optional on purpose: a `Button` whose
    /// label is only an `Image(systemName:)` announces nothing at all to
    /// VoiceOver, so every transport control here was silent, and an argument you
    /// can forget is an argument that gets forgotten.
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
        }
        .buttonStyle(NotchButtonStyle(tint: color, filled: filled, shape: .circle(diameter)))
        .accessibilityLabel(label)
        .help(label)
    }
}
