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
/// circumradius of 1.
///
/// Corners and edges are numbered clockwise on screen. Edge 0 is the top edge
/// and runs from corner 0 (upper left) to corner 1 (upper right); edge `e`
/// runs from corner `e` to corner `e + 1`.
public enum HexGeometry {
    public static let edgeCount = 6

    public static func corner(_ index: Int) -> Point {
        let angle = (-120.0 + 60.0 * Double(index)) * .pi / 180
        return Point(x: cos(angle), y: sin(angle))
    }

    /// Where a port sits on its edge. Ports are spaced evenly, leaving the
    /// same gap at the corners as between neighbours.
    public static func position(of port: Port, portsPerEdge: Int) -> Point {
        let start = corner(port.edge)
        let end = corner(port.edge + 1)
        let t = Double(port.slot + 1) / Double(portsPerEdge + 1)
        return start + (end - start) * t
    }

    /// Unit vector pointing from an edge into the tile, perpendicular to it.
    public static func inwardDirection(edge: Int) -> Point {
        let angle = (90.0 + 60.0 * Double(edge)) * .pi / 180
        return Point(x: cos(angle), y: sin(angle))
    }

    /// Distance from the centre to the middle of an edge.
    public static let inradius = (3.0).squareRoot() / 2
}
