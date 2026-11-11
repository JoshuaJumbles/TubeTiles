import Foundation

/// A named collection of tiles built to one port count and one look.
///
/// A library carries the rules its tiles are meant to follow. For now that is
/// which pipe kinds they use. The rules steer the editor and, above all, the
/// tiles the generator makes up, so a maze grown from a library keeps that
/// library's character.
public struct TileLibrary: Hashable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    /// What the library is for, in the maker's own words.
    public var note: String
    public let portsPerEdge: Int
    /// The pipe kinds this library's tiles are meant to use.
    public var allowedKinds: Set<PipeKind>
    public private(set) var tiles: [Tile]

    public init(
        id: UUID = UUID(),
        name: String,
        note: String = "",
        portsPerEdge: Int,
        allowedKinds: Set<PipeKind> = Set(PipeKind.allCases)
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.portsPerEdge = portsPerEdge
        self.allowedKinds = allowedKinds
        self.tiles = []
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, note, portsPerEdge, allowedKinds, tiles
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
        copy.tiles = tiles.map { tile in
            var twin = tile
            twin.id = UUID()
            return twin
        }
        return copy
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
