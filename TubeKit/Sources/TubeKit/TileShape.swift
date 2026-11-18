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
    /// The Cairo pentagon with five equal edges: two right angles, with a
    /// wide corner between them at the bottom and a flat edge opposite it
    /// at the top. It is its own mirror image left to right, and looks the
    /// same no other way.
    case cairo
    /// A regular octagon with a flat top.
    case octagon

    public var edgeCount: Int {
        switch self {
        case .hexagon: 6
        case .square: 4
        case .cairo: 5
        case .octagon: 8
        }
    }

    /// Whether every edge and corner is alike, so the tile can be turned
    /// one edge at a time.
    public var isRegular: Bool {
        switch self {
        case .hexagon, .square, .octagon: true
        case .cairo: false
        }
    }

    // The Cairo pentagon's measurements. With the flat edge from
    // (-1/2, 0) to (1/2, 0), the two right-angled corners are at
    // (-s, s) and (s, s), and the wide corner at (0, s - c), where
    // c = (1 - root 7) / 4 is the cosine of the angle at each end of
    // the flat edge and s is its sine.
    static let cairoCosine = (1 - (7.0).squareRoot()) / 4
    static let cairoSine = (1 - cairoCosine * cairoCosine).squareRoot()
    /// Half the pentagon's height, from flat edge to wide corner.
    static let cairoHalfHeight = (cairoSine - cairoCosine) / 2

    private static let cairoCorners: [Point] = [
        Point(x: -0.5, y: -cairoHalfHeight),
        Point(x: 0.5, y: -cairoHalfHeight),
        Point(x: cairoSine, y: (cairoSine + cairoCosine) / 2),
        Point(x: 0, y: cairoHalfHeight),
        Point(x: -cairoSine, y: (cairoSine + cairoCosine) / 2),
    ]

    /// Distance from the centre to the furthest corner.
    public var circumradius: Double {
        switch self {
        case .hexagon: 1
        case .square: (0.5).squareRoot()
        case .octagon: 0.5 / sin(.pi / 8)
        case .cairo: Self.cairoCorners.map { $0.distance(to: .zero) }.max() ?? 1
        }
    }

    /// Distance from the centre to the nearest edge.
    public var inradius: Double {
        switch self {
        case .hexagon: (3.0).squareRoot() / 2
        case .square: 0.5
        case .octagon: 0.5 / tan(.pi / 8)
        case .cairo:
            (0..<edgeCount).map { edge in
                let offset = Point.zero - corner(edge)
                let inward = inwardDirection(edge: edge)
                return offset.x * inward.x + offset.y * inward.y
            }.min() ?? 0.5
        }
    }

    /// Degrees turned from one edge of a regular shape to the next.
    private var step: Double { 360.0 / Double(edgeCount) }

    public func corner(_ index: Int) -> Point {
        switch self {
        case .hexagon, .square, .octagon:
            let angle = (-90.0 - step / 2 + step * Double(index)) * .pi / 180
            return Point(x: cos(angle), y: sin(angle)) * circumradius
        case .cairo:
            return Self.cairoCorners[((index % 5) + 5) % 5]
        }
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
        switch self {
        case .hexagon, .square, .octagon:
            let angle = (90.0 + step * Double(edge)) * .pi / 180
            return Point(x: cos(angle), y: sin(angle))
        case .cairo:
            // Corners run clockwise on screen, so inwards is a quarter turn
            // clockwise from the way the edge runs.
            let along = corner(edge + 1) - corner(edge)
            let length = (along.x * along.x + along.y * along.y).squareRoot()
            return Point(x: -along.y / length, y: along.x / length)
        }
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

    /// Every way a tile of this shape can be placed. A regular shape can be
    /// turned to any edge, and flipped and then turned. The Cairo pentagon
    /// can only be left as it is or flipped.
    public var transforms: [TileTransform] {
        switch self {
        case .hexagon, .square, .octagon:
            TileTransform.all(sides: edgeCount)
        case .cairo:
            [TileTransform(sides: edgeCount), TileTransform(mirrored: true, sides: edgeCount)]
        }
    }

    /// The width and height of the outline.
    public var size: (width: Double, height: Double) {
        let all = corners
        let xs = all.map(\.x)
        let ys = all.map(\.y)
        return ((xs.max() ?? 0) - (xs.min() ?? 0), (ys.max() ?? 0) - (ys.min() ?? 0))
    }
}
