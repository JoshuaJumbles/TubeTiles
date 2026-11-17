import Foundation

/// How thick pipes are, set once for a whole library.
///
/// This is more than a look. Thicker pipes take up more room, so some turns
/// that clear each other when thin collide when thick, and fewer pipes fit
/// near the edge of a maze's bounds.
public struct PipeGauge: Hashable, Sendable, Codable {
    /// A pipe's full width, as a share of the space between two ports.
    public var width: Double
    /// Each wall, as a share of the pipe's width.
    public var wall: Double

    public static let widthRange = 0.3...0.95
    public static let wallRange = 0.06...0.4
    public static let standard = PipeGauge(width: 0.7, wall: 0.2)

    /// Values outside the ranges are brought to the nearest end.
    public init(width: Double, wall: Double) {
        self.width = min(max(width, Self.widthRange.lowerBound), Self.widthRange.upperBound)
        self.wall = min(max(wall, Self.wallRange.lowerBound), Self.wallRange.upperBound)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            width: try container.decode(Double.self, forKey: .width),
            wall: try container.decode(Double.self, forKey: .wall)
        )
    }
}

/// Sizes used to draw and validate pipes, in units of the hex circumradius.
public struct TileStyle: Hashable, Sendable {
    public var portsPerEdge: Int
    public var gauge: PipeGauge
    /// The outline of the tile the pipes are in.
    public var shape: TileShape

    public init(portsPerEdge: Int, gauge: PipeGauge = .standard, shape: TileShape = .hexagon) {
        self.portsPerEdge = portsPerEdge
        self.gauge = gauge
        self.shape = shape
    }

    /// Full width of a pipe including its walls.
    public var pipeWidth: Double { gauge.width / Double(portsPerEdge) }

    public var wallThickness: Double { pipeWidth * gauge.wall }

    /// Width used by the overlap rule. Slightly narrower than the drawn pipe,
    /// so pipes that only graze each other are allowed.
    public var clearanceWidth: Double { pipeWidth * 0.8 }

    /// Size of the no-crossing zone at the bend of a corner pipe.
    public var elbowDiameter: Double { pipeWidth * 1.1 }

    public func roomDiameter(for kind: PipeKind) -> Double? {
        let height = shape.inradius * 2
        switch kind {
        case .roomSmall: return height * 0.31
        case .roomMedium: return height * 0.62
        case .roomLarge: return height * 0.93
        // The largest dead end is a little smaller than the largest room,
        // so it fits whole inside the tile from any port near mid-edge.
        case .endSmall: return height * 0.31
        case .endMedium: return height * 0.55
        case .endLarge: return height * 0.80
        case .bezier, .corner: return nil
        }
    }
}

public enum PathSegment: Hashable, Sendable {
    case line(Point, Point)
    case cubic(Point, control1: Point, control2: Point, Point)

    /// Points along the segment, including both ends.
    public func flattened(steps: Int = 24) -> [Point] {
        switch self {
        case let .line(start, end):
            return [start, end]
        case let .cubic(p0, c0, c1, p1):
            return (0...steps).map { step in
                let t = Double(step) / Double(steps)
                let u = 1 - t
                return p0 * (u * u * u) + c0 * (3 * u * u * t) + c1 * (3 * u * t * t) + p1 * (t * t * t)
            }
        }
    }
}

public struct Disc: Hashable, Sendable {
    public var center: Point
    public var diameter: Double
}

/// The centre line of a pipe, plus its room if it has one.
///
/// This is the single description of a pipe's shape. Drawing, the overlap
/// rule and export all read from it.
public struct PipeShape: Hashable, Sendable {
    public var segments: [PathSegment]
    public var room: Disc?
    /// Where a corner pipe bends. Nothing else may cross here.
    public var elbow: Point?

    public init(_ pipe: Pipe, style: TileStyle) {
        let count = style.portsPerEdge
        let outline = style.shape
        let start = outline.position(of: pipe.a, portsPerEdge: count)
        let end = outline.position(of: pipe.b, portsPerEdge: count)
        let startDirection = outline.inwardDirection(edge: pipe.a.edge)
        let endDirection = outline.inwardDirection(edge: pipe.b.edge)
        let sameEdge = pipe.a.edge == pipe.b.edge
        let opposite = outline.areOpposite(pipe.a.edge, pipe.b.edge)
        let midpoint = (start + end) * 0.5
        // Where lines running straight in from each port cross. Nil when the
        // ports are on the same or opposite edges and the lines are parallel.
        var meeting = Self.intersection(start, startDirection, end, endDirection)
        // On a shape whose edges are not all alike, those lines can cross
        // outside the tile. A pipe bent towards such a point would leave the
        // tile, so it is drawn as if the lines never met.
        if let found = meeting, !outline.isRegular, !outline.contains(found) {
            meeting = nil
        }

        switch pipe.kind {
        case .bezier:
            let control1: Point
            let control2: Point
            if let meeting {
                control1 = start + (meeting - start) * 0.5
                control2 = end + (meeting - end) * 0.5
            } else {
                let reach = sameEdge
                    ? start.distance(to: end) * 0.75
                    : opposite ? outline.inradius * 2 * 0.66 : 0.5
                control1 = start + startDirection * reach
                control2 = end + endDirection * reach
            }
            segments = [.cubic(start, control1: control1, control2: control2, end)]

        case .corner:
            if let meeting {
                segments = [.line(start, meeting), .line(meeting, end)]
                elbow = meeting
            } else {
                segments = [.line(start, end)]
            }

        case .roomSmall, .roomMedium, .roomLarge:
            let center = meeting ?? midpoint
            segments = [.line(start, center), .line(center, end)]
            room = Disc(center: center, diameter: style.roomDiameter(for: pipe.kind) ?? 0)

        case .endSmall, .endMedium, .endLarge:
            // Straight in from the port, far enough for the room to clear
            // the edge it came from but never past the middle of the tile.
            let diameter = style.roomDiameter(for: pipe.kind) ?? 0
            let depth = min(diameter / 2 + style.pipeWidth, outline.inradius)
            let center = start + startDirection * depth
            segments = [.line(start, center)]
            room = Disc(center: center, diameter: diameter)
        }
    }

    private static func intersection(_ p: Point, _ d: Point, _ q: Point, _ e: Point) -> Point? {
        let cross = d.x * e.y - d.y * e.x
        guard abs(cross) > 1e-9 else { return nil }
        let delta = q - p
        let t = (delta.x * e.y - delta.y * e.x) / cross
        return p + d * t
    }
}
