import Foundation

/// A hex tile: a set of pipes joining ports on its edges.
///
/// The order of `pipes` is the order they were added, which is also the order
/// they are stacked when drawn.
public struct Tile: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public let portsPerEdge: Int
    public internal(set) var pipes: [Pipe]

    public init(id: UUID = UUID(), portsPerEdge: Int) {
        precondition(portsPerEdge > 0, "A tile needs at least one port per edge")
        self.id = id
        self.portsPerEdge = portsPerEdge
        self.pipes = []
    }

    /// Builds a tile by adding each pipe in turn, failing on the first that
    /// breaks a placement rule.
    public init(id: UUID = UUID(), portsPerEdge: Int, pipes: [Pipe]) throws(PlacementError) {
        self.init(id: id, portsPerEdge: portsPerEdge)
        for pipe in pipes {
            try add(pipe)
        }
    }

    /// Builds a tile without checking placement rules. For data that was
    /// produced under other rules, such as imported tiles.
    init(id: UUID = UUID(), portsPerEdge: Int, uncheckedPipes: [Pipe]) {
        self.init(id: id, portsPerEdge: portsPerEdge)
        self.pipes = uncheckedPipes
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
            uncheckedPipes: pipes.map { transform.apply(to: $0, portsPerEdge: portsPerEdge) }
        )
    }
}
