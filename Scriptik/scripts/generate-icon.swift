#!/usr/bin/env swift
// Generates AppIcon.icns for Scriptik
// Polished macOS-style rounded square icon with microphone
// Mic shape based on Bootstrap Icons mic-fill (MIT license)

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

/// Build mic path in a 16x16 coordinate space (Bootstrap mic-fill, MIT license)
/// Then transform to be centered in the icon at the desired scale.
/// The mic SVG viewBox is 16x16. The mic body spans roughly x:5-11, y:3-11.
/// The cradle+stem spans roughly x:3-13, y:7-16.
/// Visual center of the whole mic shape is around (8, 9.5) in SVG coords.
func micPath(centerX: CGFloat, centerY: CGFloat, height: CGFloat) -> CGPath {
    // The mic in SVG coords spans from y=3 (top of capsule) to y=16 (bottom of base)
    // Total height in SVG units = 13
    let svgH: CGFloat = 13.0
    let scale = height / svgH

    // We want SVG point (8, 9.5) to map to (centerX, centerY)
    // SVG y increases downward, CG y increases upward, so we flip
    let svgCenterX: CGFloat = 8.0
    let svgCenterY: CGFloat = 9.5

    // Transform: translate SVG origin to CG, flip Y, scale, center
    var t = CGAffineTransform.identity
    t = t.translatedBy(x: centerX, y: centerY)
    t = t.scaledBy(x: scale, y: -scale)  // flip Y
    t = t.translatedBy(x: -svgCenterX, y: -svgCenterY)

    let path = CGMutablePath()

    // Path 1: Mic capsule head — "M5 3a3 3 0 0 1 6 0v5a3 3 0 0 1-6 0z"
    // This is a rounded rect: top-left at (5,3), width 6, height 8, with radius 3
    // Decomposed: move to (5,3), arc to (11,3) via top, line to (11,8),
    //             arc to (5,8) via bottom, close
    // Actually it's: M5,3 then arc(rx=3,ry=3) to (11,3), v5 to (11,8),
    //                arc(rx=3,ry=3) to (5,8), close
    // Simpler: it's a capsule from (5,3)-(11,11) with corner radius 3
    let capsule = CGRect(x: 5, y: 3, width: 6, height: 8)
    let capsulePath = CGPath(roundedRect: capsule, cornerWidth: 3, cornerHeight: 3, transform: &t)
    path.addPath(capsulePath)

    // Path 2: Cradle + stem + base
    // "M3.5 6.5A.5.5 0 0 1 4 7v1a4 4 0 0 0 8 0V7a.5.5 0 0 1 1 0v1a5 5 0 0 1-4.5 4.975V15h3a.5.5 0 0 1 0 1h-7a.5.5 0 0 1 0-1h3v-2.025A5 5 0 0 1 3 8V7a.5.5 0 0 1 .5-.5"
    // This is complex SVG. Let's build it as simple geometric shapes instead.

    // Left side of cradle: vertical line at x=3.5 from y=7 to y=8
    // Then arc (radius 5) from (3,8) curving down to (8,13)
    // Stem at x=8 from y=12.975 to y=15
    // Base: horizontal line from (5.5,15) to (10.5,16) area

    // Simplified approach: draw cradle as stroked path, stem, base
    // We'll handle these as filled rects since we want a filled icon

    // Actually, let's draw the cradle+stem as a compound shape
    // Left arm: rect at x=3.25, y=6.75, w=0.75, h=1.5 with rounded ends
    // Right arm: rect at x=12, y=6.75, w=0.75, h=1.5
    // U-curve: we approximate with arcs

    // For cleaner result, just draw simple geometry:

    // Cradle left side
    let cradleThick: CGFloat = 0.85
    let leftArm = CGRect(x: 3.3, y: 6.8, width: cradleThick, height: 1.8)
    path.addPath(CGPath(roundedRect: leftArm, cornerWidth: cradleThick/2,
                        cornerHeight: cradleThick/2, transform: &t))

    // Cradle right side
    let rightArm = CGRect(x: 11.85, y: 6.8, width: cradleThick, height: 1.8)
    path.addPath(CGPath(roundedRect: rightArm, cornerWidth: cradleThick/2,
                        cornerHeight: cradleThick/2, transform: &t))

    // Cradle bottom arc: a thick arc from left to right
    // We'll use a donut segment approach
    let cradleArc = CGMutablePath()
    // In SVG coords, center of arc is at (8, 8), inner radius ~4, outer radius ~4.85
    // Arc from 0 to pi (bottom half)
    let arcCX: CGFloat = 8, arcCY: CGFloat = 8
    let outerR: CGFloat = 4.85, innerR: CGFloat = 4.0
    // Outer arc (clockwise in SVG = counter-clockwise in CG after flip)
    cradleArc.addArc(center: CGPoint(x: arcCX, y: arcCY), radius: outerR,
                     startAngle: 0, endAngle: .pi, clockwise: false)
    // Inner arc back
    cradleArc.addArc(center: CGPoint(x: arcCX, y: arcCY), radius: innerR,
                     startAngle: .pi, endAngle: 0, clockwise: true)
    cradleArc.closeSubpath()
    path.addPath(cradleArc.copy(using: &t)!)

    // Stem: vertical rect from y=12.5 to y=15
    let stem = CGRect(x: 7.55, y: 12.5, width: 0.9, height: 2.5)
    path.addPath(CGPath(roundedRect: stem, cornerWidth: 0.1, cornerHeight: 0.1, transform: &t))

    // Base: horizontal rounded rect
    let base = CGRect(x: 5.0, y: 15.0, width: 6.0, height: 1.0)
    path.addPath(CGPath(roundedRect: base, cornerWidth: 0.5, cornerHeight: 0.5, transform: &t))

    return path
}

func renderIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        fatalError("No graphics context")
    }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let cx = s * 0.5
    let cy = s * 0.5

    // ========================================
    // BACKGROUND: Rounded square (squircle)
    // ========================================
    let margin = s * 0.04
    let bgRect = CGRect(x: margin, y: margin, width: s - margin * 2, height: s - margin * 2)
    let cornerR = (s - margin * 2) * 0.22
    let bgPath = squirclePath(in: bgRect, cornerRadius: cornerR)

    // Main gradient: rich blue to deep indigo
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    let bgColors = [
        CGColor(red: 0.32, green: 0.58, blue: 1.0, alpha: 1.0),   // Bright blue (top)
        CGColor(red: 0.24, green: 0.42, blue: 0.95, alpha: 1.0),  // Mid blue
        CGColor(red: 0.30, green: 0.24, blue: 0.80, alpha: 1.0),  // Deep indigo (bottom)
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
    // MICROPHONE (centered in icon)
    // ========================================
    let micHeight = s * 0.52  // mic occupies ~52% of icon height
    let mic = micPath(centerX: cx, centerY: cy, height: micHeight)

    // Shadow
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01),
                  blur: s * 0.03,
                  color: CGColor(red: 0, green: 0, blue: 0.15, alpha: 0.30))

    // Mic fill: gradient white-to-light-gray for 3D feel
    ctx.saveGState()
    ctx.addPath(mic)
    ctx.clip()
    let micColors = [
        CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.98),
        CGColor(red: 0.90, green: 0.92, blue: 0.96, alpha: 0.95),
    ]
    if let mg = CGGradient(colorsSpace: colorSpace, colors: micColors as CFArray,
                           locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(mg,
            start: CGPoint(x: cx, y: cy + micHeight * 0.5),
            end: CGPoint(x: cx, y: cy - micHeight * 0.5),
            options: [.drawsAfterEndLocation, .drawsBeforeStartLocation])
    }
    ctx.restoreGState()
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
