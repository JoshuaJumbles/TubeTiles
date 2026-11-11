/// A named collection of tiles that all share one port count.
public struct TileLibrary: Hashable, Sendable, Codable {
    public var name: String
    public let portsPerEdge: Int
    public private(set) var tiles: [Tile]

    public init(name: String, portsPerEdge: Int) {
        self.name = name
        self.portsPerEdge = portsPerEdge
        self.tiles = []
    }

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
