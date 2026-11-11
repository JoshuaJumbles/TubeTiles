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

    /// Tiles grouped by edge code: the sets of interchangeable variants.
    public var tilesByEdgeCode: [EdgeCode: [Tile]] {
        Dictionary(grouping: tiles, by: \.edgeCode)
    }
}
