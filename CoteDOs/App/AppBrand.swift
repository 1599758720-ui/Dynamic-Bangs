import AppKit

enum AppBrand {
    static let name = "Dynamic Bangs"

    static func statusIcon(paused: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 16), flipped: true) { _ in
            let outline = NSBezierPath()
            outline.move(to: NSPoint(x: 1, y: 4))
            outline.line(to: NSPoint(x: 3.2, y: 4))
            outline.curve(to: NSPoint(x: 5, y: 6.2),
                          controlPoint1: NSPoint(x: 4.7, y: 4), controlPoint2: NSPoint(x: 5, y: 5))
            outline.line(to: NSPoint(x: 5, y: 8.8))
            outline.curve(to: NSPoint(x: 7.1, y: 11),
                          controlPoint1: NSPoint(x: 5, y: 10.2), controlPoint2: NSPoint(x: 5.8, y: 11))
            outline.line(to: NSPoint(x: 10.9, y: 11))
            outline.curve(to: NSPoint(x: 13, y: 8.8),
                          controlPoint1: NSPoint(x: 12.2, y: 11), controlPoint2: NSPoint(x: 13, y: 10.2))
            outline.line(to: NSPoint(x: 13, y: 6.2))
            outline.curve(to: NSPoint(x: 14.8, y: 4),
                          controlPoint1: NSPoint(x: 13, y: 5), controlPoint2: NSPoint(x: 13.3, y: 4))
            outline.line(to: NSPoint(x: 17, y: 4))
            outline.lineWidth = 1.4
            outline.lineCapStyle = .round
            NSColor.black.setStroke()
            outline.stroke()
            if !paused {
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: 8, y: 5.5, width: 2, height: 2)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = name
        return image
    }
}
