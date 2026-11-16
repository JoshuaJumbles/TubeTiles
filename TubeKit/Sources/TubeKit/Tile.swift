import Foundation

/// A hex tile: a set of pipes joining ports on its edges.
///
/// The order of `pipes` is the order they were added, which is also the order
/// they are stacked when drawn.
public struct Tile: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public let portsPerEdge: Int
    /// How thick the tile's pipes are. It decides which pipes have room
    /// beside each other, so the placement rules read it. Changing it leaves
    /// the pipes as they are, even ones that no longer clear each other.
    public var gauge: PipeGauge
    public internal(set) var pipes: [Pipe]

    public init(id: UUID = UUID(), portsPerEdge: Int, gauge: PipeGauge = .standard) {
        precondition(portsPerEdge > 0, "A tile needs at least one port per edge")
        self.id = id
        self.portsPerEdge = portsPerEdge
        self.gauge = gauge
        self.pipes = []
    }

    /// Builds a tile by adding each pipe in turn, failing on the first that
    /// breaks a placement rule.
    public init(
        id: UUID = UUID(), portsPerEdge: Int, gauge: PipeGauge = .standard, pipes: [Pipe]
    ) throws(PlacementError) {
        self.init(id: id, portsPerEdge: portsPerEdge, gauge: gauge)
        for pipe in pipes {
            try add(pipe)
        }
    }

    /// Builds a tile without checking placement rules. For data that was
    /// produced under other rules, such as imported tiles.
    init(id: UUID = UUID(), portsPerEdge: Int, gauge: PipeGauge = .standard, uncheckedPipes: [Pipe]) {
        self.init(id: id, portsPerEdge: portsPerEdge, gauge: gauge)
        self.pipes = uncheckedPipes
    }

    /// The sizes this tile's pipes are drawn and checked at.
    public var style: TileStyle { TileStyle(portsPerEdge: portsPerEdge, gauge: gauge) }

    /// The same tile at another pipe thickness.
    public func gauged(_ gauge: PipeGauge) -> Tile {
        var copy = self
        copy.gauge = gauge
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case id, portsPerEdge, gauge, pipes
    }

    // Tiles saved before pipes could be made thicker or thinner load at the
    // standard thickness, and standard tiles are still written without it.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        portsPerEdge = try container.decode(Int.self, forKey: .portsPerEdge)
        gauge = try container.decodeIfPresent(PipeGauge.self, forKey: .gauge) ?? .standard
        pipes = try container.decode([Pipe].self, forKey: .pipes)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(portsPerEdge, forKey: .portsPerEdge)
        if gauge != .standard { try container.encode(gauge, forKey: .gauge) }
        try container.encode(pipes, forKey: .pipes)
    }

    public mutating func add(_ pipe: Pipe) throws(PlacementError) {
        if let error = PlacementRules.error(adding: pipe, to: self) {
            throw error
        }
        pipes.append(pipe)
    }

    /// Removes the pipe ending at `port` and returns it, if there is one.
    @discardableResult
    public mutating func removePipe(at port: Port) -> Pipe? {
        guard let index = pipes.firstIndex(where: { $0.touches(port) }) else { return nil }
        return pipes.remove(at: index)
    }

    public func pipe(at port: Port) -> Pipe? {
        pipes.first { $0.touches(port) }
    }

    /// The port joined to `port` through this tile, if `port` is in use.
    public func connection(from port: Port) -> Port? {
        pipe(at: port)?.otherEnd(from: port)
    }

    public var occupiedPorts: Set<Port> {
        Set(pipes.flatMap(\.ports))
    }

    /// The tile's dead ends, if it has any.
    public var deadEnds: [Pipe] {
        pipes.filter(\.isDeadEnd)
    }

    public var freePorts: [Port] {
        let occupied = occupiedPorts
        return (0..<HexGeometry.edgeCount).flatMap { edge in
            (0..<portsPerEdge).map { Port(edge: edge, slot: $0) }
        }.filter { !occupied.contains($0) }
    }

    public var edgeCode: EdgeCode {
        EdgeCode(portsPerEdge: portsPerEdge, occupied: occupiedPorts)
    }

    /// Which port each occupied port is joined to, ignoring pipe kinds. A
    /// dead end's port maps to itself.
    ///
    /// Two tiles with the same edge code but different pairings are the
    /// variants that reroute a path without disturbing their neighbours.
    public var pairing: [Port: Port] {
        var result: [Port: Port] = [:]
        for pipe in pipes {
            result[pipe.a] = pipe.b
            result[pipe.b] = pipe.a
        }
        return result
    }

    /// The tile as it appears when placed with `transform`. Keeps its `id`.
    public func transformed(by transform: TileTransform) -> Tile {
        Tile(
            id: id,
            portsPerEdge: portsPerEdge,
            gauge: gauge,
            uncheckedPipes: pipes.map { transform.apply(to: $0, portsPerEdge: portsPerEdge) }
        )
    }
}
