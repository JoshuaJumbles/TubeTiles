import Foundation

/// Where a cell sits in the plane: its centre, and how far it is turned
/// from the way its shape is drawn. Everything inside a cell (ports, pipes,
/// corners) is worked out as if the cell were upright at the origin and then
/// put in place through its frame.
public struct CellFrame: Hashable, Sendable {
    public var center: Point
    /// Clockwise turn on screen, in radians.
    public var angle: Double

    public init(center: Point, angle: Double = 0) {
        self.center = center
        self.angle = angle
    }

    /// Where a point of the cell falls in the plane.
    public func place(_ local: Point) -> Point {
        center + turn(local)
    }

    /// A direction inside the cell, as it points in the plane.
    public func turn(_ direction: Point) -> Point {
        // Upright cells are left exactly as they are, not turned by nothing.
        guard angle != 0 else { return direction }
        return Point(
            x: direction.x * cos(angle) - direction.y * sin(angle),
            y: direction.x * sin(angle) + direction.y * cos(angle)
        )
    }

    /// Where a point of the plane falls inside the cell.
    public func local(_ point: Point) -> Point {
        let offset = point - center
        guard angle != 0 else { return offset }
        return Point(
            x: offset.x * cos(angle) + offset.y * sin(angle),
            y: -offset.x * sin(angle) + offset.y * cos(angle)
        )
    }
}

/// How tiles are laid out to cover the plane: where each cell sits, what
/// shape it is, and which edge of which neighbour lies across each of its
/// edges.
///
/// Mazes, the generator, bounds and the exports ask the tiling for all of
/// this, so a new tiling is a new case here rather than new code elsewhere.
/// A cell's address is a `HexCoord` whatever the tiling: two whole numbers,
/// read as the tiling sees fit.
public enum Tiling: String, Hashable, Sendable, Codable, CaseIterable {
    /// Flat-top hexagons in columns, every other column half a cell lower.
    case hexagonal
    /// Squares in rows and columns.
    case square

    /// The tiling whose cells have the given shape.
    public init(shape: TileShape) {
        switch shape {
        case .hexagon: self = .hexagonal
        case .square: self = .square
        }
    }

    /// The shape of a cell. Every cell is alike in the tilings so far; one
    /// that mixes shapes would answer by cell.
    public func shape(of cell: HexCoord) -> TileShape {
        switch self {
        case .hexagonal: .hexagon
        case .square: .square
        }
    }

    /// Centre of a cell, in units of a tile's edge.
    public func center(of cell: HexCoord) -> Point {
        switch self {
        case .hexagonal: cell.center
        // One unit a cell: `q` counts columns to the right, `r` rows down.
        case .square: Point(x: Double(cell.q), y: Double(cell.r))
        }
    }

    /// How far a cell is turned from the way its shape is drawn, clockwise
    /// in radians. Every cell is upright in the tilings so far.
    public func turn(of cell: HexCoord) -> Double {
        switch self {
        case .hexagonal, .square: 0
        }
    }

    /// Where a cell sits and how it is turned.
    public func frame(of cell: HexCoord) -> CellFrame {
        CellFrame(center: center(of: cell), angle: turn(of: cell))
    }

    /// The cell on the other side of an edge, and which of its edges that
    /// is. Both cells number their ports clockwise, so along the shared edge
    /// the numbering runs in opposite directions.
    public func neighbour(of cell: HexCoord, across edge: Int) -> (cell: HexCoord, edge: Int) {
        switch self {
        case .hexagonal:
            return (cell.neighbour(across: edge), (edge + 3) % 6)
        case .square:
            // Edges run top, right, bottom, left.
            let step = [(0, -1), (1, 0), (0, 1), (-1, 0)][edge]
            return (HexCoord(q: cell.q + step.0, r: cell.r + step.1), (edge + 2) % 4)
        }
    }

    /// The port that touches `port` of `cell`, on the cell across that edge.
    public func touching(_ port: Port, of cell: HexCoord, portsPerEdge: Int) -> PortRef {
        let other = neighbour(of: cell, across: port.edge)
        return PortRef(coord: other.cell, port: Port(edge: other.edge, slot: portsPerEdge - 1 - port.slot))
    }

    // MARK: Regions

    /// How many steps a cell is from the origin. An unmasked maze is every
    /// cell within some number of rings.
    public func ring(of cell: HexCoord) -> Int {
        switch self {
        case .hexagonal: cell.ring
        // Rings of squares are square, so a region is a square block.
        case .square: max(abs(cell.q), abs(cell.r))
        }
    }

    /// Every cell within `radius` rings of the origin, in a stable order.
    public func cells(radius: Int) -> [HexCoord] {
        (-radius...radius).flatMap { q in
            (-radius...radius).map { HexCoord(q: q, r: $0) }
        }.filter { ring(of: $0) <= radius }
    }

    public func cellCount(radius: Int) -> Int {
        switch self {
        case .hexagonal: 3 * radius * (radius + 1) + 1
        case .square: (2 * radius + 1) * (2 * radius + 1)
        }
    }

    /// The width and height of the region within `radius` rings, centred on
    /// the origin cell.
    public func extent(radius: Int) -> (width: Double, height: Double) {
        switch self {
        case .hexagonal:
            (3 * Double(radius) + 2, TileShape.hexagon.inradius * 2 * Double(2 * radius + 1))
        case .square:
            (Double(2 * radius + 1), Double(2 * radius + 1))
        }
    }

    /// Enough rings to hold everything inside the given bounds, up to
    /// `limit`.
    public func radius(covering bounds: (min: Point, max: Point), limit: Int) -> Int {
        // The ring of the cell under each corner of the bounds. A region of
        // rings is convex, so one that holds the corners holds everything
        // between them.
        var furthest = 0.0
        for x in [bounds.min.x, bounds.max.x] {
            for y in [bounds.min.y, bounds.max.y] {
                switch self {
                case .hexagonal:
                    let q = x / 1.5
                    let r = y / (3.0).squareRoot() - q / 2
                    furthest = max(furthest, abs(q), abs(r), abs(q + r))
                case .square:
                    // A cell reaches half a unit either side of its centre.
                    furthest = max(furthest, abs(x) - 0.5, abs(y) - 0.5)
                }
            }
        }
        return min(max(Int(furthest.rounded(.up)), 1), max(limit, 1))
    }

    /// How wide a run of whole columns of cells is.
    public func width(ofColumns columns: Int) -> Double {
        switch self {
        case .hexagonal: 1.5 * Double(columns) + 0.5
        case .square: Double(columns)
        }
    }

    /// How many whole columns of cells fit in a width.
    public func columns(inWidth width: Double) -> Int {
        switch self {
        case .hexagonal: Int(((width - 0.5) / 1.5).rounded())
        case .square: Int(width.rounded())
        }
    }

    // MARK: Symmetry

    /// The symmetries a maze on this tiling can keep.
    public var symmetries: [Symmetry] {
        switch self {
        case .hexagonal: [.none, .mirror, .half, .third, .sixth]
        case .square: [.none, .mirror, .half, .quarter]
        }
    }

    /// The turns and flips of the whole grid, about the origin cell, that
    /// leave a maze with the given symmetry unchanged.
    public func transforms(for symmetry: Symmetry) -> [TileTransform] {
        switch self {
        case .hexagonal:
            return symmetry.transforms
        case .square:
            let same = TileTransform(sides: 4)
            switch symmetry {
            case .mirror: return [same, TileTransform(mirrored: true, sides: 4)]
            case .half: return [same, TileTransform(turns: 2, sides: 4)]
            case .quarter: return (0..<4).map { TileTransform(turns: $0, sides: 4) }
            // A square grid has no third or sixth turn.
            case .none, .third, .sixth: return [same]
            }
        }
    }

    /// Where a cell lands when the whole grid is turned and flipped about
    /// the origin cell.
    public func transformed(_ cell: HexCoord, by transform: TileTransform) -> HexCoord {
        switch self {
        case .hexagonal:
            return cell.transformed(by: transform)
        case .square:
            var q = cell.q
            var r = cell.r
            if transform.mirrored { q = -q }
            // A quarter turn clockwise takes right to down.
            for _ in 0..<transform.turns {
                (q, r) = (-r, q)
            }
            return HexCoord(q: q, r: r)
        }
    }

    /// Every cell that has to match `cell` for a maze to keep a symmetry,
    /// starting with the cell itself, and how the tile in `cell` has to be
    /// turned or flipped to be the tile in each.
    ///
    /// Moving a cell and turning its tile are separate things. On a grid of
    /// upright cells a quarter turn of the maze moves a tile and turns it a
    /// quarter. On a grid whose cells are themselves turned, the same move
    /// can land a tile in a cell that is already a quarter round, so the
    /// tile is not turned at all.
    public func images(of cell: HexCoord, under symmetry: Symmetry) -> [(cell: HexCoord, tile: TileTransform)] {
        transforms(for: symmetry).map { (transformed(cell, by: $0), $0) }
    }

    /// The ways a tile has to look the same as itself for its cell to keep
    /// a symmetry: one for each image of the cell, other than the first,
    /// that is the cell itself.
    public func stabilizer(of cell: HexCoord, symmetry: Symmetry) -> [TileTransform] {
        images(of: cell, under: symmetry).dropFirst().filter { $0.cell == cell }.map(\.tile)
    }
}
