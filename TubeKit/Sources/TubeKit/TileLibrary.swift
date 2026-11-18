import Foundation

/// A named collection of tiles built to one port count and one look.
///
/// A library can hold tiles of several shapes. What it shares across them
/// is the look: the port count, the pipe thickness and the rules below. Any
/// tiling whose cells are all shapes the library holds can be laid with it.
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
    /// The outlines the library's tiles can have, in the order they are
    /// shown. Never empty, and no shape twice.
    public let shapes: [TileShape]
    /// The pipe kinds this library's tiles are meant to use.
    public var allowedKinds: Set<PipeKind>
    /// How thick the pipes of every tile in the library are.
    public private(set) var gauge: PipeGauge
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
        deadSlots: Set<Int> = [],
        gauge: PipeGauge = .standard,
        shapes: [TileShape] = [.hexagon]
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.portsPerEdge = portsPerEdge
        self.shapes = Self.distinct(shapes)
        self.allowedKinds = allowedKinds
        self.gauge = gauge
        self.deadPorts = []
        self.tiles = []
        setDeadSlots(deadSlots)
    }

    /// The shapes in the order given, each once, or hexagons if there are
    /// none.
    private static func distinct(_ shapes: [TileShape]) -> [TileShape] {
        var result: [TileShape] = []
        for shape in shapes where !result.contains(shape) { result.append(shape) }
        return result.isEmpty ? [.hexagon] : result
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, note, portsPerEdge, shape, shapes, allowedKinds, gauge, deadPorts, tiles
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
        // A library of one shape is stored as it always was, under `shape`.
        let shapes = Self.distinct(
            try container.decodeIfPresent([TileShape].self, forKey: .shapes)
                ?? [try container.decodeIfPresent(TileShape.self, forKey: .shape) ?? .hexagon]
        )
        self.shapes = shapes
        allowedKinds = try container.decodeIfPresent(Set<PipeKind>.self, forKey: .allowedKinds)
            ?? Set(PipeKind.allCases)
        deadPorts = Set((try container.decodeIfPresent([Port].self, forKey: .deadPorts) ?? [])
            .filter { port in shapes.contains { $0.isValid(port, portsPerEdge: ports) } })
        let gauge = try container.decodeIfPresent(PipeGauge.self, forKey: .gauge) ?? .standard
        self.gauge = gauge
        tiles = try container.decode([Tile].self, forKey: .tiles)
            .filter { $0.portsPerEdge == ports && shapes.contains($0.shape) }
            .map { $0.gauged(gauge) }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(note, forKey: .note)
        try container.encode(portsPerEdge, forKey: .portsPerEdge)
        if shapes.count > 1 {
            try container.encode(shapes, forKey: .shapes)
        } else if shapes != [.hexagon] {
            try container.encode(shapes[0], forKey: .shape)
        }
        // In a fixed order, so saving the same library twice gives the same file.
        try container.encode(PipeKind.allCases.filter(allowedKinds.contains), forKey: .allowedKinds)
        if gauge != .standard { try container.encode(gauge, forKey: .gauge) }
        try container.encode(deadPorts.sorted(), forKey: .deadPorts)
        try container.encode(tiles, forKey: .tiles)
    }

    // MARK: Shapes

    /// The tiles of one shape, in the order they were saved.
    public func tiles(of shape: TileShape) -> [Tile] {
        tiles.filter { $0.shape == shape }
    }

    /// The tilings this library can lay: those whose every cell is a shape
    /// it holds. A library with more shapes than a tiling needs can still
    /// lay it, using only the tiles that fit.
    public var tilings: [Tiling] {
        Tiling.allCases.filter { $0.shapes.allSatisfy(shapes.contains) }
    }

    /// Whether tiles of `other` could be saved here: the same port count
    /// and at least one shape in common.
    public func canTakeTiles(from other: TileLibrary) -> Bool {
        other.portsPerEdge == portsPerEdge && other.shapes.contains(where: shapes.contains)
    }

    /// The most edges any of the library's shapes has.
    private var edgeCount: Int {
        shapes.map(\.edgeCount).max() ?? 0
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

    // MARK: Pipe thickness

    /// Changes how thick the pipes of every tile are. No tile is removed:
    /// ones whose pipes no longer clear each other stay and are still used.
    public mutating func setGauge(_ gauge: PipeGauge) {
        self.gauge = gauge
        tiles = tiles.map { $0.gauged(gauge) }
    }

    /// How many tiles have pipes that would not clear each other at the
    /// given thickness.
    public func crowdedTileCount(at gauge: PipeGauge) -> Int {
        tiles.filter { CoverageMap(tile: $0.gauged(gauge)).hasViolation }.count
    }

    // MARK: Dead ports

    public func isLive(_ port: Port) -> Bool {
        !deadPorts.contains(port)
    }

    /// The slots that are dead on every edge alike, or nil if the pattern
    /// differs between edges.
    public var deadSlots: Set<Int>? {
        let perEdge = (0..<edgeCount).map { edge in
            Set(deadPorts.filter { $0.edge == edge }.map(\.slot))
        }
        return perEdge.allSatisfy { $0 == perEdge[0] } ? perEdge[0] : nil
    }

    /// Makes the given slots dead on every edge of every shape.
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
        deadPorts = Set((0..<edgeCount).flatMap { edge in
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
        precondition(
            tile.portsPerEdge == portsPerEdge && shapes.contains(tile.shape),
            "Tile does not match the library's shapes and port count"
        )
        let tile = tile.gauged(gauge)
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
        var copy = TileLibrary(
            name: name, note: note, portsPerEdge: portsPerEdge, allowedKinds: allowedKinds, gauge: gauge,
            shapes: shapes
        )
        copy.deadPorts = deadPorts
        copy.tiles = tiles.map { tile in
            var twin = tile
            twin.id = UUID()
            return twin
        }
        return copy
    }

    // MARK: Bringing in another library

    /// Adds the tiles of `other` that this library does not already have,
    /// each as a tile of its own. A tile counts as already here if one of
    /// this library's draws the same pipes, as it stands or turned or
    /// flipped. Returns how many were added and how many were passed over.
    ///
    /// The other library's rules are not taken on. Its tiles are drawn at
    /// this library's pipe thickness, like every tile saved here. Tiles of a
    /// shape this library does not hold are passed over, and nothing is
    /// added if the port counts differ.
    @discardableResult
    public mutating func merge(_ other: TileLibrary) -> (added: Int, skipped: Int) {
        guard canTakeTiles(from: other) else { return (0, other.tiles.count) }
        var added = 0
        var skipped = 0
        for tile in other.tiles where !tile.pipes.isEmpty {
            guard shapes.contains(tile.shape) else {
                skipped += 1
                continue
            }
            var copy = tile
            copy.id = UUID()
            if twin(of: copy) == nil {
                save(copy)
                added += 1
            } else {
                skipped += 1
            }
        }
        return (added, skipped)
    }

    /// This library under a new identity and name, tiles and rules intact,
    /// for adding a library that came from somewhere else.
    public func adopted(named name: String) -> TileLibrary {
        var copy = duplicated(named: name)
        copy.id = UUID()
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
        let profile = tile.profile
        for stored in tiles where stored.id != tile.id && stored.pipes.count == wanted.count {
            guard stored.shape == tile.shape, stored.profile == profile else { continue }
            // The plain placement first, so an exact copy is reported as one.
            for transform in tile.shape.transforms where Set(stored.transformed(by: transform).pipes) == wanted {
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
        Dictionary(grouping: tiles) { $0.profile }
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
