import Foundation

/// Sizes used to draw and validate pipes, in units of the hex circumradius.
public struct TileStyle: Hashable, Sendable {
    public var portsPerEdge: Int

    public init(portsPerEdge: Int) {
        self.portsPerEdge = portsPerEdge
    }

    /// Full width of a pipe including its walls.
    public var pipeWidth: Double { 0.7 / Double(portsPerEdge) }

    public var wallThickness: Double { pipeWidth * 0.2 }

    /// Width used by the overlap rule. Slightly narrower than the drawn pipe,
    /// so pipes that only graze each other are allowed.
    public var clearanceWidth: Double { pipeWidth * 0.8 }

    /// Size of the no-crossing zone at the bend of a corner pipe.
    public var elbowDiameter: Double { pipeWidth * 1.1 }

    public func roomDiameter(for kind: PipeKind) -> Double? {
        let height = HexGeometry.inradius * 2
        switch kind {
        case .roomSmall: return height * 0.31
        case .roomMedium: return height * 0.62
        case .roomLarge: return height * 0.93
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
        let start = HexGeometry.position(of: pipe.a, portsPerEdge: count)
        let end = HexGeometry.position(of: pipe.b, portsPerEdge: count)
        let startDirection = HexGeometry.inwardDirection(edge: pipe.a.edge)
        let endDirection = HexGeometry.inwardDirection(edge: pipe.b.edge)
        let sameEdge = pipe.a.edge == pipe.b.edge
        let opposite = pipe.a.isOnOppositeEdge(from: pipe.b)
        let midpoint = (start + end) * 0.5
        // Where lines running straight in from each port cross. Nil when the
        // ports are on the same or opposite edges and the lines are parallel.
        let meeting = Self.intersection(start, startDirection, end, endDirection)

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
                    : opposite ? HexGeometry.inradius * 2 * 0.66 : 0.5
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
