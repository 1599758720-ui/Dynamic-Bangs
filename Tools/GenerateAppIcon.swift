#!/usr/bin/swift
//
// Draw the Dynamic Bangs icon in a 1024-point grid and export the Mac icon set.
// Run with swift Tools/GenerateAppIcon.swift from the project root.

import CoreGraphics
import Foundation
import ImageIO

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: srgb, components: [
        CGFloat((hex >> 16) & 0xFF) / 255,
        CGFloat((hex >> 8) & 0xFF) / 255,
        CGFloat(hex & 0xFF) / 255,
        alpha,
    ])!
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: srgb, colors: colors as CFArray, locations: nil)!
}

/// A horizontal edge that bends down into the camera housing.
func fringePath() -> CGMutablePath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 219, y: 408))
    path.addLine(to: CGPoint(x: 320, y: 408))
    path.addCurve(to: CGPoint(x: 375, y: 474),
                  control1: CGPoint(x: 359, y: 408), control2: CGPoint(x: 375, y: 434))
    path.addLine(to: CGPoint(x: 375, y: 553))
    path.addCurve(to: CGPoint(x: 451, y: 629),
                  control1: CGPoint(x: 375, y: 599), control2: CGPoint(x: 405, y: 629))
    path.addLine(to: CGPoint(x: 573, y: 629))
    path.addCurve(to: CGPoint(x: 649, y: 553),
                  control1: CGPoint(x: 619, y: 629), control2: CGPoint(x: 649, y: 599))
    path.addLine(to: CGPoint(x: 649, y: 474))
    path.addCurve(to: CGPoint(x: 704, y: 408),
                  control1: CGPoint(x: 649, y: 434), control2: CGPoint(x: 665, y: 408))
    path.addLine(to: CGPoint(x: 805, y: 408))
    return path
}

func drawIcon(in context: CGContext, side: CGFloat, small: Bool) {
    context.translateBy(x: 0, y: side)
    context.scaleBy(x: side / 1024, y: -side / 1024)

    // macOS applies its own corner mask to a full-bleed square.
    context.drawLinearGradient(
        gradient([color(0x284D79), color(0x17243C), color(0x090F1C)]),
        start: CGPoint(x: 196, y: 90), end: CGPoint(x: 805, y: 951),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    if !small {
        context.drawRadialGradient(
            gradient([color(0x5FAFFF, 0.24), color(0x5FAFFF, 0)]),
            startCenter: CGPoint(x: 320, y: 250), startRadius: 0,
            endCenter: CGPoint(x: 320, y: 250), endRadius: 490, options: []
        )
    }

    let fringe = fringePath()
    context.addPath(fringe)
    context.setFillColor(color(0x080D18))
    context.fillPath()

    context.saveGState()
    context.addPath(fringe)
    context.setLineCap(.round)
    context.setLineWidth(small ? 58 : 32)
    context.replacePathWithStrokedPath()
    context.clip()
    context.drawLinearGradient(
        gradient([color(0xD6F9FF), color(0x77DEFA), color(0x557EFC)]),
        start: CGPoint(x: 219, y: 361), end: CGPoint(x: 805, y: 645),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    context.restoreGState()

    let lensSize: CGFloat = small ? 66 : 54
    let lens = CGRect(x: 512 - lensSize / 2, y: 505 - lensSize / 2, width: lensSize, height: lensSize)
    context.setFillColor(color(0x7DDFF8))
    context.fillEllipse(in: lens)
    if !small {
        context.setFillColor(color(0xE4FBFF))
        context.fillEllipse(in: CGRect(x: 501, y: 492, width: 16, height: 16))
    }
}

func bitmap(_ side: Int, opaque: Bool = false) -> CGContext {
    CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
              space: srgb, bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue)!
}

func render(side: Int) -> CGImage {
    let supersampled = bitmap(side * 2)
    drawIcon(in: supersampled, side: CGFloat(side * 2), small: side <= 32)
    let output = bitmap(side)
    output.interpolationQuality = .high
    output.draw(supersampled.makeImage()!, in: CGRect(x: 0, y: 0, width: side, height: side))
    return output.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination), "Could not write \(url.path)")
}

let catalog = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first
                  ?? "CoteDOs/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: true)
for side in [16, 32, 64, 128, 256, 512, 1024] {
    write(render(side: side), to: catalog.appendingPathComponent("icon_\(side).png"))
}

let marketingIcon = URL(fileURLWithPath: "assets/icon.png")
if CommandLine.arguments.count == 1 && FileManager.default.fileExists(atPath: marketingIcon.deletingLastPathComponent().path) {
    let flat = bitmap(1024, opaque: true)
    flat.setFillColor(color(0xFFFFFF))
    flat.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    let preview = CGRect(x: 100, y: 100, width: 824, height: 824)
    flat.addPath(CGPath(roundedRect: preview, cornerWidth: 172, cornerHeight: 172, transform: nil))
    flat.clip()
    flat.draw(render(side: 1024), in: preview)
    write(flat.makeImage()!, to: marketingIcon)
}
