/// Which ports of a tile are in use, as one number per edge.
///
/// Each edge value is the occupancy of its slots read as binary with slot 0
/// as the most significant bit, so with four ports per edge a pipe in slot 0
/// only gives 8. This is the profile used to decide which tiles can sit next
/// to each other; it says nothing about how ports are joined inside the tile.
public struct EdgeCode: Hashable, Sendable, Codable, CustomStringConvertible {
    public let portsPerEdge: Int
    /// One value per edge, clockwise from the top: six for a hexagon.
    public let values: [Int]

    public init(portsPerEdge: Int, values: [Int]) {
        precondition(values.count >= 3, "An edge code has one value per edge")
        self.portsPerEdge = portsPerEdge
        self.values = values
    }

    public init(
        portsPerEdge: Int, edgeCount: Int = HexGeometry.edgeCount, occupied ports: some Sequence<Port>
    ) {
        var values = Array(repeating: 0, count: edgeCount)
        for port in ports {
            values[port.edge] |= 1 << (portsPerEdge - 1 - port.slot)
        }
        self.init(portsPerEdge: portsPerEdge, values: values)
    }

    /// Parses the dash-separated form, for example `"0-0-0-0-2-8"`.
    public init?(_ string: String, portsPerEdge: Int, edgeCount: Int = HexGeometry.edgeCount) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false).map { Int($0) }
        guard parts.count == edgeCount, !parts.contains(nil) else { return nil }
        self.init(portsPerEdge: portsPerEdge, values: parts.compactMap { $0 })
    }

    public var description: String {
        values.map(String.init).joined(separator: "-")
    }

    public func isOccupied(_ port: Port) -> Bool {
        values[port.edge] & (1 << (portsPerEdge - 1 - port.slot)) != 0
    }

    public var occupiedPorts: [Port] {
        values.indices.flatMap { edge in
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
        let count = values.count
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

    /// The same profile in a standard orientation: the smallest of its
    /// placements, twelve for a hexagon. Two tiles the generator can use interchangeably,
    /// after turning or flipping one of them, share a canonical code.
    public var canonical: EdgeCode {
        TileTransform.all(sides: values.count)
            .map { transformed(by: $0) }
            .min { $0.values.lexicographicallyPrecedes($1.values) } ?? self
    }

    /// The same profile in a standard orientation for a tile that can only
    /// be placed in the given ways: the smallest of those placements.
    public func canonical(under transforms: [TileTransform]) -> EdgeCode {
        transforms
            .map { transformed(by: $0) }
            .min { $0.values.lexicographicallyPrecedes($1.values) } ?? self
    }

    /// A single edge's pattern, ignoring direction: the smaller of the value
    /// and its bit reversal. A tile can show either by being flipped.
    public static func pattern(_ value: Int, width: Int) -> Int {
        min(value, reversed(value, width: width))
    }

    /// Every distinct edge pattern for a port count, including the empty edge.
    public static func allPatterns(portsPerEdge: Int) -> [Int] {
        (0..<(1 << portsPerEdge)).filter { $0 == pattern($0, width: portsPerEdge) }
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
