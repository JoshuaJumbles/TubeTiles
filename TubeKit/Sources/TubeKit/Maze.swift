import Foundation

/// A library tile in a particular placement.
public struct PlacedTile: Hashable, Sendable, Codable {
    public let source: Tile
    public let transform: TileTransform
    /// The tile as it sits on the grid.
    public let oriented: Tile
    /// The edge code of `oriented`, kept because it is read constantly.
    public let code: EdgeCode
    /// True for a tile made up by the generator rather than taken from the
    /// library.
    public let isGenerated: Bool

    public init(_ source: Tile, transform: TileTransform = .identity, isGenerated: Bool = false) {
        self.source = source
        self.transform = transform
        self.isGenerated = isGenerated
        oriented = source.transformed(by: transform)
        code = oriented.edgeCode
    }

    /// This placement after the whole grid is flipped and turned.
    public func transformed(by gridTransform: TileTransform) -> PlacedTile {
        PlacedTile(source, transform: transform.then(gridTransform), isGenerated: isGenerated)
    }

    /// Whether two placements put the same pipes on the grid.
    public func looksLike(_ other: PlacedTile) -> Bool {
        Set(oriented.pipes) == Set(other.oriented.pipes)
    }

    // Only the source tile and how it is placed are stored. The oriented
    // tile and its edge code are worked out again on loading, so a file
    // cannot hold a placement that disagrees with itself.
    private enum CodingKeys: String, CodingKey {
        case source, transform, isGenerated
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            try container.decode(Tile.self, forKey: .source),
            transform: try container.decode(TileTransform.self, forKey: .transform),
            isGenerated: try container.decodeIfPresent(Bool.self, forKey: .isGenerated) ?? false
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encode(transform, forKey: .transform)
        try container.encode(isGenerated, forKey: .isGenerated)
    }
}

/// Tiles laid out on a region of the hex grid.
///
/// Without a mask, the region is every cell within `radius` rings of the
/// origin. Its outline is sealed: no pipe may point out of it, except
/// through an opening. Inside, a cell may be empty, and an empty cell is
/// fine as long as no neighbouring pipe points into it.
///
/// With a mask, the region is whatever part of that hexagon the mask covers.
/// Ports outside the mask are closed, cells left without ports are out of
/// play, and a pipe whose drawn shape would cross the mask is refused. A
/// masked maze has no openings.
public struct Maze: Hashable, Sendable, Codable {
    public let portsPerEdge: Int
    public let radius: Int
    /// The space the maze may take up, or nil for the whole hexagon.
    public let mask: Mask?
    /// How the mask falls on the grid. Follows from the three above.
    private let region: MaskedRegion?
    public private(set) var cells: [HexCoord: PlacedTile] = [:]
    /// Ports on the outline where a pipe is required to leave the region:
    /// the entrance and exit of an open path.
    public private(set) var openings: Set<PortRef> = []
    /// Cells whose tile must contain a dead end: where a path starts or
    /// finishes inside the maze.
    public private(set) var goals: Set<HexCoord> = []

    /// How many path ends the maze asks for. Every path has two ends or
    /// none, so a maze can only be finished when this is even.
    public var endCount: Int { openings.count + goals.count }

    public init(portsPerEdge: Int, radius: Int, mask: Mask? = nil) {
        self.portsPerEdge = portsPerEdge
        self.radius = radius
        self.mask = mask
        region = mask.map { MaskedRegion(mask: $0, portsPerEdge: portsPerEdge, radius: radius) }
    }

    /// Enough rings to hold everything `mask` covers, up to `limit`.
    public static func radius(covering mask: Mask, limit: Int) -> Int {
        guard let bounds = mask.bounds else { return 1 }
        // The ring of the cell under each corner of the mask's bounds. A
        // hexagon of rings is convex, so one that holds the corners holds
        // everything between them.
        var furthest = 0.0
        for x in [bounds.min.x, bounds.max.x] {
            for y in [bounds.min.y, bounds.max.y] {
                let q = x / 1.5
                let r = y / (3.0).squareRoot() - q / 2
                furthest = max(furthest, abs(q), abs(r), abs(q + r))
            }
        }
        return min(max(Int(furthest.rounded(.up)), 1), max(limit, 1))
    }

    /// The same tiles on a region of a different shape. A tile stays if its
    /// cell is still in play and it keeps to the new shape; the rest are
    /// dropped, as are openings when the new shape has a mask.
    public func reshaped(radius: Int, mask: Mask?) -> Maze {
        var next = Maze(portsPerEdge: portsPerEdge, radius: radius, mask: mask)
        next.goals = goals.filter(next.contains)
        next.openings = openings.filter(next.isOnOutline)
        for (coord, placed) in cells where next.contains(coord) && next.staysInside(placed, at: coord) {
            next.cells[coord] = placed
        }
        for coord in next.cells.keys.sorted() {
            if let placed = next.cells[coord], !next.fits(placed.code, at: coord) {
                next.cells[coord] = nil
            }
        }
        return next
    }

    // Stored as a plain list of cells, in a stable order. Anything in a file
    // that could not be part of this maze (a cell outside the region, a tile
    // with the wrong port count, an opening off the outline) is dropped.
    private enum CodingKeys: String, CodingKey {
        case portsPerEdge, radius, mask, cells, openings, goals
    }

    private struct StoredCell: Codable {
        var coord: HexCoord
        var tile: PlacedTile
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            portsPerEdge: try container.decode(Int.self, forKey: .portsPerEdge),
            radius: try container.decode(Int.self, forKey: .radius),
            mask: try container.decodeIfPresent(Mask.self, forKey: .mask)
        )
        for cell in try container.decode([StoredCell].self, forKey: .cells)
        where contains(cell.coord) && cell.tile.source.portsPerEdge == portsPerEdge
            && staysInside(cell.tile, at: cell.coord) {
            cells[cell.coord] = cell.tile
        }
        let stored = try container.decodeIfPresent([PortRef].self, forKey: .openings) ?? []
        openings = Set(stored.filter(isOnOutline))
        goals = Set((try container.decodeIfPresent([HexCoord].self, forKey: .goals) ?? []).filter(contains))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(portsPerEdge, forKey: .portsPerEdge)
        try container.encode(radius, forKey: .radius)
        try container.encodeIfPresent(mask, forKey: .mask)
        let stored = cells.keys.sorted().compactMap { coord in
            cells[coord].map { StoredCell(coord: coord, tile: $0) }
        }
        try container.encode(stored, forKey: .cells)
        try container.encode(openings.sorted { ($0.coord, $0.port) < ($1.coord, $1.port) }, forKey: .openings)
        try container.encode(goals.sorted(), forKey: .goals)
    }

    public func contains(_ coord: HexCoord) -> Bool {
        coord.ring <= radius && (region?.active.contains(coord) ?? true)
    }

    // MARK: Mask

    /// The ports on `edge` of `coord` that the mask leaves usable, as bits
    /// in edge-code order. Every port, where there is no mask.
    public func allowedValue(at coord: HexCoord, edge: Int) -> Int {
        region?.allowed[coord]?[edge] ?? (1 << portsPerEdge) - 1
    }

    /// The ports of `coord` that the mask closes.
    public func closedPorts(at coord: HexCoord) -> Set<Port> {
        guard let edges = region?.allowed[coord] else { return [] }
        var closed: Set<Port> = []
        for (edge, value) in edges.enumerated() {
            for slot in 0..<portsPerEdge where value & (1 << (portsPerEdge - 1 - slot)) == 0 {
                closed.insert(Port(edge: edge, slot: slot))
            }
        }
        return closed
    }

    /// Whether a pipe at `coord` could reach outside the mask, so that its
    /// shape has to be checked.
    public func isOnBorder(_ coord: HexCoord) -> Bool {
        region?.border.contains(coord) ?? false
    }

    /// Whether `pipe`, drawn in the cell at `coord`, keeps its whole width
    /// inside the mask.
    public func staysInside(_ pipe: Pipe, at coord: HexCoord) -> Bool {
        guard let mask, isOnBorder(coord) else { return true }
        return MaskedRegion.staysInside(pipe, at: coord, mask: mask, portsPerEdge: portsPerEdge)
    }

    /// Whether every pipe of `tile`, placed at `coord`, stays inside the
    /// mask and off the ports it closes.
    public func staysInside(_ tile: PlacedTile, at coord: HexCoord) -> Bool {
        guard isOnBorder(coord) else { return true }
        for edge in 0..<HexGeometry.edgeCount where tile.code.values[edge] & ~allowedValue(at: coord, edge: edge) != 0 {
            return false
        }
        return tile.oriented.pipes.allSatisfy { staysInside($0, at: coord) }
    }

    // MARK: Cells

    /// Every cell of the region, in a stable order.
    public var coords: [HexCoord] {
        (-radius...radius).flatMap { q in
            (-radius...radius).map { HexCoord(q: q, r: $0) }
        }.filter(contains)
    }

    public var cellCount: Int { region?.active.count ?? 3 * radius * (radius + 1) + 1 }

    /// Whether `ref` is a port on the outline, facing out of the region.
    /// A masked region has no such ports: its edge runs wherever the mask
    /// does, not along the sides of cells.
    public func isOnOutline(_ ref: PortRef) -> Bool {
        mask == nil && contains(ref.coord) && ref.port.isValid(portsPerEdge: portsPerEdge)
            && !contains(ref.coord.neighbour(across: ref.port.edge))
    }

    /// Every port on the outline, going round the region.
    public var outlinePorts: [PortRef] {
        coords.flatMap { coord in
            (0..<HexGeometry.edgeCount).flatMap { edge in
                (0..<portsPerEdge).map { PortRef(coord: coord, port: Port(edge: edge, slot: $0)) }
            }
        }.filter(isOnOutline)
    }

    /// Replaces the openings. Ports that are not on the outline are ignored.
    /// A tile that no longer fits its cell, because an opening beside it was
    /// added or removed, is taken out so the cell can be regrown.
    public mutating func setOpenings(_ refs: some Sequence<PortRef>) {
        let next = Set(refs.filter(isOnOutline))
        let touched = Set(openings.symmetricDifference(next).map(\.coord))
        openings = next
        for coord in touched {
            if let placed = cells[coord], !fits(placed.code, at: coord) {
                cells[coord] = nil
            }
        }
    }

    /// Replaces the goals. Cells outside the region are ignored. The tile at
    /// any cell that becomes or stops being a goal is taken out, since it
    /// needs a different kind of tile.
    public mutating func setGoals(_ coords: some Sequence<HexCoord>) {
        let next = Set(coords.filter(contains))
        for coord in goals.symmetricDifference(next) {
            cells[coord] = nil
        }
        goals = next
    }

    /// The value a tile at `coord` must show on `edge`, or nil if anything
    /// goes: on the outline, exactly the openings there (usually none), and
    /// otherwise whatever a placed neighbour needs.
    public func requirement(at coord: HexCoord, edge: Int) -> Int? {
        let neighbour = coord.neighbour(across: edge)
        guard contains(neighbour) else {
            var value = 0
            for opening in openings where opening.coord == coord && opening.port.edge == edge {
                value |= 1 << (portsPerEdge - 1 - opening.port.slot)
            }
            return value
        }
        guard let placed = cells[neighbour] else { return nil }
        return placed.code.requiredNeighbourValue(forEdge: (edge + 3) % HexGeometry.edgeCount)
    }

    /// Whether an edge code satisfies every requirement at `coord`, and
    /// uses no port the mask closes.
    public func fits(_ code: EdgeCode, at coord: HexCoord) -> Bool {
        for edge in 0..<HexGeometry.edgeCount {
            if let required = requirement(at: coord, edge: edge), required != code.values[edge] {
                return false
            }
            if code.values[edge] & ~allowedValue(at: coord, edge: edge) != 0 {
                return false
            }
        }
        return true
    }

    /// Empty cells that must still be filled: ones a neighbouring pipe or an
    /// opening points into, and goals. The maze is not finished until there
    /// are none.
    public var openCells: [HexCoord] {
        coords.filter { coord in
            guard cells[coord] == nil else { return false }
            return goals.contains(coord) || (0..<HexGeometry.edgeCount).contains { edge in
                (requirement(at: coord, edge: edge) ?? 0) != 0
            }
        }
    }

    /// True once there is at least one tile and no pipe is left hanging.
    public var isSealed: Bool {
        !cells.isEmpty && openCells.isEmpty
    }

    /// The maze with `tile` placed at `coord` and at each of its images under
    /// `symmetry`, or nil if any of those cells is taken, the images disagree
    /// with each other, a neighbour does not match, or a pipe would cross
    /// the mask.
    public func placing(_ tile: PlacedTile, at coord: HexCoord, symmetry: Symmetry = .none) -> Maze? {
        guard tile.source.portsPerEdge == portsPerEdge else { return nil }
        var next = self
        var targets: [HexCoord] = []
        for transform in symmetry.transforms {
            let target = coord.transformed(by: transform)
            let image = tile.transformed(by: transform)
            guard contains(target), cells[target] == nil else { return nil }
            if let earlier = next.cells[target] {
                // A cell that maps onto itself needs a tile that does too.
                guard earlier.looksLike(image) else { return nil }
            } else {
                next.cells[target] = image
                targets.append(target)
            }
        }
        for target in targets {
            guard let placed = next.cells[target], next.fits(placed.code, at: target),
                  next.staysInside(placed, at: target)
            else { return nil }
        }
        return next
    }

    /// The cells `placing` would fill for a tile at `coord`.
    public func images(of coord: HexCoord, symmetry: Symmetry) -> [HexCoord] {
        var seen: [HexCoord] = []
        for transform in symmetry.transforms {
            let target = coord.transformed(by: transform)
            if !seen.contains(target) { seen.append(target) }
        }
        return seen
    }

    /// Removes the tile at `coord` and at each of its images.
    public mutating func remove(at coord: HexCoord, symmetry: Symmetry = .none) {
        for target in images(of: coord, symmetry: symmetry) {
            cells[target] = nil
        }
    }

    /// Removes every tile. Openings and goals stay where they are.
    public mutating func removeAll() {
        cells.removeAll()
    }
}
