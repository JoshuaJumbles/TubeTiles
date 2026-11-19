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
    /// Cairo pentagons. They come in pairs joined along their flat edges,
    /// with the wide corners pointing away from each other. The pairs sit
    /// on a square grid, standing upright and lying sideways by turns like
    /// the squares of a chessboard, so a pentagon points one of four ways.
    ///
    /// A cell's `q` is its pair's column. Its `r` is twice the pair's row,
    /// plus one for the second pentagon of the pair: the upper one of an
    /// upright pair, the right-hand one of a sideways pair.
    ///
    /// The centre of the grid is not a cell but a corner where four
    /// pentagons meet, the one point the tiling can be turned a quarter
    /// about. The four pairs around it are columns -1 and 0 of rows -1
    /// and 0.
    case cairo
    /// Octagons in rows and columns, with a square turned on its corner in
    /// each gap where four of them meet.
    ///
    /// Cells are addressed in half steps of the octagons' spacing. An
    /// octagon has `q` and `r` both even, a square has both odd, and no
    /// cell has one of each.
    case truncatedSquare
    /// Hexagons that touch only at their corners, with a triangle on every
    /// edge.
    ///
    /// The hexagons sit in rows, each row half a step along from the one
    /// above. A cell's `q` is its hexagon's place in the row. Its `r` is
    /// three times the row, plus one for the triangle on the hexagon's top
    /// edge or two for the triangle on its bottom edge. The other four
    /// triangles round a hexagon belong to its neighbours.
    case trihexagonal
    /// Rows of squares with rows of triangles between them, the triangles
    /// pointing down and up by turns. Each row of squares sits half a
    /// square along from the one above.
    ///
    /// A cell's `q` is its square's place in the row. Its `r` is three
    /// times the row, plus one for the triangle hanging under the square,
    /// or two for the upward triangle to the right of that one.
    case elongatedTriangular
    /// Squares on a grid, tilted one way and the other like the squares of
    /// a chessboard so that they meet only at their corners, with a
    /// triangle on every edge. The triangles sit back to back in pairs.
    ///
    /// A cell's `q` is its square's column. Its `r` is five times the
    /// square's row, plus one to four for the triangle on its top, right,
    /// bottom or left edge. Only every other square has triangles of its
    /// own; the rest borrow their neighbours'.
    case snubSquare

    /// One tiling with cells of the given shape.
    public init(shape: TileShape) {
        switch shape {
        case .hexagon: self = .hexagonal
        case .square: self = .square
        case .cairo: self = .cairo
        case .octagon: self = .truncatedSquare
        case .triangle: self = .trihexagonal
        }
    }

    /// The shapes of the tiling's cells, each once. A library has to hold
    /// all of them to lay it.
    public var shapes: [TileShape] {
        switch self {
        case .hexagonal: [.hexagon]
        case .square: [.square]
        case .cairo: [.cairo]
        case .truncatedSquare: [.octagon, .square]
        case .trihexagonal: [.hexagon, .triangle]
        case .elongatedTriangular, .snubSquare: [.square, .triangle]
        }
    }

    /// The shape of a cell.
    public func shape(of cell: HexCoord) -> TileShape {
        switch self {
        case .hexagonal: .hexagon
        case .square: .square
        case .cairo: .cairo
        case .truncatedSquare: cell.q & 1 == 0 ? .octagon : .square
        case .trihexagonal: Self.trihexParts(cell).kind == 0 ? .hexagon : .triangle
        case .elongatedTriangular: Self.parts(cell, per: 3).kind == 0 ? .square : .triangle
        case .snubSquare: Self.parts(cell, per: 5).kind == 0 ? .square : .triangle
        }
    }

    /// Whether an address names a cell. Every pair of numbers does, except
    /// where octagons and squares share the grid.
    public func isCell(_ cell: HexCoord) -> Bool {
        switch self {
        case .truncatedSquare:
            return (cell.q & 1) == (cell.r & 1)
        case .snubSquare:
            // Triangles belong to the squares on one colour of the board.
            let parts = Self.parts(cell, per: 5)
            return parts.kind == 0 || (parts.column + parts.row) & 1 == 0
        case .hexagonal, .square, .cairo, .trihexagonal, .elongatedTriangular:
            return true
        }
    }

    /// A cell's column and row, and which of the `count` cells at that
    /// place it is, for the tilings that keep several cells to a place.
    private static func parts(_ cell: HexCoord, per count: Int) -> (column: Int, row: Int, kind: Int) {
        let row = Int((Double(cell.r) / Double(count)).rounded(.down))
        return (cell.q, row, cell.r - count * row)
    }

    /// From one row of squares to the next, in rows of squares and
    /// triangles: a square and a triangle high.
    static let elongatedPitch = 1 + (3.0).squareRoot() / 2

    /// The smallest region that takes in a row of squares.
    private static func elongatedRing(ofRow row: Int) -> Int {
        row == 0 ? 0 : Int(((Double(abs(row)) - 0.5) * elongatedPitch).rounded(.up))
    }

    /// How many rows of squares a region has above its middle row, and as
    /// many below.
    private static func elongatedRows(radius: Int) -> Int {
        Int(Double(radius) / elongatedPitch + 0.5)
    }

    /// Distance between neighbouring squares of the pinwheel pattern.
    static let snubPitch = (1 + (3.0).squareRoot()) / 2

    /// For each kind of pinwheel cell and each of its edges: how far away
    /// the neighbour's square is, which of that square's cells, and which
    /// edge. Kinds are 0 for a square with triangles of its own, 1 to 4 for
    /// those triangles, and 5 for a square without.
    ///
    /// Found by looking: the cell across an edge is the one with an edge in
    /// the same place.
    private static let snubNeighbours: [[(column: Int, row: Int, kind: Int, edge: Int)]] = {
        let tiling = Tiling.snubSquare
        func middle(_ cell: HexCoord, _ edge: Int) -> Point {
            let shape = tiling.shape(of: cell)
            return tiling.frame(of: cell).place((shape.corner(edge) + shape.corner(edge + 1)) * 0.5)
        }
        var nearby: [HexCoord] = []
        for column in -2...3 {
            for row in -2...2 {
                for kind in 0..<5 {
                    let cell = HexCoord(q: column, r: 5 * row + kind)
                    if tiling.isCell(cell) { nearby.append(cell) }
                }
            }
        }
        // A square with triangles and each of them, at the middle of the
        // board, and the square without to its right.
        let samples = (0..<5).map { HexCoord(q: 0, r: $0) } + [HexCoord(q: 1, r: 0)]
        return samples.map { cell in
            (0..<tiling.shape(of: cell).edgeCount).map { edge in
                let here = middle(cell, edge)
                for other in nearby where other != cell {
                    for facing in 0..<tiling.shape(of: other).edgeCount
                    where middle(other, facing).distance(to: here) < 1e-6 {
                        let parts = parts(other, per: 5)
                        return (parts.column - cell.q, parts.row, parts.kind, facing)
                    }
                }
                preconditionFailure("A pinwheel cell has an edge with nothing across it")
            }
        }
    }()

    /// Which row of `snubNeighbours` a pinwheel cell reads.
    private static func snubKind(_ parts: (column: Int, row: Int, kind: Int)) -> Int {
        parts.kind == 0 && (parts.column + parts.row) & 1 != 0 ? 5 : parts.kind
    }

    /// A hexagon-and-triangle cell's hexagon, and which of its three cells
    /// it is: 0 the hexagon, 1 the triangle above, 2 the triangle below.
    private static func trihexParts(_ cell: HexCoord) -> (column: Int, row: Int, kind: Int) {
        let row = Int((Double(cell.r) / 3).rounded(.down))
        return (cell.q, row, cell.r - 3 * row)
    }

    private static func trihexCell(column: Int, row: Int, kind: Int) -> HexCoord {
        HexCoord(q: column, r: 3 * row + kind)
    }

    /// From a hexagon's centre to the centre of a triangle on its edge.
    private static let trihexReach = TileShape.hexagon.inradius + TileShape.triangle.inradius

    /// Distance between neighbouring octagons: twice an octagon's inradius.
    static let octagonPitch = 1 + (2.0).squareRoot()

    /// Distance between neighbouring pairs of Cairo pentagons.
    static let cairoPitch = 0.5 + TileShape.cairoHalfHeight * 2

    /// A Cairo cell's pair, which pentagon of the pair it is, and whether
    /// the pair lies sideways.
    private static func cairoParts(_ cell: HexCoord) -> (column: Int, row: Int, second: Bool, sideways: Bool) {
        let row = Int((Double(cell.r) / 2).rounded(.down))
        let column = cell.q
        return (column, row, cell.r - 2 * row == 1, ((column + row) % 2 + 2) % 2 == 1)
    }

    /// For each kind of Cairo cell (upright first, upright second, sideways
    /// first, sideways second) and each edge: how far away the neighbouring
    /// pair is, which pentagon of it, and which edge.
    private static let cairoNeighbours: [[(column: Int, row: Int, second: Bool, edge: Int)]] = [
        [(0, 0, true, 0), (1, 0, false, 2), (0, 1, true, 1), (0, 1, false, 4), (-1, 0, true, 3)],
        [(0, 0, false, 0), (-1, 0, true, 2), (0, -1, false, 1), (0, -1, true, 4), (1, 0, false, 3)],
        [(0, 0, true, 0), (0, 1, true, 2), (-1, 0, false, 1), (-1, 0, true, 4), (0, -1, false, 3)],
        [(0, 0, false, 0), (0, -1, false, 2), (1, 0, true, 1), (1, 0, false, 4), (0, 1, true, 3)],
    ]

    /// Centre of a cell, in units of a tile's edge.
    public func center(of cell: HexCoord) -> Point {
        switch self {
        case .hexagonal:
            return cell.center
        // One unit a cell: `q` counts columns to the right, `r` rows down.
        case .square:
            return Point(x: Double(cell.q), y: Double(cell.r))
        case .cairo:
            // Each pentagon sits half its height from the middle of its
            // pair, on the side its wide corner points to.
            let parts = Self.cairoParts(cell)
            let reach = TileShape.cairoHalfHeight
            let x = (Double(parts.column) + 0.5) * Self.cairoPitch
            let y = (Double(parts.row) + 0.5) * Self.cairoPitch
            if parts.sideways {
                // The first points left and sits to the left.
                return Point(x: x + (parts.second ? reach : -reach), y: y)
            }
            // The first points down and sits below.
            return Point(x: x, y: y + (parts.second ? -reach : reach))
        case .truncatedSquare:
            return Point(x: Double(cell.q), y: Double(cell.r)) * (Self.octagonPitch / 2)
        case .trihexagonal:
            // Hexagons are two units apart along a row, and each row is one
            // unit along and root three down from the last.
            let parts = Self.trihexParts(cell)
            let hexagon = Point(
                x: 2 * Double(parts.column) + Double(parts.row), y: (3.0).squareRoot() * Double(parts.row)
            )
            let lift = parts.kind == 0 ? 0 : (parts.kind == 1 ? -Self.trihexReach : Self.trihexReach)
            return Point(x: hexagon.x, y: hexagon.y + lift)
        case .elongatedTriangular:
            let parts = Self.parts(cell, per: 3)
            let square = Point(
                x: Double(parts.column) + Double(parts.row) / 2, y: Double(parts.row) * Self.elongatedPitch
            )
            let inradius = TileShape.triangle.inradius
            switch parts.kind {
            case 0: return square
            // Hanging from the square's bottom edge.
            case 1: return Point(x: square.x, y: square.y + 0.5 + inradius)
            // Half a square along, standing on the row of squares below.
            default: return Point(x: square.x + 0.5, y: square.y + Self.elongatedPitch - 0.5 - inradius)
            }
        case .snubSquare:
            let parts = Self.parts(cell, per: 5)
            let square = Point(x: Double(parts.column), y: Double(parts.row)) * Self.snubPitch
            guard parts.kind > 0 else { return square }
            // Out from the middle of the square's edge.
            let angle = Self.snubTilt + Double(parts.kind - 2) * .pi / 2
            let reach = 0.5 + TileShape.triangle.inradius
            return Point(x: square.x + cos(angle) * reach, y: square.y + sin(angle) * reach)
        }
    }

    /// How far a cell is turned from the way its shape is drawn, clockwise
    /// in radians. Every cell is upright in the tilings so far.
    public func turn(of cell: HexCoord) -> Double {
        switch self {
        case .hexagonal, .square:
            return 0
        case .cairo:
            // Upright pairs point down then up, sideways pairs left then
            // right, counted in quarter turns clockwise from pointing down.
            let parts = Self.cairoParts(cell)
            let quarters = parts.sideways ? (parts.second ? 3 : 1) : (parts.second ? 2 : 0)
            return Double(quarters) * .pi / 2
        case .truncatedSquare:
            // A square stands on its corner, so its top edge faces up and
            // to the right.
            return cell.q & 1 == 0 ? 0 : .pi / 4
        case .trihexagonal:
            // The triangle above a hexagon points up, which is half a turn
            // from the way a triangle is drawn.
            return Self.trihexParts(cell).kind == 1 ? .pi : 0
        case .elongatedTriangular:
            return Self.parts(cell, per: 3).kind == 2 ? .pi : 0
        case .snubSquare:
            let parts = Self.parts(cell, per: 5)
            // A sixth of a turn either way, by the colour of the square. A
            // triangle is turned to put its top edge against its square.
            if parts.kind == 0 { return (parts.column + parts.row) & 1 == 0 ? Self.snubTilt : -Self.snubTilt }
            return Self.snubTilt + Double(parts.kind - 3) * .pi / 2
        }
    }

    /// How far the pinwheel's squares are tilted.
    private static let snubTilt = Double.pi / 6

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
        case .cairo:
            let parts = Self.cairoParts(cell)
            let kind = (parts.sideways ? 2 : 0) + (parts.second ? 1 : 0)
            let other = Self.cairoNeighbours[kind][edge]
            return (
                HexCoord(q: parts.column + other.column, r: 2 * (parts.row + other.row) + (other.second ? 1 : 0)),
                other.edge
            )
        case .truncatedSquare:
            if cell.q & 1 == 0 {
                // An octagon's level and upright edges meet other octagons,
                // its slanted ones meet squares.
                let step = [(0, -2), (1, -1), (2, 0), (1, 1), (0, 2), (-1, 1), (-2, 0), (-1, -1)][edge]
                let other = HexCoord(q: cell.q + step.0, r: cell.r + step.1)
                return (other, edge % 2 == 0 ? (edge + 4) % 8 : [2, 3, 0, 1][edge / 2])
            }
            // A square's edges face up-right, down-right, down-left and
            // up-left, each onto a slanted edge of an octagon.
            let step = [(1, -1), (1, 1), (-1, 1), (-1, -1)][edge]
            return (HexCoord(q: cell.q + step.0, r: cell.r + step.1), [5, 7, 1, 3][edge])
        case .trihexagonal:
            let parts = Self.trihexParts(cell)
            // How far away the neighbour's hexagon is, which of its cells,
            // and which edge.
            let table: [(column: Int, row: Int, kind: Int, edge: Int)]
            switch parts.kind {
            // Round a hexagon the triangles point up and down by turns.
            case 0: table = [(0, 0, 1, 0), (1, -1, 2, 2), (0, 1, 1, 1), (0, 0, 2, 0), (-1, 1, 1, 2), (0, -1, 2, 1)]
            case 1: table = [(0, 0, 0, 0), (0, -1, 0, 2), (1, -1, 0, 4)]
            default: table = [(0, 0, 0, 3), (0, 1, 0, 5), (-1, 1, 0, 1)]
            }
            let other = table[edge]
            return (
                Self.trihexCell(column: parts.column + other.column, row: parts.row + other.row, kind: other.kind),
                other.edge
            )
        case .elongatedTriangular:
            let parts = Self.parts(cell, per: 3)
            let table: [(column: Int, row: Int, kind: Int, edge: Int)]
            switch parts.kind {
            // Above a square is an upward triangle of the row before; the
            // squares either side are in its own row.
            case 0: table = [(0, -1, 2, 0), (1, 0, 0, 3), (0, 0, 1, 0), (-1, 0, 0, 1)]
            case 1: table = [(0, 0, 0, 2), (0, 0, 2, 1), (-1, 0, 2, 2)]
            default: table = [(0, 1, 0, 0), (0, 0, 1, 1), (1, 0, 1, 2)]
            }
            let other = table[edge]
            return (HexCoord(q: parts.column + other.column, r: 3 * (parts.row + other.row) + other.kind), other.edge)
        case .snubSquare:
            let parts = Self.parts(cell, per: 5)
            let other = Self.snubNeighbours[Self.snubKind(parts)][edge]
            return (HexCoord(q: parts.column + other.column, r: 5 * (parts.row + other.row) + other.kind), other.edge)
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
        case .hexagonal:
            return cell.ring
        // Rings of squares are square, so a region is a square block.
        case .square:
            return max(abs(cell.q), abs(cell.r))
        case .cairo:
            // By pairs, so a region is a square block of them. The centre
            // is a corner between pairs, so columns -1 and 0 are equally
            // near it.
            let parts = Self.cairoParts(cell)
            return max(
                parts.column < 0 ? -parts.column - 1 : parts.column,
                parts.row < 0 ? -parts.row - 1 : parts.row
            )
        case .truncatedSquare:
            // By octagons, so a region is a square block of them. A square
            // is on the ring of the furthest octagon it touches, which
            // leaves a region with only the squares it surrounds.
            return (max(abs(cell.q), abs(cell.r)) + 1) / 2
        case .trihexagonal:
            // By hexagons, so a region is a hexagon of them. A triangle is
            // on the ring of the furthest hexagon it touches, which leaves
            // a region with only the triangles its hexagons close in.
            let parts = Self.trihexParts(cell)
            func ring(_ column: Int, _ row: Int) -> Int { max(abs(column), abs(row), abs(column + row)) }
            switch parts.kind {
            case 0:
                return ring(parts.column, parts.row)
            case 1:
                return max(
                    ring(parts.column, parts.row), ring(parts.column, parts.row - 1),
                    ring(parts.column + 1, parts.row - 1)
                )
            default:
                return max(
                    ring(parts.column, parts.row), ring(parts.column, parts.row + 1),
                    ring(parts.column - 1, parts.row + 1)
                )
            }
        case .elongatedTriangular:
            // By squares. A row of squares with its triangles is nearly
            // twice as tall as a square is wide, so rows are taken on more
            // slowly than squares along a row, to keep a region about as
            // tall as it is wide. A triangle comes with the square it hangs
            // from or stands on, once there is a row on its other side.
            let parts = Self.parts(cell, per: 3)
            func ring(_ column: Int, _ row: Int) -> Int {
                max(Self.elongatedRing(ofRow: row), Int(abs(Double(column) + Double(row) / 2).rounded(.up)))
            }
            switch parts.kind {
            case 0: return ring(parts.column, parts.row)
            case 1: return max(ring(parts.column, parts.row), Self.elongatedRing(ofRow: parts.row + 1))
            default: return max(ring(parts.column, parts.row + 1), Self.elongatedRing(ofRow: parts.row))
            }
        case .snubSquare:
            // By squares, so a region is a square block of them, with the
            // triangles that lie between two of its squares.
            let parts = Self.parts(cell, per: 5)
            func ring(_ column: Int, _ row: Int) -> Int { max(abs(column), abs(row)) }
            guard parts.kind > 0 else { return ring(parts.column, parts.row) }
            let other = Self.snubNeighbours[parts.kind].first { $0.kind == 0 && ($0.column, $0.row) != (0, 0) }
            return max(
                ring(parts.column, parts.row),
                ring(parts.column + (other?.column ?? 0), parts.row + (other?.row ?? 0))
            )
        }
    }

    /// Every cell within `radius` rings of the origin, in a stable order.
    public func cells(radius: Int) -> [HexCoord] {
        // A Cairo row holds two cells, so its `r` runs twice as far, and
        // there is one more column and row on the near side of the centre.
        var rows = (-radius)...radius
        var columns = rows
        if self == .cairo {
            rows = (-2 * radius - 2)...(2 * radius + 1)
            columns = (-radius - 1)...radius
        } else if self == .truncatedSquare {
            // Addresses go in half steps.
            rows = (-2 * radius)...(2 * radius)
            columns = rows
        } else if self == .trihexagonal {
            // Three cells to a hexagon.
            rows = (-3 * radius - 3)...(3 * radius + 5)
        } else if self == .elongatedTriangular {
            // Three cells to a square, and rows that lean.
            rows = (-3 * radius - 3)...(3 * radius + 5)
            columns = (-2 * radius - 1)...(2 * radius + 1)
        } else if self == .snubSquare {
            // Five cells to a square.
            rows = (-5 * radius)...(5 * radius + 4)
        }
        return columns.flatMap { q in
            rows.map { HexCoord(q: q, r: $0) }
        }.filter { isCell($0) && ring(of: $0) <= radius }
    }

    public func cellCount(radius: Int) -> Int {
        switch self {
        case .hexagonal: return 3 * radius * (radius + 1) + 1
        case .square: return (2 * radius + 1) * (2 * radius + 1)
        case .cairo: return 8 * (radius + 1) * (radius + 1)
        case .truncatedSquare: return (2 * radius + 1) * (2 * radius + 1) + 4 * radius * radius
        // A hexagon of hexagons, and the triangles between them.
        case .trihexagonal: return 3 * radius * (radius + 1) + 1 + 6 * radius * radius
        case .elongatedTriangular:
            // Even rows hold one square more than odd ones. Every square
            // but those of the last row has a triangle under it, and every
            // one but those of the first has a triangle above.
            let rows = Self.elongatedRows(radius: radius)
            let even = 2 * (rows / 2) + 1
            let squares = even * (2 * radius + 1) + (2 * rows + 1 - even) * 2 * radius
            return 3 * squares - 2 * (rows % 2 == 0 ? 2 * radius + 1 : 2 * radius)
        // A block of squares, and a triangle for each two that touch.
        case .snubSquare: return (2 * radius + 1) * (6 * radius + 1)
        }
    }

    /// The width and height of the region within `radius` rings, centred on
    /// the centre of the grid.
    public func extent(radius: Int) -> (width: Double, height: Double) {
        switch self {
        case .hexagonal:
            return (3 * Double(radius) + 2, TileShape.hexagon.inradius * 2 * Double(2 * radius + 1))
        case .square:
            return (Double(2 * radius + 1), Double(2 * radius + 1))
        case .cairo:
            // Sideways pairs reach as far across as upright ones reach up
            // and down.
            let side = 2 * ((Double(radius) + 0.5) * Self.cairoPitch + TileShape.cairoHalfHeight * 2)
            return (side, side)
        case .truncatedSquare:
            let side = Double(2 * radius + 1) * Self.octagonPitch
            return (side, side)
        case .trihexagonal:
            return (Double(4 * radius + 2), (3.0).squareRoot() * Double(2 * radius + 1))
        case .elongatedTriangular:
            return (Double(2 * radius + 1), 2 * Double(Self.elongatedRows(radius: radius)) * Self.elongatedPitch + 1)
        case .snubSquare:
            // A tilted square reaches half a pitch from its centre.
            let side = Double(2 * radius + 1) * Self.snubPitch
            return (side, side)
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
                case .cairo:
                    // Rounded up below, which is a ring to spare for the
                    // pentagons that reach in from the next pair.
                    furthest = max(furthest, abs(x) / Self.cairoPitch, abs(y) / Self.cairoPitch)
                case .truncatedSquare:
                    // An octagon reaches half a pitch either side of its
                    // centre.
                    furthest = max(furthest, abs(x) / Self.octagonPitch - 0.5, abs(y) / Self.octagonPitch - 0.5)
                case .trihexagonal:
                    let row = y / (3.0).squareRoot()
                    let column = (x - row) / 2
                    furthest = max(furthest, abs(column), abs(row), abs(column + row))
                case .elongatedTriangular:
                    // Rows come more slowly than squares, by up to a row.
                    furthest = max(furthest, abs(x) - 0.5, abs(y) + 0.5)
                case .snubSquare:
                    furthest = max(furthest, abs(x) / Self.snubPitch - 0.5, abs(y) / Self.snubPitch - 0.5)
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
        // Two pentagons side by side take up one pitch.
        case .cairo: Double(columns) * Self.cairoPitch / 2
        // Columns of octagons.
        case .truncatedSquare: Double(columns) * Self.octagonPitch
        // Hexagons in a row.
        case .trihexagonal: Double(columns) * 2
        // Squares in a row.
        case .elongatedTriangular: Double(columns)
        case .snubSquare: Double(columns) * Self.snubPitch
        }
    }

    /// How many whole columns of cells fit in a width.
    public func columns(inWidth width: Double) -> Int {
        switch self {
        case .hexagonal: Int(((width - 0.5) / 1.5).rounded())
        case .square: Int(width.rounded())
        case .cairo: Int((width * 2 / Self.cairoPitch).rounded())
        case .truncatedSquare: Int((width / Self.octagonPitch).rounded())
        case .trihexagonal: Int((width / 2).rounded())
        case .elongatedTriangular: Int(width.rounded())
        case .snubSquare: Int((width / Self.snubPitch).rounded())
        }
    }

    // MARK: Symmetry

    /// The symmetries a maze on this tiling can keep.
    public var symmetries: [Symmetry] {
        switch self {
        // The centre is a hexagon either way.
        case .hexagonal, .trihexagonal: [.none, .mirror, .half, .third, .sixth]
        // The centre is an octagon, which has every symmetry a square has.
        case .square, .truncatedSquare: [.none, .mirror, .half, .quarter]
        // Rows look the same turned half way round or flipped, and no
        // other way.
        case .elongatedTriangular: [.none, .mirror, .half]
        // The pinwheel turns about a square, but no mirror line passes
        // through one.
        case .snubSquare: [.none, .half, .quarter]
        // Turns only: the tiling's mirror lines miss the corner at the
        // centre of the grid.
        case .cairo: [.none, .half, .quarter]
        }
    }

    /// The turns and flips of the whole grid, about its centre, that leave
    /// a maze with the given symmetry unchanged. Away from hexagons they
    /// are counted in quarter turns of the grid, whatever the cells' shapes;
    /// `images(of:under:)` says what each does to a tile.
    public func transforms(for symmetry: Symmetry) -> [TileTransform] {
        switch self {
        case .hexagonal, .trihexagonal:
            return symmetry.transforms
        case .square, .truncatedSquare, .elongatedTriangular, .snubSquare:
            guard symmetries.contains(symmetry) else { return [TileTransform(sides: 4)] }
            let same = TileTransform(sides: 4)
            switch symmetry {
            case .mirror: return [same, TileTransform(mirrored: true, sides: 4)]
            case .half: return [same, TileTransform(turns: 2, sides: 4)]
            case .quarter: return (0..<4).map { TileTransform(turns: $0, sides: 4) }
            // A square grid has no third or sixth turn.
            case .none, .third, .sixth: return [same]
            }
        case .cairo:
            switch symmetry {
            case .half: return [0, 2].map { TileTransform(turns: $0, sides: 4) }
            case .quarter: return (0..<4).map { TileTransform(turns: $0, sides: 4) }
            // No mirror line passes through the centre.
            case .none, .mirror, .third, .sixth: return [TileTransform(sides: 4)]
            }
        }
    }

    /// Where a cell lands when the whole grid is turned and flipped about
    /// its centre.
    public func transformed(_ cell: HexCoord, by transform: TileTransform) -> HexCoord {
        switch self {
        case .hexagonal:
            return cell.transformed(by: transform)
        // Half-step addresses turn and flip like whole ones.
        case .square, .truncatedSquare:
            var q = cell.q
            var r = cell.r
            if transform.mirrored { q = -q }
            // A quarter turn clockwise takes right to down.
            for _ in 0..<transform.turns {
                (q, r) = (-r, q)
            }
            return HexCoord(q: q, r: r)
        case .cairo:
            var parts = Self.cairoParts(cell)
            // Which way the pentagon points, in quarter turns clockwise
            // from pointing down, as in `turn(of:)`.
            var pointing = parts.sideways ? (parts.second ? 3 : 1) : (parts.second ? 2 : 0)
            for _ in 0..<transform.turns {
                // A quarter turn clockwise about the corner takes the pair
                // to the right of the centre to the one below it.
                (parts.column, parts.row) = (-parts.row - 1, parts.column)
                pointing = (pointing + 1) % 4
            }
            // Up and right are the second pentagons of their pairs.
            return HexCoord(q: parts.column, r: 2 * parts.row + (pointing >= 2 ? 1 : 0))
        case .trihexagonal, .elongatedTriangular, .snubSquare:
            return self.cell(nearest: transform.apply(to: center(of: cell))) ?? cell
        }
    }

    /// The cell whose centre is nearest a point, for the tilings that keep
    /// several cells to a place. Used to find where a cell lands when the
    /// grid is turned: its centre lands on another cell's.
    private func cell(nearest point: Point) -> HexCoord? {
        let count: Int
        let row: Int
        let column: Int
        switch self {
        case .trihexagonal:
            count = 3
            row = Int((point.y / (3.0).squareRoot()).rounded())
            column = Int(((point.x - Double(row)) / 2).rounded())
        case .elongatedTriangular:
            count = 3
            row = Int((point.y / Self.elongatedPitch).rounded())
            column = Int((point.x - Double(row) / 2).rounded())
        case .snubSquare:
            count = 5
            row = Int((point.y / Self.snubPitch).rounded())
            column = Int((point.x / Self.snubPitch).rounded())
        case .hexagonal, .square, .cairo, .truncatedSquare:
            return nil
        }
        var best: HexCoord?
        var nearest = Double.infinity
        for rowStep in -1...1 {
            for columnStep in -1...1 {
                for kind in 0..<count {
                    let candidate = HexCoord(q: column + columnStep, r: count * (row + rowStep) + kind)
                    guard isCell(candidate) else { continue }
                    let distance = center(of: candidate).distance(to: point)
                    if distance < nearest { (best, nearest) = (candidate, distance) }
                }
            }
        }
        return best
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
        transforms(for: symmetry).map { (transformed(cell, by: $0), tileTransform(for: $0, at: cell)) }
    }

    /// What a turn or flip of the whole grid does to the tile in a cell.
    private func tileTransform(for grid: TileTransform, at cell: HexCoord) -> TileTransform {
        switch self {
        case .hexagonal, .square:
            return grid
        case .cairo:
            // A Cairo cell is turned as far as the grid was to reach it, so
            // its tile goes in as it is.
            return TileTransform(sides: 5)
        case .truncatedSquare:
            if cell.q & 1 == 0 {
                // A quarter turn is two of an octagon's edges.
                return TileTransform(turns: grid.turns * 2, mirrored: grid.mirrored, sides: 8)
            }
            // A square on its corner is flipped about a line through two of
            // its corners, which is a flip about its upright and then a
            // quarter turn back.
            return TileTransform(turns: grid.turns - (grid.mirrored ? 1 : 0), mirrored: grid.mirrored, sides: 4)
        case .trihexagonal, .elongatedTriangular, .snubSquare:
            // The grid's turn, less the difference in how the two cells are
            // already turned, counted in edges of the cell's own shape. A
            // flip reverses the turn the cell started with.
            let sides = shape(of: cell).edgeCount
            let from = turn(of: cell)
            let to = turn(of: transformed(cell, by: grid))
            let turned = Double(grid.turns) * 2 * .pi / Double(grid.sides) + (grid.mirrored ? -from : from) - to
            return TileTransform(
                turns: Int((turned / (2 * .pi / Double(sides))).rounded()), mirrored: grid.mirrored, sides: sides
            )
        }
    }

    /// The ways a tile has to look the same as itself for its cell to keep
    /// a symmetry: one for each image of the cell, other than the first,
    /// that is the cell itself.
    public func stabilizer(of cell: HexCoord, symmetry: Symmetry) -> [TileTransform] {
        images(of: cell, under: symmetry).dropFirst().filter { $0.cell == cell }.map(\.tile)
    }
}
