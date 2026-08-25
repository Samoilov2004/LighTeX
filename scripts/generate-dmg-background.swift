#!/usr/bin/swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: generate-dmg-background.swift <output.png>\n".utf8))
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let canvas = NSSize(width: 720, height: 440)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvas.width),
    pixelsHigh: Int(canvas.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
    FileHandle.standardError.write(Data("Could not create the DMG canvas.\n".utf8))
    exit(1)
}

func centeredOrigin(for text: NSAttributedString, y: CGFloat) -> NSPoint {
    let size = text.size()
    return NSPoint(x: (canvas.width - size.width) / 2, y: y)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext

let bounds = NSRect(origin: .zero, size: canvas)
NSGradient(colors: [
    NSColor(calibratedWhite: 0.995, alpha: 1),
    NSColor(calibratedRed: 0.945, green: 0.961, blue: 0.995, alpha: 1),
])!.draw(in: bounds, angle: -90)

for (center, radius, alpha) in [
    (NSPoint(x: 170, y: 215), CGFloat(155), CGFloat(0.055)),
    (NSPoint(x: 550, y: 215), CGFloat(155), CGFloat(0.045)),
] {
    let glowBounds = NSRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
    )
    NSGradient(colors: [
        NSColor(calibratedRed: 0.05, green: 0.42, blue: 0.98, alpha: alpha),
        NSColor(calibratedRed: 0.05, green: 0.42, blue: 0.98, alpha: 0),
    ])!.draw(in: NSBezierPath(ovalIn: glowBounds), relativeCenterPosition: .zero)
}

let title = NSAttributedString(
    string: "Install LighTex",
    attributes: [
        .font: NSFont.systemFont(ofSize: 25, weight: .semibold),
        .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1),
    ]
)
title.draw(at: centeredOrigin(for: title, y: 374))

let subtitle = NSAttributedString(
    string: "Drag LighTex into Applications",
    attributes: [
        .font: NSFont.systemFont(ofSize: 14, weight: .regular),
        .foregroundColor: NSColor(calibratedWhite: 0.38, alpha: 1),
    ]
)
subtitle.draw(at: centeredOrigin(for: subtitle, y: 344))

let arrowColor = NSColor(calibratedRed: 0.04, green: 0.39, blue: 0.96, alpha: 0.86)
let arrow = NSBezierPath()
arrow.lineWidth = 3
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 302, y: 220))
arrow.line(to: NSPoint(x: 418, y: 220))
arrow.move(to: NSPoint(x: 404, y: 233))
arrow.line(to: NSPoint(x: 418, y: 220))
arrow.line(to: NSPoint(x: 404, y: 207))
arrowColor.setStroke()
arrow.stroke()

let footer = NSAttributedString(
    string: "macOS 14 or later",
    attributes: [
        .font: NSFont.systemFont(ofSize: 11, weight: .medium),
        .foregroundColor: NSColor(calibratedWhite: 0.42, alpha: 1),
    ]
)
footer.draw(at: centeredOrigin(for: footer, y: 34))

graphicsContext.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [.compressionFactor: 0.9]) else {
    FileHandle.standardError.write(Data("Could not render the DMG background.\n".utf8))
    exit(1)
}

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try pngData.write(to: outputURL, options: .atomic)
