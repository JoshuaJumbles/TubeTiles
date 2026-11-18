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

    /// One tiling with cells of the given shape.
    public init(shape: TileShape) {
        switch shape {
        case .hexagon: self = .hexagonal
        case .square: self = .square
        case .cairo: self = .cairo
        case .octagon: self = .truncatedSquare
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
        }
    }

    /// The shape of a cell.
    public func shape(of cell: HexCoord) -> TileShape {
        switch self {
        case .hexagonal: .hexagon
        case .square: .square
        case .cairo: .cairo
        case .truncatedSquare: cell.q & 1 == 0 ? .octagon : .square
        }
    }

    /// Whether an address names a cell. Every pair of numbers does, except
    /// where octagons and squares share the grid.
    public func isCell(_ cell: HexCoord) -> Bool {
        self != .truncatedSquare || (cell.q & 1) == (cell.r & 1)
    }

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
        }
        return columns.flatMap { q in
            rows.map { HexCoord(q: q, r: $0) }
        }.filter { isCell($0) && ring(of: $0) <= radius }
    }

    public func cellCount(radius: Int) -> Int {
        switch self {
        case .hexagonal: 3 * radius * (radius + 1) + 1
        case .square: (2 * radius + 1) * (2 * radius + 1)
        case .cairo: 8 * (radius + 1) * (radius + 1)
        case .truncatedSquare: (2 * radius + 1) * (2 * radius + 1) + 4 * radius * radius
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
        }
    }

    /// How many whole columns of cells fit in a width.
    public func columns(inWidth width: Double) -> Int {
        switch self {
        case .hexagonal: Int(((width - 0.5) / 1.5).rounded())
        case .square: Int(width.rounded())
        case .cairo: Int((width * 2 / Self.cairoPitch).rounded())
        case .truncatedSquare: Int((width / Self.octagonPitch).rounded())
        }
    }

    // MARK: Symmetry

    /// The symmetries a maze on this tiling can keep.
    public var symmetries: [Symmetry] {
        switch self {
        case .hexagonal: [.none, .mirror, .half, .third, .sixth]
        // The centre is an octagon, which has every symmetry a square has.
        case .square, .truncatedSquare: [.none, .mirror, .half, .quarter]
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
        case .hexagonal:
            return symmetry.transforms
        case .square, .truncatedSquare:
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
        }
    }

    /// The ways a tile has to look the same as itself for its cell to keep
    /// a symmetry: one for each image of the cell, other than the first,
    /// that is the cell itself.
    public func stabilizer(of cell: HexCoord, symmetry: Symmetry) -> [TileTransform] {
        images(of: cell, under: symmetry).dropFirst().filter { $0.cell == cell }.map(\.tile)
    }
}
