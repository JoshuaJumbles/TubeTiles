import Foundation

/// One of the twelve ways a hex tile can be placed: optionally mirrored
/// left-to-right, then rotated clockwise in 60 degree steps.
///
/// Every operation on ports, points and edge codes is defined from this one
/// convention so that drawing, matching and path tracing can never disagree.
public struct TileTransform: Hashable, Sendable, Codable, CaseIterable {
    /// Clockwise 60 degree steps, always 0...5.
    public let turns: Int
    /// Whether the tile is flipped across its vertical axis before rotating.
    public let mirrored: Bool

    public init(turns: Int = 0, mirrored: Bool = false) {
        let count = HexGeometry.edgeCount
        self.turns = ((turns % count) + count) % count
        self.mirrored = mirrored
    }

    public static let identity = TileTransform()

    public static let allCases: [TileTransform] = [false, true].flatMap { mirrored in
        (0..<HexGeometry.edgeCount).map { TileTransform(turns: $0, mirrored: mirrored) }
    }

    public func apply(to port: Port, portsPerEdge: Int) -> Port {
        let count = HexGeometry.edgeCount
        var edge = port.edge
        var slot = port.slot
        if mirrored {
            // The top and bottom edges stay put and the side edges swap
            // across the vertical axis. Clockwise order along an edge flips.
            edge = (count - edge) % count
            slot = portsPerEdge - 1 - slot
        }
        return Port(edge: (edge + turns) % count, slot: slot)
    }

    public func apply(to point: Point) -> Point {
        let x = mirrored ? -point.x : point.x
        let angle = Double(turns) * .pi / 3
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
            mirrored: mirrored != next.mirrored
        )
    }

    public var inverse: TileTransform {
        mirrored ? self : TileTransform(turns: -turns)
    }
}
