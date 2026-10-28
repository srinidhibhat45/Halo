// Draws Halo's app icon into an .iconset folder (then: iconutil -c icns <dir>).
//
//   swift Scripts/make-icon.swift build/AppIcon.iconset
//
// The design: a deep indigo squircle holding a ring of eight frosted segments, the top one lit
// with a blue glow, as if just highlighted. Drawn with CoreGraphics on Apple's macOS icon grid
// (1024 canvas, 824 body, continuous corners).
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/AppIcon.iconset"
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: sRGB, components: [
        CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, alpha,
    ])!
}

/// Rounded rectangle with Apple-style continuous (squircle) corners.
func continuousRoundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    let r = min(radius, min(rect.width, rect.height) / 2 / 1.52866483)
    let p = CGMutablePath()
    let (minX, minY, maxX, maxY) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
    p.move(to: pt(minX + 1.52866483 * r, maxY))
    p.addLine(to: pt(maxX - 1.52866483 * r, maxY))
    p.addCurve(to: pt(maxX - 0.66993427 * r, maxY - 0.06549600 * r), control1: pt(maxX - 1.08849323 * r, maxY), control2: pt(maxX - 0.86840694 * r, maxY))
    p.addCurve(to: pt(maxX - 0.06549600 * r, maxY - 0.66993427 * r), control1: pt(maxX - 0.37754465 * r, maxY - 0.16656099 * r), control2: pt(maxX - 0.16656099 * r, maxY - 0.37754465 * r))
    p.addCurve(to: pt(maxX, maxY - 1.52866483 * r), control1: pt(maxX, maxY - 0.86840694 * r), control2: pt(maxX, maxY - 1.08849323 * r))
    p.addLine(to: pt(maxX, minY + 1.52866483 * r))
    p.addCurve(to: pt(maxX - 0.06549600 * r, minY + 0.66993427 * r), control1: pt(maxX, minY + 1.08849323 * r), control2: pt(maxX, minY + 0.86840694 * r))
    p.addCurve(to: pt(maxX - 0.66993427 * r, minY + 0.06549600 * r), control1: pt(maxX - 0.16656099 * r, minY + 0.37754465 * r), control2: pt(maxX - 0.37754465 * r, minY + 0.16656099 * r))
    p.addCurve(to: pt(maxX - 1.52866483 * r, minY), control1: pt(maxX - 0.86840694 * r, minY), control2: pt(maxX - 1.08849323 * r, minY))
    p.addLine(to: pt(minX + 1.52866483 * r, minY))
    p.addCurve(to: pt(minX + 0.66993427 * r, minY + 0.06549600 * r), control1: pt(minX + 1.08849323 * r, minY), control2: pt(minX + 0.86840694 * r, minY))
    p.addCurve(to: pt(minX + 0.06549600 * r, minY + 0.66993427 * r), control1: pt(minX + 0.37754465 * r, minY + 0.16656099 * r), control2: pt(minX + 0.16656099 * r, minY + 0.37754465 * r))
    p.addCurve(to: pt(minX, minY + 1.52866483 * r), control1: pt(minX, minY + 0.86840694 * r), control2: pt(minX, minY + 1.08849323 * r))
    p.addLine(to: pt(minX, maxY - 1.52866483 * r))
    p.addCurve(to: pt(minX + 0.06549600 * r, maxY - 0.66993427 * r), control1: pt(minX, maxY - 1.08849323 * r), control2: pt(minX, maxY - 0.86840694 * r))
    p.addCurve(to: pt(minX + 0.66993427 * r, maxY - 0.06549600 * r), control1: pt(minX + 0.16656099 * r, maxY - 0.37754465 * r), control2: pt(minX + 0.37754465 * r, maxY - 0.16656099 * r))
    p.addCurve(to: pt(minX + 1.52866483 * r, maxY), control1: pt(minX + 0.86840694 * r, maxY), control2: pt(minX + 1.08849323 * r, maxY))
    p.closeSubpath()
    return p
}

/// Annular sector between `inner` and `outer` radii from angle `a0` to `a1` (radians, y-up),
/// inset by `inset` so that stroking it with `2 * inset` and round joins yields rounded corners.
func sectorPath(center c: CGPoint, inner: CGFloat, outer: CGFloat, a0: CGFloat, a1: CGFloat, inset: CGFloat) -> CGPath {
    let ri = inner + inset, ro = outer - inset
    let di = inset / ri, dO = inset / ro
    let p = CGMutablePath()
    p.addArc(center: c, radius: ro, startAngle: a0 + dO, endAngle: a1 - dO, clockwise: false)
    p.addArc(center: c, radius: ri, startAngle: a1 - di, endAngle: a0 + di, clockwise: true)
    p.closeSubpath()
    return p
}

func drawIcon(pixels: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let k = CGFloat(pixels) / 1024
    ctx.scaleBy(x: k, y: k)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = continuousRoundedRect(body, radius: 185)
    let center = CGPoint(x: 512, y: 512)

    // Shadow under the body.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0x000000, 0.45))
    ctx.addPath(bodyPath)
    ctx.setFillColor(rgb(0x0B0D1E))
    ctx.fillPath()
    ctx.restoreGState()

    // Body: indigo-to-ink gradient with a soft blue bloom behind the ring.
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let bg = CGGradient(colorsSpace: sRGB, colors: [rgb(0x272C6B), rgb(0x12153A), rgb(0x06070F)] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    let bloom = CGGradient(colorsSpace: sRGB, colors: [rgb(0x4C6BFF, 0.42), rgb(0x4C6BFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(bloom, startCenter: CGPoint(x: 512, y: 560), startRadius: 0, endCenter: CGPoint(x: 512, y: 560), endRadius: 430, options: [])

    // Ring of eight segments; slot 0 (top) is lit.
    let inner: CGFloat = 176, outer: CGFloat = 318
    let count = 8
    let step = 2 * CGFloat.pi / CGFloat(count)
    let gap: CGFloat = 12 / ((inner + outer) / 2)   // ~12 px gap at the mid-line
    let corner: CGFloat = 16
    for i in 0..<count {
        let mid = CGFloat.pi / 2 - CGFloat(i) * step   // clockwise from the top (y-up)
        let core = sectorPath(center: center, inner: inner, outer: outer, a0: mid - step / 2 + gap / 2, a1: mid + step / 2 - gap / 2, inset: corner)
        // Fill ∪ round-joined stroke = the sector with rounded corners, as one seamless shape.
        let path = core.union(core.copy(strokingWithWidth: corner * 2, lineCap: .round, lineJoin: .round, miterLimit: 10))
        ctx.saveGState()
        if i == 0 {
            // Glow, then a bright blue→cyan fill.
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 56, color: rgb(0x3D8BFF, 0.95))
            ctx.addPath(path)
            ctx.setFillColor(rgb(0x3D8BFF))
            ctx.fillPath()
            ctx.restoreGState()
            ctx.addPath(path)
            ctx.clip()
            let lit = CGGradient(colorsSpace: sRGB, colors: [rgb(0x8FE3FF), rgb(0x3D8BFF), rgb(0x2B5CFF)] as CFArray, locations: [0, 0.6, 1])!
            ctx.drawLinearGradient(lit, start: CGPoint(x: 512, y: center.y + outer), end: CGPoint(x: 512, y: center.y + inner), options: [])
        } else {
            ctx.addPath(path)
            ctx.clip()
            let frost = CGGradient(colorsSpace: sRGB, colors: [rgb(0xFFFFFF, 0.20), rgb(0xFFFFFF, 0.08)] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(frost, start: CGPoint(x: 512, y: center.y + outer), end: CGPoint(x: 512, y: center.y - outer), options: [])
        }
        ctx.restoreGState()

        // A small "action" dot in each segment.
        let dotRadius: CGFloat = i == 0 ? 15 : 11
        let r = (inner + outer) / 2
        let dot = CGRect(x: center.x + cos(mid) * r - dotRadius, y: center.y + sin(mid) * r - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
        ctx.setFillColor(rgb(0xFFFFFF, i == 0 ? 1 : 0.55))
        ctx.fillEllipse(in: dot)
    }

    // Hub.
    let hubR: CGFloat = 128
    let hubRect = CGRect(x: center.x - hubR, y: center.y - hubR, width: hubR * 2, height: hubR * 2)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 22, color: rgb(0x000000, 0.5))
    ctx.setFillColor(rgb(0x161A3D))
    ctx.fillEllipse(in: hubRect)
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addEllipse(in: hubRect)
    ctx.clip()
    let hub = CGGradient(colorsSpace: sRGB, colors: [rgb(0x2E3470), rgb(0x12152F)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(hub, start: CGPoint(x: 512, y: center.y + hubR), end: CGPoint(x: 512, y: center.y - hubR), options: [])
    ctx.restoreGState()
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.16))
    ctx.setLineWidth(4)
    ctx.strokeEllipse(in: hubRect.insetBy(dx: 2, dy: 2))
    // Hub mark: a small ring echoing the logo.
    ctx.setStrokeColor(rgb(0xBFD4FF, 0.9))
    ctx.setLineWidth(14)
    ctx.strokeEllipse(in: CGRect(x: center.x - 38, y: center.y - 38, width: 76, height: 76))

    // Top gloss and a hairline edge.
    let gloss = CGGradient(colorsSpace: sRGB, colors: [rgb(0xFFFFFF, 0.10), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gloss, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    ctx.addPath(bodyPath)
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.14))
    ctx.setLineWidth(4)
    ctx.strokePath()
    ctx.restoreGState()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to path: String) throws {
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "make-icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot write \(path)"])
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw NSError(domain: "make-icon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot finalize \(path)"])
    }
}

let entries: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for entry in entries {
    try writePNG(drawIcon(pixels: entry.pixels), to: "\(outDir)/\(entry.name).png")
}
print("Wrote \(entries.count) PNGs to \(outDir)")
