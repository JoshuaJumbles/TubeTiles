/// A connection point on the boundary of a tile.
///
/// `edge` is 0...5 clockwise from the top edge. `slot` counts clockwise along
/// that edge from 0. How many slots an edge has is a property of the tile or
/// library, not of the port.
public struct Port: Hashable, Sendable, Codable, Comparable {
    public var edge: Int
    public var slot: Int

    public init(edge: Int, slot: Int) {
        self.edge = edge
        self.slot = slot
    }

    /// Builds a port from a flat index, `edge * portsPerEdge + slot`.
    public init(index: Int, portsPerEdge: Int) {
        self.init(edge: index / portsPerEdge, slot: index % portsPerEdge)
    }

    public func index(portsPerEdge: Int) -> Int {
        edge * portsPerEdge + slot
    }

    public func isValid(portsPerEdge: Int) -> Bool {
        (0..<HexGeometry.edgeCount).contains(edge) && (0..<portsPerEdge).contains(slot)
    }

    public func isOnOppositeEdge(from other: Port) -> Bool {
        (edge + 3) % HexGeometry.edgeCount == other.edge
    }

    /// True when the two ports look straight at each other across the tile.
    public func faces(_ other: Port, portsPerEdge: Int) -> Bool {
        isOnOppositeEdge(from: other) && other.slot == portsPerEdge - 1 - slot
    }

    /// The port on the neighbouring tile that touches this one.
    ///
    /// Both tiles number their slots clockwise, so along a shared edge the
    /// numbering runs in opposite directions.
    public func neighbourPort(portsPerEdge: Int) -> Port {
        Port(edge: (edge + 3) % HexGeometry.edgeCount, slot: portsPerEdge - 1 - slot)
    }

    public static func < (lhs: Port, rhs: Port) -> Bool {
        (lhs.edge, lhs.slot) < (rhs.edge, rhs.slot)
    }
}
