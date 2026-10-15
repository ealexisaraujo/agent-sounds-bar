// Draws the app icon's foreground layers (glyph shapes on transparent 1024x1024 canvases) into
// Resources/AppIcon.icon/Assets. The background gradient, glass and shadows live in icon.json;
// build.sh compiles the bundle with actool. Open Resources/AppIcon.icon in Icon Composer to tweak.
// Usage: swift scripts/draw-icon-layers.swift [out-dir]
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let glyphScale: CGFloat = 1.14
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icon/Assets"

func canvas(_ draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setShouldAntialias(true)
    // Scale the whole glyph around the canvas center so its proportions stay in one place.
    ctx.translateBy(x: 512, y: 512); ctx.scaleBy(x: glyphScale, y: glyphScale); ctx.translateBy(x: -512, y: -512)
    draw(ctx)
    return ctx.makeImage()!
}

func save(_ img: CGImage, _ name: String) {
    let url = URL(fileURLWithPath: out).appendingPathComponent(name) as CFURL
    let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
}

/// Polygon with every corner rounded by `r`.
func roundedPolygon(_ p: [CGPoint], _ r: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let n = p.count
    let mid = CGPoint(x: (p[n - 1].x + p[0].x) / 2, y: (p[n - 1].y + p[0].y) / 2)
    path.move(to: mid)
    for i in 0..<n { path.addArc(tangent1End: p[i], tangent2End: p[(i + 1) % n], radius: r) }
    path.closeSubpath()
    return path
}

let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
let c = CGPoint(x: 512, y: 512)

// Speaker: magnet box + cone, one rounded shape.
let speaker = canvas { ctx in
    let pts = [CGPoint(x: 250, y: 430), CGPoint(x: 352, y: 430), CGPoint(x: 516, y: 286),
               CGPoint(x: 516, y: 738), CGPoint(x: 352, y: 594), CGPoint(x: 250, y: 594)]
    ctx.addPath(roundedPolygon(pts, 34))
    ctx.setFillColor(white)
    ctx.fillPath()
}

// Two sound waves.
let waves = canvas { ctx in
    ctx.setStrokeColor(white)
    ctx.setLineWidth(60)
    ctx.setLineCap(.round)
    let o = CGPoint(x: 536, y: c.y)
    for (r, span) in [(CGFloat(122), CGFloat.pi * 0.25), (CGFloat(236), CGFloat.pi * 0.24)] {
        ctx.addArc(center: o, radius: r, startAngle: -span, endAngle: span, clockwise: false)
        ctx.strokePath()
    }
}

// Four-point spark: the "agent" accent.
let spark = canvas { ctx in
    let sc = CGPoint(x: 780, y: 780), R: CGFloat = 72, k: CGFloat = 0.2
    let path = CGMutablePath()
    for i in 0..<4 {
        let a = CGFloat(i) * .pi / 2
        let tip = CGPoint(x: sc.x + R * cos(a), y: sc.y + R * sin(a))
        let next = CGPoint(x: sc.x + R * cos(a + .pi / 2), y: sc.y + R * sin(a + .pi / 2))
        if i == 0 { path.move(to: tip) }
        // Concave sides: curve through a control point pulled toward the center.
        let ctrl = CGPoint(x: sc.x + R * k * cos(a + .pi / 4), y: sc.y + R * k * sin(a + .pi / 4))
        path.addQuadCurve(to: next, control: ctrl)
    }
    path.closeSubpath()
    ctx.addPath(path)
    ctx.setFillColor(CGColor(red: 1, green: 0.84, blue: 0.40, alpha: 1))
    ctx.fillPath()
}

save(speaker, "speaker.png")
save(waves, "waves.png")
save(spark, "spark.png")
print("layers written to \(out)")
