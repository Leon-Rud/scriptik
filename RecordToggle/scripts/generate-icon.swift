#!/usr/bin/env swift
// Generates AppIcon.icns for Record Toggle
// Uses CoreGraphics to render a microphone icon with gradient background

import Cocoa

let sizes = [16, 32, 128, 256, 512, 1024]
let scriptDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
let resourcesDir = scriptDir
    .deletingLastPathComponent()
    .appendingPathComponent("Sources/RecordToggle/Resources")
let iconsetDir = resourcesDir.appendingPathComponent("AppIcon.iconset")

// Clean and create iconset directory
try? FileManager.default.removeItem(at: iconsetDir)
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

func renderIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        fatalError("No graphics context")
    }

    // --- Gradient circle background ---
    let rect = CGRect(x: 0, y: 0, width: s, height: s)
    let inset = s * 0.02
    let circleRect = rect.insetBy(dx: inset, dy: inset)
    let circlePath = CGPath(ellipseIn: circleRect, transform: nil)

    ctx.saveGState()
    ctx.addPath(circlePath)
    ctx.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        CGColor(red: 0.25, green: 0.45, blue: 0.95, alpha: 1.0),  // Blue
        CGColor(red: 0.35, green: 0.25, blue: 0.85, alpha: 1.0),  // Indigo
    ]
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(gradient,
            start: CGPoint(x: s * 0.5, y: s),
            end: CGPoint(x: s * 0.5, y: 0),
            options: [])
    }
    ctx.restoreGState()

    // Subtle inner shadow / glow at top
    ctx.saveGState()
    ctx.addPath(circlePath)
    ctx.clip()
    let glowColors = [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.15),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
    ]
    if let glow = CGGradient(colorsSpace: colorSpace, colors: glowColors as CFArray, locations: [0.0, 0.5]) {
        ctx.drawLinearGradient(glow,
            start: CGPoint(x: s * 0.5, y: s),
            end: CGPoint(x: s * 0.5, y: s * 0.3),
            options: [])
    }
    ctx.restoreGState()

    // --- White microphone ---
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))

    let cx = s * 0.5
    let micW = s * 0.18
    let micH = s * 0.30
    let micTop = s * 0.62
    let micRadius = micW * 0.5

    // Mic body (rounded rect)
    let micRect = CGRect(x: cx - micW/2, y: micTop - micH, width: micW, height: micH)
    let micPath = CGPath(roundedRect: micRect, cornerWidth: micRadius, cornerHeight: micRadius, transform: nil)
    ctx.addPath(micPath)
    ctx.fillPath()

    // Mic cradle (arc below mic body)
    let cradleW = s * 0.28
    let cradleTop = micTop - micH * 0.15
    let cradleBottom = micTop - micH - s * 0.08

    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    ctx.setLineWidth(s * 0.035)
    ctx.setLineCap(.round)

    let cradlePath = CGMutablePath()
    cradlePath.move(to: CGPoint(x: cx - cradleW/2, y: cradleTop))
    cradlePath.addCurve(
        to: CGPoint(x: cx + cradleW/2, y: cradleTop),
        control1: CGPoint(x: cx - cradleW/2, y: cradleBottom),
        control2: CGPoint(x: cx + cradleW/2, y: cradleBottom)
    )
    ctx.addPath(cradlePath)
    ctx.strokePath()

    // Mic stand (vertical line down from cradle bottom center)
    let standTop = (cradleTop + cradleBottom) / 2 - s * 0.04
    let standBottom = standTop - s * 0.08
    ctx.move(to: CGPoint(x: cx, y: standTop))
    ctx.addLine(to: CGPoint(x: cx, y: standBottom))
    ctx.strokePath()

    // Stand base (horizontal line)
    let baseW = s * 0.14
    ctx.move(to: CGPoint(x: cx - baseW/2, y: standBottom))
    ctx.addLine(to: CGPoint(x: cx + baseW/2, y: standBottom))
    ctx.strokePath()

    // --- Waveform arcs ---
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.5))
    ctx.setLineWidth(s * 0.02)

    let micCenterY = micTop - micH * 0.5
    for i in 1...2 {
        let arcRadius = s * (0.22 + Double(i) * 0.06)
        let arcAngle = CGFloat.pi * 0.25

        // Left arc
        ctx.addArc(center: CGPoint(x: cx, y: micCenterY),
                   radius: arcRadius,
                   startAngle: CGFloat.pi/2 + arcAngle/2,
                   endAngle: CGFloat.pi/2 - arcAngle/2,
                   clockwise: true)
        ctx.strokePath()

        // Right arc
        ctx.addArc(center: CGPoint(x: cx, y: micCenterY),
                   radius: arcRadius,
                   startAngle: CGFloat.pi/2 + arcAngle/2,
                   endAngle: CGFloat.pi/2 - arcAngle/2,
                   clockwise: true)
        // Mirror: use negative x offset via transform
        let rightArc = CGMutablePath()
        rightArc.addArc(center: CGPoint(x: cx, y: micCenterY),
                        radius: arcRadius,
                        startAngle: -(CGFloat.pi/2 + arcAngle/2),
                        endAngle: -(CGFloat.pi/2 - arcAngle/2),
                        clockwise: false)
        ctx.addPath(rightArc)
        ctx.strokePath()
    }

    image.unlockFocus()
    return image
}

print("Generating app icon...")

// macOS requires exactly these files in the iconset:
//   icon_16x16.png (16px), icon_16x16@2x.png (32px)
//   icon_32x32.png (32px), icon_32x32@2x.png (64px)
//   icon_128x128.png (128px), icon_128x128@2x.png (256px)
//   icon_256x256.png (256px), icon_256x256@2x.png (512px)
//   icon_512x512.png (512px), icon_512x512@2x.png (1024px)
let iconEntries: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

// Cache rendered images by pixel size to avoid re-rendering
var cache: [Int: Data] = [:]

for entry in iconEntries {
    let png: Data
    if let cached = cache[entry.pixels] {
        png = cached
    } else {
        let image = renderIcon(size: entry.pixels)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
            fatalError("Failed to render \(entry.pixels)px")
        }
        cache[entry.pixels] = data
        png = data
    }

    let url = iconsetDir.appendingPathComponent(entry.name)
    try png.write(to: url)
    print("  \(entry.name) (\(entry.pixels)px)")
}

print("Converting to .icns...")

let icnsPath = resourcesDir.appendingPathComponent("AppIcon.icns")

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["--convert", "icns", iconsetDir.path, "--output", icnsPath.path]
try process.run()
process.waitUntilExit()

if process.terminationStatus == 0 {
    // Clean up iconset directory
    try? FileManager.default.removeItem(at: iconsetDir)
    print("Done: \(icnsPath.path)")
} else {
    print("ERROR: iconutil failed with status \(process.terminationStatus)")
    exit(1)
}
