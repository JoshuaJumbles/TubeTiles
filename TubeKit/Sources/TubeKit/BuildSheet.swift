import Foundation

/// What it takes to build a maze from real tiles: each distinct tile it
/// uses, how many of each, and which one goes in every cell and which way
/// round.
///
/// Two placements use the same tile when one can be turned to give the
/// other. Whether a tile flipped over counts as the same is a choice: a
/// paper stencil can be turned over, a painted tile cannot.
///
/// Over and under at crossings is left out. It is settled across the whole
/// maze, so two copies of one tile can weave differently, and a tile here is
/// only its pipes.
public struct BuildSheet: Sendable {
    /// One distinct tile.
    public struct Entry: Identifiable, Sendable {
        /// A, B, C… then AA, AB… in order of how often the tile is used.
        public let label: String
        /// The tile the right way up. Every placement is this, turned.
        public let tile: Tile
        public let count: Int

        public var id: String { label }
    }

    /// Which tile sits in a cell, and how it has to be turned (and flipped,
    /// if flipping is allowed) from the way its entry shows it.
    public struct Placement: Hashable, Sendable {
        public let entry: Int
        public let transform: TileTransform
    }

    public let entries: [Entry]
    public let placements: [HexCoord: Placement]
    public let flippedIsSame: Bool

    /// How many tiles the maze has in all.
    public var tileCount: Int { placements.count }

    public init(maze: Maze, flippedIsSame: Bool = false) {
        self.flippedIsSame = flippedIsSame

        struct Found {
            var tile: Tile
            var cells: [(HexCoord, TileTransform)] = []
        }
        var found: [[Int]: Found] = [:]
        for coord in maze.cells.keys.sorted() {
            guard let placed = maze.cells[coord] else { continue }
            // The turn that gives the smallest description is the same for
            // every placement of a tile, so it serves as the right way up.
            var best: (key: [Int], tile: Tile, transform: TileTransform)?
            for transform in placed.oriented.shape.transforms where flippedIsSame || !transform.mirrored {
                let turned = placed.oriented.transformed(by: transform)
                let key = Self.key(for: turned)
                if best == nil || key.lexicographicallyPrecedes(best!.key) {
                    best = (key, turned, transform)
                }
            }
            guard let best else { continue }
            var entry = found[best.key] ?? Found(
                tile: Tile(
                    portsPerEdge: maze.portsPerEdge, gauge: maze.gauge, shape: best.tile.shape,
                    uncheckedPipes: best.tile.pipes
                )
            )
            // Undoing that turn takes the upright tile back to the cell.
            entry.cells.append((coord, best.transform.inverse))
            found[best.key] = entry
        }

        let ordered = found.sorted { lhs, rhs in
            lhs.value.cells.count != rhs.value.cells.count
                ? lhs.value.cells.count > rhs.value.cells.count
                : lhs.key.lexicographicallyPrecedes(rhs.key)
        }
        var entries: [Entry] = []
        var placements: [HexCoord: Placement] = [:]
        for (index, item) in ordered.enumerated() {
            entries.append(Entry(label: Self.label(index), tile: item.value.tile, count: item.value.cells.count))
            for (coord, transform) in item.value.cells {
                placements[coord] = Placement(entry: index, transform: transform)
            }
        }
        self.entries = entries
        self.placements = placements
    }

    /// A, B … Z, AA, AB … for 0, 1 … 25, 26, 27 …
    public static func label(_ index: Int) -> String {
        var number = index
        var text = ""
        repeat {
            text = String(UnicodeScalar(UInt8(65 + number % 26))) + text
            number = number / 26 - 1
        } while number >= 0
        return text
    }

    /// A tile's shape and pipes as numbers, the same however the pipes are
    /// ordered. The shape leads, so the same pipes on two shapes are two
    /// stencils.
    private static func key(for tile: Tile) -> [Int] {
        let kinds = PipeKind.allCases
        return [tile.shape.edgeCount] + tile.pipes
            .map { [kinds.firstIndex(of: $0.kind) ?? 0, $0.a.edge, $0.a.slot, $0.b.edge, $0.b.slot] }
            .sorted { $0.lexicographicallyPrecedes($1) }
            .flatMap { $0 }
    }
}
