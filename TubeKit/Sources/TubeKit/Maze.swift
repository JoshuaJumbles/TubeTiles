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
}

/// Tiles laid out on a hexagonal region of the grid.
///
/// The region is every cell within `radius` rings of the origin. Its outline
/// is sealed: no pipe may point out of it, except through an opening. Inside,
/// a cell may be empty, and an empty cell is fine as long as no neighbouring
/// pipe points into it.
public struct Maze: Hashable, Sendable, Codable {
    public let portsPerEdge: Int
    public let radius: Int
    public private(set) var cells: [HexCoord: PlacedTile] = [:]
    /// Ports on the outline where a pipe is required to leave the region:
    /// the entrance and exit of an open path.
    public private(set) var openings: Set<PortRef> = []

    public init(portsPerEdge: Int, radius: Int) {
        self.portsPerEdge = portsPerEdge
        self.radius = radius
    }

    public func contains(_ coord: HexCoord) -> Bool {
        coord.ring <= radius
    }

    /// Every cell of the region, in a stable order.
    public var coords: [HexCoord] {
        (-radius...radius).flatMap { q in
            (-radius...radius).map { HexCoord(q: q, r: $0) }
        }.filter(contains)
    }

    public var cellCount: Int { 3 * radius * (radius + 1) + 1 }

    /// Whether `ref` is a port on the outline, facing out of the region.
    public func isOnOutline(_ ref: PortRef) -> Bool {
        contains(ref.coord) && ref.port.isValid(portsPerEdge: portsPerEdge)
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

    /// Whether an edge code satisfies every requirement at `coord`.
    public func fits(_ code: EdgeCode, at coord: HexCoord) -> Bool {
        for edge in 0..<HexGeometry.edgeCount {
            if let required = requirement(at: coord, edge: edge), required != code.values[edge] {
                return false
            }
        }
        return true
    }

    /// Empty cells that a neighbouring pipe points into. The maze is not
    /// finished until there are none.
    public var openCells: [HexCoord] {
        coords.filter { coord in
            cells[coord] == nil && (0..<HexGeometry.edgeCount).contains { edge in
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
    /// with each other, or a neighbour does not match.
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
            guard let placed = next.cells[target], next.fits(placed.code, at: target) else { return nil }
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

    /// Removes every tile. Openings stay where they are.
    public mutating func removeAll() {
        cells.removeAll()
    }
}
