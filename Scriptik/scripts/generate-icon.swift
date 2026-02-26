#!/usr/bin/env swift
// Generates AppIcon.icns for Scriptik
// Curly brackets with waveform — code meets audio

import Cocoa

let scriptDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
let resourcesDir = scriptDir
    .deletingLastPathComponent()
    .appendingPathComponent("Sources/Scriptik/Resources")
let iconsetDir = resourcesDir.appendingPathComponent("AppIcon.iconset")

try? FileManager.default.removeItem(at: iconsetDir)
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

/// Apple-style continuous curvature rounded rect (squircle)
func squirclePath(in rect: CGRect, cornerRadius: CGFloat) -> CGPath {
    let r = min(cornerRadius, min(rect.width, rect.height) / 2)
    let k: CGFloat = 0.76
    let path = CGMutablePath()
    let l = rect.minX, ri = rect.maxX, b = rect.minY, t = rect.maxY

    path.move(to: CGPoint(x: l + r, y: t))
    path.addLine(to: CGPoint(x: ri - r, y: t))
    path.addCurve(to: CGPoint(x: ri, y: t - r),
                  control1: CGPoint(x: ri - r + r * k, y: t),
                  control2: CGPoint(x: ri, y: t - r + r * k))
    path.addLine(to: CGPoint(x: ri, y: b + r))
    path.addCurve(to: CGPoint(x: ri - r, y: b),
                  control1: CGPoint(x: ri, y: b + r - r * k),
                  control2: CGPoint(x: ri - r + r * k, y: b))
    path.addLine(to: CGPoint(x: l + r, y: b))
    path.addCurve(to: CGPoint(x: l, y: b + r),
                  control1: CGPoint(x: l + r - r * k, y: b),
                  control2: CGPoint(x: l, y: b + r - r * k))
    path.addLine(to: CGPoint(x: l, y: t - r))
    path.addCurve(to: CGPoint(x: l + r, y: t),
                  control1: CGPoint(x: l, y: t - r + r * k),
                  control2: CGPoint(x: l + r - r * k, y: t))
    path.closeSubpath()
    return path
}

/// Draw a curly bracket path (left or right)
/// Coordinates are in normalized 0-1 space, scaled to icon size
func curlyBracketPath(s: CGFloat, isLeft: Bool) -> CGPath {
    let path = CGMutablePath()
    // Bracket dimensions relative to icon size
    let topY = s * 0.22
    let botY = s * 0.78
    let midY = s * 0.50
    let outerX: CGFloat
    let innerX: CGFloat
    let tipX: CGFloat
    let curveOut: CGFloat

    if isLeft {
        outerX = s * 0.30
        innerX = s * 0.24
        tipX = s * 0.19
        curveOut = -s * 0.04
    } else {
        outerX = s * 0.70
        innerX = s * 0.76
        tipX = s * 0.81
        curveOut = s * 0.04
    }

    // Top arm
    path.move(to: CGPoint(x: outerX, y: topY))
    path.addQuadCurve(to: CGPoint(x: innerX, y: topY + s * 0.06),
                      control: CGPoint(x: innerX, y: topY))
    // Down to mid tip
    path.addLine(to: CGPoint(x: innerX, y: midY - s * 0.06))
    path.addQuadCurve(to: CGPoint(x: tipX, y: midY),
                      control: CGPoint(x: innerX + curveOut, y: midY))
    // Mid tip back out
    path.addQuadCurve(to: CGPoint(x: innerX, y: midY + s * 0.06),
                      control: CGPoint(x: innerX + curveOut, y: midY))
    // Down to bottom
    path.addLine(to: CGPoint(x: innerX, y: botY - s * 0.06))
    path.addQuadCurve(to: CGPoint(x: outerX, y: botY),
                      control: CGPoint(x: innerX, y: botY))

    return path
}

func renderIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        fatalError("No graphics context")
    }

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let cx = s * 0.5
    let cy = s * 0.5

    // ========================================
    // BACKGROUND: Rounded square (squircle)
    // ========================================
    let margin = s * 0.04
    let bgRect = CGRect(x: margin, y: margin, width: s - margin * 2, height: s - margin * 2)
    let cornerR = (s - margin * 2) * 0.24  // 24% corner radius
    let bgPath = squirclePath(in: bgRect, cornerRadius: cornerR)

    // Main gradient: Indigo (82,91,255) to (60,70,220)
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    let bgColors = [
        CGColor(red: 0.322, green: 0.357, blue: 1.0, alpha: 1.0),    // #525BFF (top)
        CGColor(red: 0.28, green: 0.30, blue: 0.92, alpha: 1.0),     // Mid
        CGColor(red: 0.235, green: 0.275, blue: 0.863, alpha: 1.0),  // #3C46DC (bottom)
    ]
    if let g = CGGradient(colorsSpace: colorSpace, colors: bgColors as CFArray,
                          locations: [0.0, 0.5, 1.0]) {
        ctx.drawLinearGradient(g,
            start: CGPoint(x: cx, y: bgRect.maxY),
            end: CGPoint(x: cx, y: bgRect.minY),
            options: [])
    }

    // Top highlight
    let hlColors = [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.18),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
    ]
    if let hl = CGGradient(colorsSpace: colorSpace, colors: hlColors as CFArray,
                           locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(hl,
            start: CGPoint(x: cx, y: bgRect.maxY),
            end: CGPoint(x: cx, y: cy),
            options: [])
    }

    // Bottom darkening
    let shColors = [
        CGColor(red: 0, green: 0, blue: 0, alpha: 0.0),
        CGColor(red: 0, green: 0, blue: 0, alpha: 0.12),
    ]
    if let sh = CGGradient(colorsSpace: colorSpace, colors: shColors as CFArray,
                           locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(sh,
            start: CGPoint(x: cx, y: cy - s * 0.1),
            end: CGPoint(x: cx, y: bgRect.minY),
            options: [])
    }
    ctx.restoreGState()

    // Inner border
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
    ctx.setLineWidth(s * 0.004)
    ctx.strokePath()
    ctx.restoreGState()

    // ========================================
    // FOREGROUND: Curly brackets + waveform
    // ========================================
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    // Shadow for foreground elements
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.008),
                  blur: s * 0.025,
                  color: CGColor(red: 0, green: 0, blue: 0.15, alpha: 0.35))

    // White foreground color with subtle gradient
    let fgWhite = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.95)

    // -- Left curly bracket --
    let leftBracket = curlyBracketPath(s: s, isLeft: true)
    ctx.setStrokeColor(fgWhite)
    ctx.setLineWidth(s * 0.032)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.addPath(leftBracket)
    ctx.strokePath()

    // -- Right curly bracket --
    let rightBracket = curlyBracketPath(s: s, isLeft: false)
    ctx.addPath(rightBracket)
    ctx.strokePath()

    // -- Waveform bars in the center --
    let barCount = 5
    let barHeights: [CGFloat] = [0.06, 0.12, 0.19, 0.10, 0.05]
    let waveWidth = s * 0.22
    let waveStartX = cx - waveWidth / 2

    ctx.setLineWidth(s * 0.028)

    for i in 0..<barCount {
        let x = waveStartX + CGFloat(i) / CGFloat(barCount - 1) * waveWidth
        let h = s * barHeights[i]
        ctx.move(to: CGPoint(x: x, y: cy - h))
        ctx.addLine(to: CGPoint(x: x, y: cy + h))
        ctx.strokePath()
    }

    ctx.restoreGState()

    image.unlockFocus()
    return image
}

print("Generating app icon...")

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
    try? FileManager.default.removeItem(at: iconsetDir)
    print("Done: \(icnsPath.path)")
} else {
    print("ERROR: iconutil failed with status \(process.terminationStatus)")
    exit(1)
}
