import Foundation

/// A point or vector in tile space. Y grows downward, as on screen.
public struct Point: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Point(x: 0, y: 0)

    public static func + (lhs: Point, rhs: Point) -> Point {
        Point(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    public static func - (lhs: Point, rhs: Point) -> Point {
        Point(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    public static func * (lhs: Point, rhs: Double) -> Point {
        Point(x: lhs.x * rhs, y: lhs.y * rhs)
    }

    public func distance(to other: Point) -> Double {
        ((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y)).squareRoot()
    }
}

/// Geometry of a single flat-top hex tile centred on the origin with a
/// circumradius of 1. This is `TileShape.hexagon` under its older name, kept
/// for the hex grid that mazes are laid out on.
public enum HexGeometry {
    public static let edgeCount = TileShape.hexagon.edgeCount

    public static func corner(_ index: Int) -> Point {
        TileShape.hexagon.corner(index)
    }

    public static func position(of port: Port, portsPerEdge: Int) -> Point {
        TileShape.hexagon.position(of: port, portsPerEdge: portsPerEdge)
    }

    public static func inwardDirection(edge: Int) -> Point {
        TileShape.hexagon.inwardDirection(edge: edge)
    }

    /// Distance from the centre to the middle of an edge.
    public static let inradius = TileShape.hexagon.inradius
}
