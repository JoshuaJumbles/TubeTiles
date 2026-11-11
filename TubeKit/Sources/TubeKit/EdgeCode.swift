/// Which ports of a tile are in use, as one number per edge.
///
/// Each edge value is the occupancy of its slots read as binary with slot 0
/// as the most significant bit, so with four ports per edge a pipe in slot 0
/// only gives 8. This is the profile used to decide which tiles can sit next
/// to each other; it says nothing about how ports are joined inside the tile.
public struct EdgeCode: Hashable, Sendable, Codable, CustomStringConvertible {
    public let portsPerEdge: Int
    /// Six values, one per edge, clockwise from the top.
    public let values: [Int]

    public init(portsPerEdge: Int, values: [Int]) {
        precondition(values.count == HexGeometry.edgeCount, "An edge code has one value per edge")
        self.portsPerEdge = portsPerEdge
        self.values = values
    }

    public init(portsPerEdge: Int, occupied ports: some Sequence<Port>) {
        var values = Array(repeating: 0, count: HexGeometry.edgeCount)
        for port in ports {
            values[port.edge] |= 1 << (portsPerEdge - 1 - port.slot)
        }
        self.init(portsPerEdge: portsPerEdge, values: values)
    }

    /// Parses the dash-separated form, for example `"0-0-0-0-2-8"`.
    public init?(_ string: String, portsPerEdge: Int) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false).map { Int($0) }
        guard parts.count == HexGeometry.edgeCount, !parts.contains(nil) else { return nil }
        self.init(portsPerEdge: portsPerEdge, values: parts.compactMap { $0 })
    }

    public var description: String {
        values.map(String.init).joined(separator: "-")
    }

    public func isOccupied(_ port: Port) -> Bool {
        values[port.edge] & (1 << (portsPerEdge - 1 - port.slot)) != 0
    }

    public var occupiedPorts: [Port] {
        (0..<HexGeometry.edgeCount).flatMap { edge in
            (0..<portsPerEdge).map { Port(edge: edge, slot: $0) }
        }.filter(isOccupied)
    }

    /// Number of pipe ends on the given edge.
    public func portCount(onEdge edge: Int) -> Int {
        values[edge].nonzeroBitCount
    }

    /// The value a neighbouring tile must show on the edge that touches
    /// `edge` for every pipe to continue across the join.
    public func requiredNeighbourValue(forEdge edge: Int) -> Int {
        Self.reversed(values[edge], width: portsPerEdge)
    }

    public func transformed(by transform: TileTransform) -> EdgeCode {
        let count = HexGeometry.edgeCount
        var result = values
        if transform.mirrored {
            result = (0..<count).map { edge in
                Self.reversed(values[(count - edge) % count], width: portsPerEdge)
            }
        }
        let mirroredValues = result
        for edge in 0..<count {
            result[(edge + transform.turns) % count] = mirroredValues[edge]
        }
        return EdgeCode(portsPerEdge: portsPerEdge, values: result)
    }

    /// Reverses the lowest `width` bits of `value`.
    public static func reversed(_ value: Int, width: Int) -> Int {
        var result = 0
        for bit in 0..<width where value & (1 << bit) != 0 {
            result |= 1 << (width - 1 - bit)
        }
        return result
    }
}
