import AppKit
import SwiftUI

enum NotchStyle {
    static let primaryText = Color.primary
    static let secondary = Color.secondary
    static let tertiary = Color.secondary.opacity(0.86)
    static let controlInk = Color.primary
    static let controlFill = controlInk.opacity(Opacity.control)
    static let focusOrange = Color(nsColor: .systemOrange)
    static let statusGreen = Color(nsColor: .systemGreen)
    static let taskAccent = adaptive(light: 0x248A3D, dark: 0x30D158)
    static let systemBlue = Color(nsColor: .systemBlue)
    static let memoryAccent = adaptive(light: 0x516E9C, dark: 0x93B3D9)

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 10
        static let cardPadding: CGFloat = 14
        static let railInset: CGFloat = 5
    }

    enum Radius {
        static let panel: CGFloat = 28
        static let card: CGFloat = 22
        static let control: CGFloat = 9

        static func capsule(height: CGFloat) -> CGFloat { height / 2 }
    }

    enum Typography {
        static let control = Font.system(size: 11)
        static let cardTitle = Font.system(size: 12.5, weight: .semibold)
        static let cardSymbol = Font.system(size: 12, weight: .medium)

        static func metric(_ size: CGFloat) -> Font {
            .system(size: size, weight: .semibold, design: .rounded)
        }
    }

    enum Opacity {
        static let control = 0.065
        static let hover = 0.10
        static let pressed = 0.16
        static let selected = 0.13
        static let lightTile = 0.33
        static let darkTile = 0.075
        static let lightArtwork = 0.10
        static let darkArtwork = 0.15
        static let hairline = 0.08
        static let highContrastHairline = 0.28
    }

    static let hairlineWidth: CGFloat = 0.5

    enum Motion {
        static let interactive = Animation.spring(response: 0.26, dampingFraction: 0.88)
        static let surface = Animation.spring(response: 0.31, dampingFraction: 0.91)
        static let layout = Animation.spring(response: 0.30, dampingFraction: 0.80)
        static let hover = Animation.spring(response: 0.20, dampingFraction: 0.93)
    }

    static let spring = Motion.interactive

    static func hairline(_ contrast: ColorSchemeContrast) -> Color {
        controlInk.opacity(contrast == .increased ? Opacity.highContrastHairline : Opacity.hairline)
    }

    static func headerSymbol(_ contrast: ColorSchemeContrast) -> Color {
        contrast == .increased ? primaryText : secondary
    }

    private static func adaptive(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((hex >> 16) & 255) / 255,
                           green: Double((hex >> 8) & 255) / 255,
                           blue: Double(hex & 255) / 255, alpha: 1)
        })
    }
}

struct NotchFloatingMaterial: View {
    let silhouette: RoundedRectangle
    var glassOpacity = 0.42
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if reduceTransparency {
                silhouette.fill(Color(white: scheme == .light ? 0.94 : 0.12))
            } else {
                BehindWindowMaterial(silhouette: silhouette)
                if #available(macOS 26.0, *) {
                    // Keep the AppKit backdrop visible through the native optics.
                    GlassEffectContainer {
                        Color.clear.glassEffect(.regular, in: silhouette)
                    }
                    .opacity(glassOpacity)
                }
            }
        }
        .clipShape(silhouette)
        .overlay {
            if contrast == .increased {
                silhouette.strokeBorder(NotchStyle.hairline(contrast), lineWidth: NotchStyle.hairlineWidth)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private struct BehindWindowMaterial: NSViewRepresentable {
        let silhouette: RoundedRectangle
        @Environment(\.colorScheme) private var scheme
        @Environment(\.colorSchemeContrast) private var contrast

        func makeNSView(context: Context) -> BackdropView {
            let view = BackdropView()
            view.blendingMode = .behindWindow
            view.state = .active
            return view
        }

        func updateNSView(_ view: BackdropView, context: Context) {
            let appearance: NSAppearance.Name
            if contrast == .increased {
                appearance = scheme == .light ? .accessibilityHighContrastAqua : .accessibilityHighContrastDarkAqua
            } else {
                appearance = scheme == .light ? .aqua : .darkAqua
            }
            if view.appearance?.name != appearance {
                view.appearance = NSAppearance(named: appearance)
            }
            if view.silhouette.cornerSize != silhouette.cornerSize {
                view.silhouette = silhouette
                view.maskImage = nil
                view.needsLayout = true
            }
            view.material = scheme == .light ? .popover : .hudWindow
        }
    }

    private final class BackdropView: NSVisualEffectView {
        var silhouette = RoundedRectangle(cornerRadius: 0)

        override func layout() {
            super.layout()
            let size = bounds.size
            guard size.width > 0, size.height > 0, maskImage?.size != size else { return }

            // WindowServer renders the behind-window material. Give AppKit the
            // same silhouette as SwiftUI so the backdrop has rounded corners too.
            maskImage = NSImage(size: size, flipped: false) { [silhouette] rect in
                guard let context = NSGraphicsContext.current?.cgContext else { return false }
                context.addPath(silhouette.path(in: rect).cgPath)
                context.setFillColor(gray: 1, alpha: 1)
                context.fillPath()
                return true
            }
        }
    }
}

struct NotchArtworkWash: View {
    let color: Color?
    let center: UnitPoint
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if !reduceTransparency, contrast != .increased, let color {
                EllipticalGradient(colors: [color.opacity(strength), .clear], center: center,
                                   startRadiusFraction: 0.10, endRadiusFraction: 0.92)
                    .id(color)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: color)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var strength: Double {
        scheme == .light ? NotchStyle.Opacity.lightArtwork : NotchStyle.Opacity.darkArtwork
    }
}

struct NotchTileChrome: ViewModifier {
    var lifted = false

    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: NotchStyle.Radius.card)
        return content
            .background {
                shape.fill(fill)
                    .shadow(color: .black.opacity(lifted ? 0.20 : 0), radius: 9, y: 4)
            }
            .overlay {
                if contrast == .increased {
                    shape.strokeBorder(NotchStyle.hairline(contrast), lineWidth: NotchStyle.hairlineWidth)
                        .allowsHitTesting(false)
                }
            }
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : NotchStyle.Motion.hover, value: hovering)
    }

    private var fill: Color {
        let light = scheme == .light
        if reduceTransparency || lifted {
            return Color(white: light ? (hovering ? 0.995 : 0.98) : (hovering ? 0.22 : 0.19))
        }
        let idle = light ? NotchStyle.Opacity.lightTile : NotchStyle.Opacity.darkTile
        return .white.opacity(idle + (hovering ? (light ? 0.14 : 0.045) : 0))
    }
}

struct NotchTabIndicator: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: NotchStyle.Radius.control)
        if reduceTransparency || contrast == .increased {
            shape.fill(NotchStyle.controlInk.opacity(0.20))
        } else {
            shape.fill(.white.opacity(scheme == .light ? 0.52 : 0.18))
        }
    }
}

struct NotchButtonStyle: ButtonStyle {
    enum Shape {
        case rounded
        case circle(CGFloat)

        var outline: AnyShape {
            switch self {
            case .rounded: return AnyShape(RoundedRectangle(cornerRadius: NotchStyle.Radius.control))
            case .circle: return AnyShape(Circle())
            }
        }
    }

    var tint: Color = NotchStyle.controlInk
    var filled = false
    var shape: Shape = .rounded
    var selected = false
    var usesGlass = false
    var horizontalPadding: CGFloat = 9

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, style: self)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        let style: NotchButtonStyle
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled
        @Environment(\.isFocused) private var focused
        @Environment(\.colorScheme) private var scheme
        @Environment(\.colorSchemeContrast) private var contrast
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

        var body: some View {
            let outline = style.shape.outline
            buttonFace(in: outline)
                .overlay {
                    if focused {
                        outline.stroke(NotchStyle.systemBlue, lineWidth: 1.5)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(outline)
                .opacity(enabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
                .onHover { hovering = $0 }
                .animation(reduceMotion ? nil : NotchStyle.Motion.hover, value: hovering)
                .animation(reduceMotion ? nil : NotchStyle.Motion.interactive, value: configuration.isPressed)
        }

        @ViewBuilder private func buttonFace(in outline: AnyShape) -> some View {
            let highlighted = style.selected || (enabled && (hovering || configuration.isPressed))
            let face = label.foregroundStyle(style.filled ? (scheme == .light ? Color.white : .black) : style.tint)
            if #available(macOS 26.0, *), style.usesGlass, !reduceTransparency, contrast != .increased {
                face.glassEffect(highlighted ? .regular.interactive(!reduceMotion && enabled) : .identity, in: outline)
            } else {
                face.background {
                    if style.filled {
                        outline.fill(style.tint.opacity(configuration.isPressed ? 0.76 : (hovering ? 0.90 : 1)))
                    } else if highlighted {
                        outline.fill(NotchStyle.controlInk.opacity(highlightOpacity))
                    }
                }
            }
        }

        private var highlightOpacity: Double {
            if configuration.isPressed { return NotchStyle.Opacity.pressed }
            let opacity = style.selected ? NotchStyle.Opacity.selected : NotchStyle.Opacity.hover
            return contrast == .increased ? opacity + 0.07 : opacity
        }

        @ViewBuilder private var label: some View {
            switch style.shape {
            case .rounded:
                configuration.label.padding(.horizontal, style.horizontalPadding).frame(minWidth: 26, minHeight: 26)
            case let .circle(diameter):
                configuration.label.frame(width: diameter, height: diameter)
            }
        }
    }
}
