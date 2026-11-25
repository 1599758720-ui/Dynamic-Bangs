import SwiftUI

enum NotchStyle {
    static let primaryText = Color.white
    static let secondary = Color.white.opacity(0.64)
    static let tertiary = Color.white.opacity(0.40)
    static let surface = Color(white: 0.065)
    static let border = Color.white.opacity(0.09)
    static let tileFillTop = Color.white.opacity(0.095)
    static let tileFillBottom = Color.white.opacity(0.048)
    static let tileHoverFillTop = Color.white.opacity(0.135)
    static let tileHoverFillBottom = Color.white.opacity(0.072)
    static let tileCornerRadius: CGFloat = 22
    static let amber = Color(red: 1, green: 0.76, blue: 0.30)
    static let spring = Animation.spring(response: 0.26, dampingFraction: 0.88)
}

struct NotchButtonStyle: ButtonStyle {
    enum Shape {
        case capsule
        case circle(CGFloat)

        var outline: AnyShape {
            switch self {
            case .capsule: return AnyShape(Capsule())
            case .circle: return AnyShape(Circle())
            }
        }
    }

    var tint: Color = .white
    var filled = false
    var shape: Shape = .capsule
    var softTint = false

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, style: self)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        let style: NotchButtonStyle
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled
        @Environment(\.isFocused) private var focused
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.colorSchemeContrast) private var contrast

        var body: some View {
            let outline = style.shape.outline
            let fill = style.filled ? style.tint
                : (style.softTint ? style.tint : .white).opacity(hovering || focused ? 0.17 : 0.095)
            label
                .foregroundStyle(style.filled ? Color.black : style.tint)
                .background(fill, in: outline)
                .overlay {
                    outline.insetStroke(
                        LinearGradient(colors: [.white.opacity(contrast == .increased ? 0.30 : 0.14), .clear],
                                       startPoint: .top, endPoint: .bottom), lineWidth: 0.75
                    ).allowsHitTesting(false)
                }
                .overlay {
                    if focused {
                        outline.insetStroke(Color.accentColor, lineWidth: 1.5)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(outline)
                .opacity(enabled ? 1 : 0.35)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
                .onHover { hovering = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
                .animation(reduceMotion ? nil : NotchStyle.spring, value: configuration.isPressed)
        }

        @ViewBuilder private var label: some View {
            switch style.shape {
            case .capsule:
                configuration.label.padding(.horizontal, 9).frame(minWidth: 26, minHeight: 26)
            case let .circle(diameter):
                configuration.label.frame(width: diameter, height: diameter)
            }
        }
    }
}

private extension AnyShape {
    func insetStroke<S: ShapeStyle>(_ style: S, lineWidth: CGFloat) -> some View {
        stroke(style, lineWidth: lineWidth * 2).clipShape(self)
    }
}
