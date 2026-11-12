import Foundation

/// A named collection of tiles built to one port count and one look.
///
/// A library carries the rules its tiles are meant to follow: which pipe
/// kinds they use, and which ports are left alone. The rules steer the editor
/// and, above all, the tiles the generator makes up, so a maze grown from a
/// library keeps that library's character.
public struct TileLibrary: Hashable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    /// What the library is for, in the maker's own words.
    public var note: String
    public let portsPerEdge: Int
    /// The pipe kinds this library's tiles are meant to use.
    public var allowedKinds: Set<PipeKind>
    /// Ports this library's tiles are meant to leave unused.
    ///
    /// Stored port by port so that a pattern could differ from edge to edge.
    /// Today they are only ever set through `setDeadSlots`, which gives every
    /// edge the same pattern, so any tile can still be turned or flipped.
    public private(set) var deadPorts: Set<Port>
    public private(set) var tiles: [Tile]

    public init(
        id: UUID = UUID(),
        name: String,
        note: String = "",
        portsPerEdge: Int,
        allowedKinds: Set<PipeKind> = Set(PipeKind.allCases),
        deadSlots: Set<Int> = []
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.portsPerEdge = portsPerEdge
        self.allowedKinds = allowedKinds
        self.deadPorts = []
        self.tiles = []
        setDeadSlots(deadSlots)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, note, portsPerEdge, allowedKinds, deadPorts, tiles
    }

    /// Libraries saved before they had an identity, a note or rules load
    /// with a fresh identity, no note and every kind allowed.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let ports = try container.decode(Int.self, forKey: .portsPerEdge)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        portsPerEdge = ports
        allowedKinds = try container.decodeIfPresent(Set<PipeKind>.self, forKey: .allowedKinds)
            ?? Set(PipeKind.allCases)
        deadPorts = Set((try container.decodeIfPresent([Port].self, forKey: .deadPorts) ?? [])
            .filter { $0.isValid(portsPerEdge: ports) })
        tiles = try container.decode([Tile].self, forKey: .tiles).filter { $0.portsPerEdge == ports }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(note, forKey: .note)
        try container.encode(portsPerEdge, forKey: .portsPerEdge)
        // In a fixed order, so saving the same library twice gives the same file.
        try container.encode(PipeKind.allCases.filter(allowedKinds.contains), forKey: .allowedKinds)
        try container.encode(deadPorts.sorted(), forKey: .deadPorts)
        try container.encode(tiles, forKey: .tiles)
    }

    // MARK: Rules

    /// The allowed kinds that join two ports, in palette order.
    public var throughKinds: [PipeKind] {
        PipeKind.throughKinds.filter(allowedKinds.contains)
    }

    /// The allowed dead-end kinds, largest first.
    public var deadEndKinds: [PipeKind] {
        PipeKind.deadEndKinds.filter(allowedKinds.contains)
    }

    /// Whether every pipe of `tile` is of an allowed kind.
    public func allows(_ tile: Tile) -> Bool {
        tile.pipes.allSatisfy { allowedKinds.contains($0.kind) }
    }

    // MARK: Dead ports

    public func isLive(_ port: Port) -> Bool {
        !deadPorts.contains(port)
    }

    /// The slots that are dead on every edge alike, or nil if the pattern
    /// differs between edges.
    public var deadSlots: Set<Int>? {
        let perEdge = (0..<HexGeometry.edgeCount).map { edge in
            Set(deadPorts.filter { $0.edge == edge }.map(\.slot))
        }
        return perEdge.allSatisfy { $0 == perEdge[0] } ? perEdge[0] : nil
    }

    /// Makes the given slots dead on all six edges.
    ///
    /// A slot's mirror image is made dead with it. Flipping a tile reverses
    /// the order of the ports along each edge, so without this a flipped tile
    /// could land a pipe on a dead port.
    public mutating func setDeadSlots(_ slots: some Sequence<Int>) {
        var mirrored: Set<Int> = []
        for slot in slots where (0..<portsPerEdge).contains(slot) {
            mirrored.insert(slot)
            mirrored.insert(portsPerEdge - 1 - slot)
        }
        deadPorts = Set((0..<HexGeometry.edgeCount).flatMap { edge in
            mirrored.map { Port(edge: edge, slot: $0) }
        })
    }

    /// How many ports per edge are still in use, when every edge is alike.
    public var liveSlotCount: Int? {
        deadSlots.map { portsPerEdge - $0.count }
    }

    /// Whether any pipe of `tile` ends on a dead port.
    public func usesDeadPort(_ tile: Tile) -> Bool {
        !tile.occupiedPorts.isDisjoint(with: deadPorts)
    }

    /// Tiles with a pipe on a port that is now dead. Like tiles of a kind
    /// that has been switched off, they stay and are still used.
    public var deadPortTiles: [Tile] {
        tiles.filter(usesDeadPort)
    }

    /// Tiles that use a kind the library no longer allows. They stay in the
    /// library and are still used; the rules only steer what gets made next.
    public var offPaletteTiles: [Tile] {
        tiles.filter { !allows($0) }
    }

    // MARK: Tiles

    /// Adds a tile, or replaces the stored tile with the same `id`.
    public mutating func save(_ tile: Tile) {
        precondition(tile.portsPerEdge == portsPerEdge, "Tile does not match the library's port count")
        if let index = tiles.firstIndex(where: { $0.id == tile.id }) {
            tiles[index] = tile
        } else {
            tiles.append(tile)
        }
    }

    public mutating func remove(id: Tile.ID) {
        tiles.removeAll { $0.id == id }
    }

    public func contains(id: Tile.ID) -> Bool {
        tiles.contains { $0.id == id }
    }

    /// A separate library with the same rules and its own copies of the
    /// tiles, for branching a style.
    public func duplicated(named name: String) -> TileLibrary {
        var copy = TileLibrary(name: name, note: note, portsPerEdge: portsPerEdge, allowedKinds: allowedKinds)
        copy.deadPorts = deadPorts
        copy.tiles = tiles.map { tile in
            var twin = tile
            twin.id = UUID()
            return twin
        }
        return copy
    }

    // MARK: Duplicates

    /// A stored tile that draws exactly the pipes of `tile`, as it stands or
    /// once turned or flipped, and how it has to be placed to do so. The
    /// stored tile with the same `id` is `tile` itself and does not count.
    ///
    /// Pipes of a different kind between the same ports make a different
    /// tile.
    public func twin(of tile: Tile) -> (tile: Tile, transform: TileTransform)? {
        guard !tile.pipes.isEmpty else { return nil }
        let wanted = Set(tile.pipes)
        let profile = tile.edgeCode.canonical
        for stored in tiles where stored.id != tile.id && stored.pipes.count == wanted.count {
            guard stored.edgeCode.canonical == profile else { continue }
            // The plain placement first, so an exact copy is reported as one.
            for transform in TileTransform.allCases where Set(stored.transformed(by: transform).pipes) == wanted {
                return (stored, transform)
            }
        }
        return nil
    }

    // MARK: Views of the tiles

    /// Tiles grouped by exact edge code, as drawn.
    public var tilesByEdgeCode: [EdgeCode: [Tile]] {
        Dictionary(grouping: tiles, by: \.edgeCode)
    }

    /// Tiles grouped by canonical edge code: each group is a set of variants
    /// the generator can swap for one another, turning or flipping as needed.
    public var tilesByProfile: [EdgeCode: [Tile]] {
        Dictionary(grouping: tiles) { $0.edgeCode.canonical }
    }

    /// For each edge pattern, how many tiles have an edge that can show it.
    /// Patterns no tile offers are absent.
    public var edgePatternCounts: [Int: Int] {
        var counts: [Int: Int] = [:]
        for tile in tiles {
            let patterns = Set(tile.edgeCode.values.map { EdgeCode.pattern($0, width: portsPerEdge) })
            for pattern in patterns {
                counts[pattern, default: 0] += 1
            }
        }
        return counts
    }
}
