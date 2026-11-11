import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Draws the TubeTiles app icon: a hex tile with three pipes woven in a
// pinwheel. Usage: swift make_icon.swift <output.png>

let size = 1024.0
let center = CGPoint(x: size / 2, y: size / 2)
let radius = 400.0
let portsPerEdge = 3

func corner(_ index: Int) -> CGPoint {
    let angle = (-120.0 + 60.0 * Double(index)) * .pi / 180
    return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
}

func port(edge: Int, slot: Int) -> CGPoint {
    let a = corner(edge), b = corner(edge + 1)
    let t = Double(slot + 1) / Double(portsPerEdge + 1)
    return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
}

func inward(edge: Int) -> CGPoint {
    let angle = (90.0 + 60.0 * Double(edge)) * .pi / 180
    return CGPoint(x: cos(angle), y: sin(angle))
}

/// A curve between two ports, shaped like the app's curved pipes.
struct Curve {
    var p0: CGPoint, c0: CGPoint, c1: CGPoint, p1: CGPoint

    init(from: (Int, Int), to: (Int, Int)) {
        p0 = port(edge: from.0, slot: from.1)
        p1 = port(edge: to.0, slot: to.1)
        let d0 = inward(edge: from.0), d1 = inward(edge: to.0)
        let cross = d0.x * d1.y - d0.y * d1.x
        let t = ((p1.x - p0.x) * d1.y - (p1.y - p0.y) * d1.x) / cross
        let meet = CGPoint(x: p0.x + d0.x * t, y: p0.y + d0.y * t)
        c0 = CGPoint(x: (p0.x + meet.x) / 2, y: (p0.y + meet.y) / 2)
        c1 = CGPoint(x: (p1.x + meet.x) / 2, y: (p1.y + meet.y) / 2)
    }

    func point(_ t: Double) -> CGPoint {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return CGPoint(x: a * p0.x + b * c0.x + c * c1.x + d * p1.x, y: a * p0.y + b * c0.y + c * c1.y + d * p1.y)
    }

    func path(from start: Double = 0, to end: Double = 1) -> CGPath {
        let path = CGMutablePath()
        let steps = 80
        for step in 0...steps {
            let point = point(start + (end - start) * Double(step) / Double(steps))
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!
// Work with the origin at the top left, like the app.
context.translateBy(x: 0, y: size)
context.scaleBy(x: 1, y: -1)

func color(_ r: Double, _ g: Double, _ b: Double) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, 1])!
}

// Background: the app's blue, a little deeper towards the bottom.
let gradient = CGGradient(
    colorsSpace: space,
    colors: [color(0.16, 0.48, 0.80), color(0.07, 0.27, 0.52)] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size), options: [])

// The tile.
let hex = CGMutablePath()
hex.move(to: corner(0))
for index in 1..<6 { hex.addLine(to: corner(index)) }
hex.closeSubpath()
context.addPath(hex)
context.setFillColor(color(0.99, 0.98, 0.95))
context.fillPath()

let ink = color(0.08, 0.08, 0.09)
let tube = color(1, 1, 1)
let wall = 88.0
let inner = 50.0

func draw(_ path: CGPath, cap: CGLineCap) {
    context.setLineCap(cap)
    context.setLineJoin(.round)
    context.addPath(path)
    context.setStrokeColor(ink)
    context.setLineWidth(wall)
    context.strokePath()
    context.addPath(path)
    context.setStrokeColor(tube)
    context.setLineWidth(inner)
    context.strokePath()
}

// Three pipes, each a third of a turn from the last, crossing in a triangle.
let curves = [
    Curve(from: (0, 0), to: (2, 2)),
    Curve(from: (2, 0), to: (4, 2)),
    Curve(from: (4, 0), to: (0, 2)),
]

context.saveGState()
context.addPath(hex)
context.clip()
for curve in curves {
    draw(curve.path(), cap: .round)
}

// Each later pipe now lies over the earlier ones. For a true weave the first
// must pass over the last, so redraw a short piece of it where they cross.
var best = (distance: Double.infinity, t: 0.0)
for i in 0...400 {
    let a = curves[0].point(Double(i) / 400)
    for j in 0...400 {
        let b = curves[2].point(Double(j) / 400)
        let distance = hypot(a.x - b.x, a.y - b.y)
        if distance < best.distance { best = (distance, Double(i) / 400) }
    }
}
draw(curves[0].path(from: best.t - 0.17, to: best.t + 0.17), cap: .butt)
context.restoreGState()

let image = context.makeImage()!
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
print("wrote \(url.path)")
