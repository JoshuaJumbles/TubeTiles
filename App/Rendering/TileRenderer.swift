import SwiftUI
import TubeKit

/// Where a tile sits in a view: converts between tile units and view points.
struct TileFrame {
    var center: CGPoint
    /// View points per tile unit (the hex circumradius).
    var scale: CGFloat

    init(center: CGPoint, scale: CGFloat) {
        self.center = center
        self.scale = scale
    }

    /// The largest frame that fits a whole hex inside `size`.
    init(fitting size: CGSize, padding: CGFloat = 0) {
        center = CGPoint(x: size.width / 2, y: size.height / 2)
        let width = max(1, size.width - padding * 2)
        let height = max(1, size.height - padding * 2)
        scale = min(width / 2, height / (HexGeometry.inradius * 2))
    }

    func point(_ point: Point) -> CGPoint {
        CGPoint(x: center.x + point.x * scale, y: center.y + point.y * scale)
    }

    func tilePoint(_ point: CGPoint) -> Point {
        Point(x: (point.x - center.x) / scale, y: (point.y - center.y) / scale)
    }
}

extension Color {
    /// A colour that follows the system appearance.
    init(light: Color, dark: Color) {
        self.init(UIColor { traits in
            UIColor(traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

/// Colours a tile is drawn with. In light mode tiles are dark walls on
/// cream; in dark mode, light walls on charcoal.
struct TilePalette {
    /// Pipe walls.
    var ink: Color = Color(light: Color(white: 0.08), dark: Color(red: 0.93, green: 0.91, blue: 0.87))
    /// Pipe interiors.
    var tube: Color = Color(light: .white, dark: Color(red: 0.05, green: 0.05, blue: 0.06))

    /// The blank surface of a tile.
    static let face = Color(
        light: Color(red: 0.99, green: 0.98, blue: 0.95), dark: Color(red: 0.15, green: 0.155, blue: 0.17)
    )
    /// The hex border and free port markers.
    static let outline = Color(light: Color(white: 0.25), dark: Color(white: 0.72))
    /// The backdrop tiles are shown on.
    static let paper = Color(
        light: Color(red: 0.93, green: 0.91, blue: 0.86), dark: Color(red: 0.07, green: 0.07, blue: 0.08)
    )
    /// A cell of a maze that has no tile.
    static let emptyCell = Color(
        light: Color(red: 0.90, green: 0.88, blue: 0.82), dark: Color(red: 0.10, green: 0.10, blue: 0.11)
    )
    /// Marks things that are allowed or present.
    static let positive = Color(
        light: Color(red: 0.10, green: 0.52, blue: 0.34), dark: Color(red: 0.30, green: 0.78, blue: 0.55)
    )
    /// Marks things that are missing or refused.
    static let negative = Color(
        light: Color(red: 0.72, green: 0.25, blue: 0.20), dark: Color(red: 0.95, green: 0.48, blue: 0.42)
    )

    static let standard = TilePalette()
    static let rejected = TilePalette(
        ink: Color(light: Color(red: 0.80, green: 0.16, blue: 0.14), dark: Color(red: 1.0, green: 0.45, blue: 0.40)),
        tube: Color(light: Color(red: 1, green: 0.92, blue: 0.90), dark: Color(red: 0.30, green: 0.08, blue: 0.07))
    )
    static let selected = TilePalette(ink: Color.accentColor)
}

/// Draws tiles and pipes. Every screen that shows a tile goes through here.
enum TileRenderer {
    static func hexPath(in frame: TileFrame) -> Path {
        var path = Path()
        path.move(to: frame.point(HexGeometry.corner(0)))
        for index in 1..<HexGeometry.edgeCount {
            path.addLine(to: frame.point(HexGeometry.corner(index)))
        }
        path.closeSubpath()
        return path
    }

    static func centerLine(of shape: PipeShape, in frame: TileFrame) -> Path {
        var path = Path()
        for (index, segment) in shape.segments.enumerated() {
            switch segment {
            case let .line(start, end):
                if index == 0 { path.move(to: frame.point(start)) }
                path.addLine(to: frame.point(end))
            case let .cubic(start, control1, control2, end):
                if index == 0 { path.move(to: frame.point(start)) }
                path.addCurve(
                    to: frame.point(end),
                    control1: frame.point(control1),
                    control2: frame.point(control2)
                )
            }
        }
        return path
    }

    private static func disc(_ disc: Disc, inset: Double = 0, in frame: TileFrame) -> Path {
        let radius = (disc.diameter / 2 - inset) * frame.scale
        let center = frame.point(disc.center)
        return Path(ellipseIn: CGRect(
            x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2
        ))
    }

    /// Draws one pipe: walls first, then the hollow interior on top.
    static func draw(
        _ pipe: Pipe,
        style: TileStyle,
        in frame: TileFrame,
        context: inout GraphicsContext,
        palette: TilePalette = .standard
    ) {
        let shape = PipeShape(pipe, style: style)
        let line = centerLine(of: shape, in: frame)
        let outer = StrokeStyle(lineWidth: style.pipeWidth * frame.scale, lineCap: .round, lineJoin: .round)
        let inner = StrokeStyle(
            lineWidth: (style.pipeWidth - style.wallThickness * 2) * frame.scale,
            lineCap: .round, lineJoin: .round
        )

        context.stroke(line, with: .color(palette.ink), style: outer)
        if let room = shape.room {
            context.fill(disc(room, in: frame), with: .color(palette.ink))
        }
        context.stroke(line, with: .color(palette.tube), style: inner)
        if let room = shape.room {
            context.fill(disc(room, inset: style.wallThickness, in: frame), with: .color(palette.tube))
        }
    }

    /// Redraws the upper pipe for a short way either side of a crossing, so
    /// it passes over the pipe beneath whatever order the two were drawn in.
    static func drawBridge(
        _ crossing: Crossing,
        style: TileStyle,
        in frame: TileFrame,
        context: inout GraphicsContext,
        palette: TilePalette = .standard
    ) {
        let line = Polyline(PipeShape(crossing.over, style: style))
        let half = crossing.bridgeHalfLength(style: style)
        let points = line.slice(from: crossing.overDistance - half, to: crossing.overDistance + half)
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: frame.point(first))
        for point in points.dropFirst() {
            path.addLine(to: frame.point(point))
        }
        context.stroke(
            path, with: .color(palette.ink),
            style: StrokeStyle(lineWidth: style.pipeWidth * frame.scale, lineCap: .butt, lineJoin: .round)
        )
        context.stroke(
            path, with: .color(palette.tube),
            style: StrokeStyle(
                lineWidth: (style.pipeWidth - style.wallThickness * 2) * frame.scale,
                lineCap: .butt, lineJoin: .round
            )
        )
    }

    /// Draws every pipe of a tile in stacking order, clipped to the hex.
    static func draw(
        _ tile: Tile,
        in frame: TileFrame,
        context: inout GraphicsContext,
        palette: TilePalette = .standard
    ) {
        var clipped = context
        clipped.clip(to: hexPath(in: frame))
        let style = TileStyle(portsPerEdge: tile.portsPerEdge)
        for pipe in tile.pipes {
            draw(pipe, style: style, in: frame, context: &clipped, palette: palette)
        }
    }
}
