/// What a tile has to show at its edges to fill one particular cell of a
/// maze: which ports must carry a pipe, and which must be left empty.
///
/// It is read off the cell's neighbours, so a tile can be drawn to order for
/// a gap that nothing in the library fills.
public struct TileBrief: Hashable, Sendable {
    public let portsPerEdge: Int
    /// For each edge, the value the tile must show there, or nil where
    /// anything goes because no neighbour has been placed yet.
    public let required: [Int?]
    /// True for a goal cell, whose tile ends exactly one pipe in a room.
    public let needsDeadEnd: Bool

    public init(portsPerEdge: Int, required: [Int?], needsDeadEnd: Bool = false) {
        precondition(required.count == HexGeometry.edgeCount, "A brief has one requirement per edge")
        self.portsPerEdge = portsPerEdge
        self.required = required
        self.needsDeadEnd = needsDeadEnd
    }

    private func ports(wanted: Bool) -> Set<Port> {
        var result: Set<Port> = []
        for (edge, value) in required.enumerated() {
            guard let value else { continue }
            for slot in 0..<portsPerEdge where (value & (1 << (portsPerEdge - 1 - slot)) != 0) == wanted {
                result.insert(Port(edge: edge, slot: slot))
            }
        }
        return result
    }

    /// Ports that must carry a pipe.
    public var mustUse: Set<Port> { ports(wanted: true) }
    /// Ports that must be left empty.
    public var mustAvoid: Set<Port> { ports(wanted: false) }

    /// Ports that still need a pipe.
    public func missing(in tile: Tile) -> Set<Port> {
        mustUse.subtracting(tile.occupiedPorts)
    }

    /// Ports that have a pipe and must not.
    public func unwanted(in tile: Tile) -> Set<Port> {
        mustAvoid.intersection(tile.occupiedPorts)
    }

    /// Whether the tile has the dead ends the cell calls for: one for a
    /// goal, none anywhere else.
    public func hasRightDeadEnds(_ tile: Tile) -> Bool {
        tile.deadEnds.count == (needsDeadEnd ? 1 : 0)
    }

    /// Whether the tile could be placed in the cell exactly as drawn.
    public func isMet(by tile: Tile) -> Bool {
        tile.portsPerEdge == portsPerEdge && !tile.pipes.isEmpty
            && missing(in: tile).isEmpty && unwanted(in: tile).isEmpty && hasRightDeadEnds(tile)
    }
}

extension Maze {
    /// What a tile must show to fill `coord`, going by its neighbours and
    /// the outline. A tile already in the cell is ignored, so this also
    /// describes a replacement. Nil outside the maze.
    public func brief(at coord: HexCoord) -> TileBrief? {
        guard contains(coord) else { return nil }
        return TileBrief(
            portsPerEdge: portsPerEdge,
            required: (0..<HexGeometry.edgeCount).map { requirement(at: coord, edge: $0) },
            needsDeadEnd: goals.contains(coord)
        )
    }
}
