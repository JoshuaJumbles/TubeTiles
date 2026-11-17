import Foundation

/// One of the ways a tile with `sides` equal edges can be placed: optionally
/// mirrored left-to-right, then rotated clockwise one edge at a time. A hex
/// tile has twelve.
///
/// Every operation on ports, points and edge codes is defined from this one
/// convention so that drawing, matching and path tracing can never disagree.
public struct TileTransform: Hashable, Sendable, Codable, CaseIterable {
    /// Clockwise steps of one edge, always 0..<sides.
    public let turns: Int
    /// Whether the tile is flipped across its vertical axis before rotating.
    public let mirrored: Bool
    /// How many edges the tile being placed has.
    public let sides: Int

    public init(turns: Int = 0, mirrored: Bool = false, sides: Int = HexGeometry.edgeCount) {
        self.turns = ((turns % sides) + sides) % sides
        self.mirrored = mirrored
        self.sides = sides
    }

    private enum CodingKeys: String, CodingKey {
        case turns, mirrored, sides
    }

    /// Loads through the ordinary initialiser, so turns are brought into
    /// range whatever a file says. Files from when every tile was a hexagon
    /// have no `sides`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            turns: try container.decode(Int.self, forKey: .turns),
            mirrored: try container.decode(Bool.self, forKey: .mirrored),
            sides: try container.decodeIfPresent(Int.self, forKey: .sides) ?? HexGeometry.edgeCount
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(turns, forKey: .turns)
        try container.encode(mirrored, forKey: .mirrored)
        if sides != HexGeometry.edgeCount { try container.encode(sides, forKey: .sides) }
    }

    public static let identity = TileTransform()

    /// The twelve placements of a hex tile.
    public static let allCases: [TileTransform] = all(sides: HexGeometry.edgeCount)

    /// Every placement of a tile with the given number of equal edges.
    public static func all(sides: Int) -> [TileTransform] {
        [false, true].flatMap { mirrored in
            (0..<sides).map { TileTransform(turns: $0, mirrored: mirrored, sides: sides) }
        }
    }

    public func apply(to port: Port, portsPerEdge: Int) -> Port {
        let count = sides
        var edge = port.edge
        var slot = port.slot
        if mirrored {
            // The top edge stays put, and the bottom one if there is one,
            // and the side edges swap across the vertical axis. Clockwise
            // order along an edge flips.
            edge = (count - edge) % count
            slot = portsPerEdge - 1 - slot
        }
        return Port(edge: (edge + turns) % count, slot: slot)
    }

    public func apply(to point: Point) -> Point {
        let x = mirrored ? -point.x : point.x
        let angle = Double(turns) * (2 * .pi / Double(sides))
        return Point(
            x: x * cos(angle) - point.y * sin(angle),
            y: x * sin(angle) + point.y * cos(angle)
        )
    }

    public func apply(to pipe: Pipe, portsPerEdge: Int) -> Pipe {
        Pipe(
            pipe.kind,
            a: apply(to: pipe.a, portsPerEdge: portsPerEdge),
            b: apply(to: pipe.b, portsPerEdge: portsPerEdge)
        )
    }

    /// The single transform equal to applying `self` and then `next`.
    public func then(_ next: TileTransform) -> TileTransform {
        // Moving a rotation past a mirror reverses its direction.
        TileTransform(
            turns: next.turns + (next.mirrored ? -turns : turns),
            mirrored: mirrored != next.mirrored,
            sides: sides
        )
    }

    public var inverse: TileTransform {
        mirrored ? self : TileTransform(turns: -turns, sides: sides)
    }
}
