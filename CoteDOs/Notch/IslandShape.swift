import SwiftUI

/// Top-joined MacBook Pro notch silhouette with optional concave top shoulders
/// and smooth bottom corners. The entire path stays strictly inside `rect` so
/// outward flares never encroach past the budgeted menu-bar clearance.
struct NotchEarShape: InsettableShape {
    var bottomRadius: CGFloat = 13
    var leadingTopFlare: CGFloat = 6
    var trailingTopFlare: CGFloat = 6
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> NotchEarShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let box = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard box.width > 2, box.height > 2 else { return Path() }

        let maxFlare = min(box.height * 0.35, box.width * 0.12)
        let leftFlare = max(0, min(leadingTopFlare, maxFlare))
        let rightFlare = max(0, min(trailingTopFlare, maxFlare))
        let innerWidth = max(0, box.width - leftFlare - rightFlare)
        let rBottom = max(0, min(bottomRadius - insetAmount, box.height - max(leftFlare, rightFlare), innerWidth / 2))

        let leftWall = box.minX + leftFlare
        let rightWall = box.maxX - rightFlare

        var path = Path()
        path.move(to: CGPoint(x: box.minX, y: box.minY))
        if leftFlare > 0 {
            path.addQuadCurve(
                to: CGPoint(x: leftWall, y: box.minY + leftFlare),
                control: CGPoint(x: leftWall, y: box.minY)
            )
        }
        path.addLine(to: CGPoint(x: leftWall, y: box.maxY - rBottom))
        path.addQuadCurve(
            to: CGPoint(x: leftWall + rBottom, y: box.maxY),
            control: CGPoint(x: leftWall, y: box.maxY)
        )
        path.addLine(to: CGPoint(x: rightWall - rBottom, y: box.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rightWall, y: box.maxY - rBottom),
            control: CGPoint(x: rightWall, y: box.maxY)
        )
        path.addLine(to: CGPoint(x: rightWall, y: box.minY + rightFlare))
        if rightFlare > 0 {
            path.addQuadCurve(
                to: CGPoint(x: box.maxX, y: box.minY),
                control: CGPoint(x: rightWall, y: box.minY)
            )
        }
        path.closeSubpath()
        return path
    }
}

/// Legacy top-joined silhouette retained for compatibility.
struct IslandShape: InsettableShape {
    var cornerRadius: CGFloat
    var insetAmount: CGFloat = 0

    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func inset(by amount: CGFloat) -> IslandShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }

    func path(in rect: CGRect) -> Path {
        let inset = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard inset.width > 0, inset.height > 0 else { return Path() }
        let radius = max(0, min(cornerRadius - insetAmount, min(inset.width, inset.height) / 2))
        var path = Path()
        path.move(to: CGPoint(x: inset.minX, y: inset.minY))
        path.addLine(to: CGPoint(x: inset.maxX, y: inset.minY))
        path.addLine(to: CGPoint(x: inset.maxX, y: inset.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: inset.maxX - radius, y: inset.maxY),
                          control: CGPoint(x: inset.maxX, y: inset.maxY))
        path.addLine(to: CGPoint(x: inset.minX + radius, y: inset.maxY))
        path.addQuadCurve(to: CGPoint(x: inset.minX, y: inset.maxY - radius),
                          control: CGPoint(x: inset.minX, y: inset.maxY))
        path.closeSubpath()
        return path
    }
}
