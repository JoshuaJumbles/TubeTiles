import Foundation

/// The outline of a tile: how many edges it has, where its corners and ports
/// are, and which turns and flips map it onto itself.
///
/// Everything that reads a tile's geometry asks its shape, so a new shape is
/// a new case here rather than new code elsewhere. Shapes are centred on the
/// origin with edges one unit long, which keeps ports the same distance
/// apart whatever the shape.
///
/// Corners and edges are numbered clockwise on screen. Edge 0 is the top
/// edge and runs from corner 0 (upper left) to corner 1 (upper right); edge
/// `e` runs from corner `e` to corner `e + 1`.
public enum TileShape: String, Hashable, Sendable, Codable, CaseIterable {
    /// A regular hexagon with a flat top.
    case hexagon
    /// A square with its edges level and upright.
    case square

    public var edgeCount: Int {
        switch self {
        case .hexagon: 6
        case .square: 4
        }
    }

    /// Distance from the centre to a corner.
    public var circumradius: Double {
        switch self {
        case .hexagon: 1
        case .square: (0.5).squareRoot()
        }
    }

    /// Distance from the centre to the middle of an edge.
    public var inradius: Double {
        switch self {
        case .hexagon: (3.0).squareRoot() / 2
        case .square: 0.5
        }
    }

    /// Degrees turned from one edge to the next.
    private var step: Double { 360.0 / Double(edgeCount) }

    public func corner(_ index: Int) -> Point {
        let angle = (-90.0 - step / 2 + step * Double(index)) * .pi / 180
        return Point(x: cos(angle), y: sin(angle)) * circumradius
    }

    public var corners: [Point] {
        (0..<edgeCount).map(corner)
    }

    /// Where a port sits on its edge. Ports are spaced evenly, leaving the
    /// same gap at the corners as between neighbours.
    public func position(of port: Port, portsPerEdge: Int) -> Point {
        let start = corner(port.edge)
        let end = corner(port.edge + 1)
        let t = Double(port.slot + 1) / Double(portsPerEdge + 1)
        return start + (end - start) * t
    }

    /// Unit vector pointing from an edge into the tile, perpendicular to it.
    public func inwardDirection(edge: Int) -> Point {
        let angle = (90.0 + step * Double(edge)) * .pi / 180
        return Point(x: cos(angle), y: sin(angle))
    }

    /// Whether a point is inside the outline.
    public func contains(_ point: Point) -> Bool {
        for edge in 0..<edgeCount {
            let inward = inwardDirection(edge: edge)
            let offset = point - corner(edge)
            if offset.x * inward.x + offset.y * inward.y < -1e-9 { return false }
        }
        return true
    }

    /// Whether two edges face each other across the tile.
    public func areOpposite(_ first: Int, _ second: Int) -> Bool {
        edgeCount % 2 == 0 && (first + edgeCount / 2) % edgeCount == second
    }

    /// Whether two ports look straight at each other across the tile.
    public func faces(_ first: Port, _ second: Port, portsPerEdge: Int) -> Bool {
        areOpposite(first.edge, second.edge) && second.slot == portsPerEdge - 1 - first.slot
    }

    public func isValid(_ port: Port, portsPerEdge: Int) -> Bool {
        (0..<edgeCount).contains(port.edge) && (0..<portsPerEdge).contains(port.slot)
    }

    /// Every port of a tile of this shape, edge by edge.
    public func ports(portsPerEdge: Int) -> [Port] {
        (0..<edgeCount).flatMap { edge in (0..<portsPerEdge).map { Port(edge: edge, slot: $0) } }
    }

    /// Every way a tile of this shape can be placed: turned, or flipped and
    /// then turned.
    public var transforms: [TileTransform] {
        TileTransform.all(sides: edgeCount)
    }

    /// The width and height of the outline.
    public var size: (width: Double, height: Double) {
        let all = corners
        let xs = all.map(\.x)
        let ys = all.map(\.y)
        return ((xs.max() ?? 0) - (xs.min() ?? 0), (ys.max() ?? 0) - (ys.min() ?? 0))
    }
}
