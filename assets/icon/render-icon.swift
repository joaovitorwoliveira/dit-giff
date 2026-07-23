#!/usr/bin/env swift

// Renders the Dit Giff app icon at every size macOS needs.
// The design is fully geometric, so it is drawn rather than exported: same hex,
// same geometry, same result on every run.
//
//   swift render-icon.swift <output-dir>

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import SwiftUI

// MARK: - Palette

struct Paint {
    let r, g, b: CGFloat
    init(_ hex: UInt32) {
        r = CGFloat((hex >> 16) & 0xFF) / 255
        g = CGFloat((hex >> 8) & 0xFF) / 255
        b = CGFloat(hex & 0xFF) / 255
    }
    func cg(_ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: alpha)
    }
    var hexString: String {
        String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

let fieldLeft = Paint(0x0D1712)   // near-black, green undertone — the "after"
let fieldRight = Paint(0x1A100E)  // near-black, warm undertone — the "before"
let sage = Paint(0x8FBF8A)        // the open eye
let coral = Paint(0xF07A64)       // the closed eye

// MARK: - Geometry, expressed as fractions of the icon body

/// Apple's continuous-corner radius ratio for app icon shapes.
let cornerRatio: CGFloat = 0.2237
/// Fraction of the 1024 canvas occupied by the icon body on the macOS grid.
let macOSBodyRatio: CGFloat = 824.0 / 1024.0

let strokeWeight: CGFloat = 0.088   // thickness of the plus bars
let markSpan: CGFloat = 0.330       // length of a plus arm / of the minus
let minusWeightBoost: CGFloat = 1.06 // the minus needs extra mass to weigh the same
let minusSpanBoost: CGFloat = 1.02
let eyeOffsetBase: CGFloat = 0.225  // horizontal distance of each eye from center

/// How the icon is adapted for a given pixel size.
///
/// Small sizes are not just scaled-down large ones. Below ~64px the grid margin and
/// the drop shadow eat most of the canvas and the marks fall below one pixel, so the
/// body grows, the strokes thicken and the soft effects are dropped entirely — the
/// same reason an .iconset ships separate artwork per size instead of one image.
struct SizeProfile {
    let bodyRatio: CGFloat
    let weightScale: CGFloat
    let spanScale: CGFloat
    let eyeOffset: CGFloat
    let dropShadow: Bool
    let softDetail: Bool
    let snapToPixels: Bool

    static func forSize(_ px: Int, fullBleed: Bool) -> SizeProfile {
        if fullBleed {
            return SizeProfile(bodyRatio: 1, weightScale: 1, spanScale: 1,
                               eyeOffset: eyeOffsetBase, dropShadow: false,
                               softDetail: true, snapToPixels: false)
        }
        switch px {
        case ...16:
            return SizeProfile(bodyRatio: 1.00, weightScale: 1.62, spanScale: 1.02,
                               eyeOffset: 0.212, dropShadow: false,
                               softDetail: false, snapToPixels: true)
        case ...32:
            return SizeProfile(bodyRatio: 0.96, weightScale: 1.30, spanScale: 1.08,
                               eyeOffset: 0.232, dropShadow: false,
                               softDetail: false, snapToPixels: true)
        case ...64:
            return SizeProfile(bodyRatio: 0.90, weightScale: 1.12, spanScale: 1.02,
                               eyeOffset: eyeOffsetBase, dropShadow: false,
                               softDetail: true, snapToPixels: false)
        case ...128:
            return SizeProfile(bodyRatio: 0.86, weightScale: 1.04, spanScale: 1,
                               eyeOffset: eyeOffsetBase, dropShadow: true,
                               softDetail: true, snapToPixels: false)
        default:
            return SizeProfile(bodyRatio: macOSBodyRatio, weightScale: 1, spanScale: 1,
                               eyeOffset: eyeOffsetBase, dropShadow: true,
                               softDetail: true, snapToPixels: false)
        }
    }
}

// MARK: - Shapes

func squirclePath(in rect: CGRect) -> CGPath {
    RoundedRectangle(cornerRadius: rect.width * cornerRatio, style: .continuous)
        .path(in: rect)
        .cgPath
}

func capsulePath(center: CGPoint, width: CGFloat, height: CGFloat) -> CGPath {
    let rect = CGRect(x: center.x - width / 2, y: center.y - height / 2,
                      width: width, height: height)
    let radius = min(width, height) / 2
    return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius,
                  transform: nil)
}

func plusPath(center: CGPoint, span: CGFloat, weight: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.addPath(capsulePath(center: center, width: span, height: weight))
    path.addPath(capsulePath(center: center, width: weight, height: span))
    return path
}

// MARK: - Drawing

/// - Parameter fullBleed: true = body fills the canvas (Icon Composer, web).
///                        false = macOS grid, body inset inside the canvas.
func drawIcon(into ctx: CGContext, canvas: CGFloat, fullBleed: Bool) {
    let p = SizeProfile.forSize(Int(canvas), fullBleed: fullBleed)
    let body = (canvas * p.bodyRatio).rounded()
    let origin = ((canvas - body) / 2).rounded()
    let rect = CGRect(x: origin, y: origin, width: body, height: body)
    let shape = squirclePath(in: rect)

    ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0))
    ctx.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))

    if p.dropShadow {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -body * 0.012),
                      blur: body * 0.030,
                      color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.34))
        ctx.addPath(shape)
        ctx.setFillColor(fieldLeft.cg())
        ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    // The split field: the "after" on the left, the "before" on the right. The
    // boundary is snapped to a whole pixel so it never renders as a grey seam.
    let seam = (rect.midX).rounded()
    ctx.setFillColor(fieldLeft.cg())
    ctx.fill(CGRect(x: 0, y: 0, width: seam, height: canvas))
    ctx.setFillColor(fieldRight.cg())
    ctx.fill(CGRect(x: seam, y: 0, width: canvas - seam, height: canvas))

    if p.softDetail {
        drawVignette(ctx, rect: rect)
        drawRim(ctx, shape: shape, body: body)
    }
    ctx.restoreGState()

    drawEyes(ctx, rect: rect, body: body, profile: p)
}

func drawVignette(_ ctx: CGContext, rect: CGRect) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let gradient = CGGradient(colorsSpace: space,
                              colors: [CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0),
                                       CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.20)] as CFArray,
                              locations: [0, 1])!
    let center = CGPoint(x: rect.midX, y: rect.midY)
    ctx.drawRadialGradient(gradient,
                           startCenter: center, startRadius: rect.width * 0.30,
                           endCenter: center, endRadius: rect.width * 0.80,
                           options: .drawsAfterEndLocation)
}

/// A hairline of light caught on the top edge, and a darker lip along the bottom.
/// Both live inside the shape's own edge — never an outline drawn around it.
func drawRim(_ ctx: CGContext, shape: CGPath, body: CGFloat) {
    ctx.saveGState()
    ctx.setLineWidth(body * 0.007)
    ctx.addPath(shape)
    ctx.replacePathWithStrokedPath()
    ctx.clip()

    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let bounds = shape.boundingBox

    let highlight = CGGradient(colorsSpace: space,
                               colors: [CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0),
                                        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.16)] as CFArray,
                               locations: [0.42, 1])!
    ctx.drawLinearGradient(highlight,
                           start: CGPoint(x: bounds.midX, y: bounds.minY),
                           end: CGPoint(x: bounds.midX, y: bounds.maxY),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    let lip = CGGradient(colorsSpace: space,
                         colors: [CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.28),
                                  CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0)] as CFArray,
                         locations: [0, 0.28])!
    ctx.drawLinearGradient(lip,
                           start: CGPoint(x: bounds.midX, y: bounds.minY),
                           end: CGPoint(x: bounds.midX, y: bounds.maxY),
                           options: [])
    ctx.restoreGState()
}

func drawEyes(_ ctx: CGContext, rect: CGRect, body: CGFloat, profile p: SizeProfile) {
    var weight = body * strokeWeight * p.weightScale
    var span = body * markSpan * p.spanScale
    var offset = body * p.eyeOffset

    // At small sizes an unsnapped edge lands mid-pixel and the mark greys out.
    if p.snapToPixels {
        weight = max(2, weight.rounded())
        span = max(weight + 2, span.rounded())
        offset = offset.rounded()
    }

    let y = p.snapToPixels ? rect.midY.rounded() : rect.midY
    let cx = p.snapToPixels ? rect.midX.rounded() : rect.midX

    let plus = plusPath(center: CGPoint(x: cx - offset, y: y), span: span, weight: weight)
    let minus = capsulePath(center: CGPoint(x: cx + offset, y: y),
                            width: span * minusSpanBoost,
                            height: (weight * minusWeightBoost).rounded(p.snapToPixels))

    for (path, paint) in [(plus, sage), (minus, coral)] {
        ctx.saveGState()
        if p.softDetail {
            ctx.setShadow(offset: CGSize(width: 0, height: -body * 0.006),
                          blur: body * 0.014,
                          color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.38))
        }
        ctx.addPath(path)
        ctx.setFillColor(paint.cg())
        ctx.fillPath()
        ctx.restoreGState()
    }
}

extension CGFloat {
    func rounded(_ shouldRound: Bool) -> CGFloat { shouldRound ? self.rounded() : self }
}

// MARK: - Output

func render(size: Int, fullBleed: Bool, to url: URL) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: size, height: size,
                              bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("could not create a \(size)x\(size) bitmap context")
    }
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    drawIcon(into: ctx, canvas: CGFloat(size), fullBleed: fullBleed)

    guard let image = ctx.makeImage() else { fatalError("could not rasterise \(url.lastPathComponent)") }
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("could not open \(url.path) for writing")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(url.path)") }
}

/// The monochrome symbol: marks only, black on transparent, no container, no effects.
func renderSymbol(size: Int, to url: URL) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: size, height: size / 2,
                              bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("could not create the symbol context")
    }
    let canvas = CGFloat(size)
    let body = canvas
    let rect = CGRect(x: 0, y: CGFloat(size) / 2 - body / 2, width: body, height: body)
    let weight = body * strokeWeight
    let span = body * markSpan
    let y = rect.midY
    let plus = plusPath(center: CGPoint(x: rect.midX - body * eyeOffsetBase, y: y),
                        span: span, weight: weight)
    let minus = capsulePath(center: CGPoint(x: rect.midX + body * eyeOffsetBase, y: y),
                            width: span * minusSpanBoost, height: weight * minusWeightBoost)
    ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    ctx.addPath(plus); ctx.fillPath()
    ctx.addPath(minus); ctx.fillPath()

    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("could not write the symbol")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write the symbol") }
}

// MARK: - Vector master

func svgPathData(_ path: CGPath) -> String {
    var out = ""
    func fmt(_ v: CGFloat) -> String { String(format: "%.3f", v) }
    path.applyWithBlock { element in
        let points = element.pointee.points
        switch element.pointee.type {
        case .moveToPoint:
            out += "M\(fmt(points[0].x)) \(fmt(points[0].y)) "
        case .addLineToPoint:
            out += "L\(fmt(points[0].x)) \(fmt(points[0].y)) "
        case .addQuadCurveToPoint:
            out += "Q\(fmt(points[0].x)) \(fmt(points[0].y)) \(fmt(points[1].x)) \(fmt(points[1].y)) "
        case .addCurveToPoint:
            out += "C\(fmt(points[0].x)) \(fmt(points[0].y)) \(fmt(points[1].x)) \(fmt(points[1].y)) \(fmt(points[2].x)) \(fmt(points[2].y)) "
        case .closeSubpath:
            out += "Z "
        @unknown default:
            break
        }
    }
    return out.trimmingCharacters(in: .whitespaces)
}

func writeSVG(to url: URL) {
    let s: CGFloat = 1024
    let rect = CGRect(x: 0, y: 0, width: s, height: s)
    let shape = svgPathData(squirclePath(in: rect))
    let weight = s * strokeWeight
    let span = s * markSpan
    let cy = s / 2
    let plusX = s / 2 - s * eyeOffsetBase
    let minusX = s / 2 + s * eyeOffsetBase
    let minusW = span * minusSpanBoost
    let minusH = weight * minusWeightBoost

    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
      <defs>
        <clipPath id="squircle"><path d="\(shape)"/></clipPath>
        <radialGradient id="vignette" cx="50%" cy="50%" r="80%">
          <stop offset="37%" stop-color="#000" stop-opacity="0"/>
          <stop offset="100%" stop-color="#000" stop-opacity="0.20"/>
        </radialGradient>
        <linearGradient id="rim" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="#fff" stop-opacity="0.16"/>
          <stop offset="58%" stop-color="#fff" stop-opacity="0"/>
          <stop offset="72%" stop-color="#000" stop-opacity="0"/>
          <stop offset="100%" stop-color="#000" stop-opacity="0.28"/>
        </linearGradient>
        <filter id="contact" x="-30%" y="-30%" width="160%" height="160%">
          <feDropShadow dx="0" dy="\(String(format: "%.1f", s * 0.006))" stdDeviation="\(String(format: "%.1f", s * 0.007))" flood-color="#000" flood-opacity="0.38"/>
        </filter>
      </defs>

      <g clip-path="url(#squircle)">
        <rect x="0" y="0" width="512" height="1024" fill="\(fieldLeft.hexString)"/>
        <rect x="512" y="0" width="512" height="1024" fill="\(fieldRight.hexString)"/>
        <rect x="0" y="0" width="1024" height="1024" fill="url(#vignette)"/>
      </g>
      <path d="\(shape)" fill="none" stroke="url(#rim)" stroke-width="\(String(format: "%.2f", s * 0.007))" clip-path="url(#squircle)"/>

      <g filter="url(#contact)">
        <rect x="\(fmtNum(plusX - span / 2))" y="\(fmtNum(cy - weight / 2))" width="\(fmtNum(span))" height="\(fmtNum(weight))" rx="\(fmtNum(weight / 2))" fill="\(sage.hexString)"/>
        <rect x="\(fmtNum(plusX - weight / 2))" y="\(fmtNum(cy - span / 2))" width="\(fmtNum(weight))" height="\(fmtNum(span))" rx="\(fmtNum(weight / 2))" fill="\(sage.hexString)"/>
        <rect x="\(fmtNum(minusX - minusW / 2))" y="\(fmtNum(cy - minusH / 2))" width="\(fmtNum(minusW))" height="\(fmtNum(minusH))" rx="\(fmtNum(minusH / 2))" fill="\(coral.hexString)"/>
      </g>
    </svg>
    """
    try! svg.write(to: url, atomically: true, encoding: .utf8)
}

func fmtNum(_ v: CGFloat) -> String { String(format: "%.2f", v) }

// MARK: - Main

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
                 ? CommandLine.arguments[1]
                 : FileManager.default.currentDirectoryPath)

let iconset = outDir.appendingPathComponent("DitGiff.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// The ten files a macOS .iconset / .appiconset expects.
let slots: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in slots {
    render(size: px, fullBleed: false, to: iconset.appendingPathComponent("\(name).png"))
}

render(size: 1024, fullBleed: true, to: outDir.appendingPathComponent("icon-1024-fullbleed.png"))
render(size: 1024, fullBleed: false, to: outDir.appendingPathComponent("icon-1024-macos-grid.png"))
renderSymbol(size: 1024, to: outDir.appendingPathComponent("symbol-monochrome.png"))
writeSVG(to: outDir.appendingPathComponent("icon.svg"))

print("rendered \(slots.count) iconset slots + masters into \(outDir.path)")
