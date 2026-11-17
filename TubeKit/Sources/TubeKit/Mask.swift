import Foundation

/// The space a maze is allowed to take up: a shape in the plane the maze is
/// drawn on, in units of the tile circumradius, with the centre of the
/// origin cell at zero.
///
/// A mask knows nothing about tiles or the grid. It only answers whether a
/// point is inside, so the same mask would bound any tiling laid over it.
/// A maze closes every port that falls outside its mask and refuses any pipe
/// whose drawn shape would cross it.
///
/// A mask is a list of shapes applied in order. Each one either adds its
/// area or takes it away, so cut-outs and compound outlines are built from
/// the same few pieces.
public struct Mask: Hashable, Sendable, Codable {
    public struct Shape: Hashable, Sendable, Codable {
        public enum Kind: String, Sendable, Codable {
            case rectangle
        }

        public var kind: Kind
        public var center: Point
        public var width: Double
        public var height: Double
        /// True for a shape that removes its area from what came before.
        public var subtracts: Bool

        public init(
            _ kind: Kind = .rectangle, center: Point = .zero, width: Double, height: Double, subtracts: Bool = false
        ) {
            self.kind = kind
            self.center = center
            self.width = width
            self.height = height
            self.subtracts = subtracts
        }

        /// Whether `point` is inside the shape once its outline has been
        /// moved by `margin`: outwards if positive, inwards if negative.
        func contains(_ point: Point, margin: Double) -> Bool {
            switch kind {
            case .rectangle:
                abs(point.x - center.x) <= width / 2 + margin && abs(point.y - center.y) <= height / 2 + margin
            }
        }
    }

    public var shapes: [Shape]

    public init(shapes: [Shape]) {
        self.shapes = shapes
    }

    public static func rectangle(center: Point = .zero, width: Double, height: Double) -> Mask {
        Mask(shapes: [Shape(center: center, width: width, height: height)])
    }

    /// Whether `point` is inside the mask and at least `inset` away from its
    /// edge. The inset is what keeps a pipe's full width inside, not just
    /// its centre line.
    public func contains(_ point: Point, inset: Double = 0) -> Bool {
        var inside = false
        for shape in shapes {
            if shape.subtracts {
                // A cut-out grows by the inset, so things keep clear of it.
                if shape.contains(point, margin: inset) { inside = false }
            } else if shape.contains(point, margin: -inset) {
                inside = true
            }
        }
        return inside
    }

    /// The smallest upright rectangle around everything the mask adds, or
    /// nil if it adds nothing.
    public var bounds: (min: Point, max: Point)? {
        let adding = shapes.filter { !$0.subtracts }
        guard let first = adding.first else { return nil }
        var low = Point(x: first.center.x - first.width / 2, y: first.center.y - first.height / 2)
        var high = Point(x: first.center.x + first.width / 2, y: first.center.y + first.height / 2)
        for shape in adding.dropFirst() {
            low.x = min(low.x, shape.center.x - shape.width / 2)
            low.y = min(low.y, shape.center.y - shape.height / 2)
            high.x = max(high.x, shape.center.x + shape.width / 2)
            high.y = max(high.y, shape.center.y + shape.height / 2)
        }
        return (low, high)
    }
}

/// How a mask falls on the hex grid: which cells are in play, and which of
/// their ports it closes. Worked out once per maze shape.
struct MaskedRegion: Hashable, Sendable {
    /// Cells with enough of themselves inside the mask to hold a tile.
    var active: Set<HexCoord> = []
    /// For each cell the mask touches, the ports on each edge that may
    /// still carry a pipe, as bits in edge-code order. Cells that are not
    /// listed have every port.
    var allowed: [HexCoord: [Int]] = [:]
    /// Cells where a pipe could reach outside the mask, so each one has to
    /// be checked.
    var border: Set<HexCoord> = []

    /// A cell is in play only if the mask leaves ports open on at least
    /// this many of its edges.
    static let fewestEdges = 3

    init(mask: Mask, style: TileStyle, radius: Int) {
        let count = style.portsPerEdge
        let inset = style.pipeWidth / 2
        let all = (-radius...radius).flatMap { q in (-radius...radius).map { HexCoord(q: q, r: $0) } }
            .filter { $0.ring <= radius }
        let full = (1 << count) - 1

        /// A port sits on an edge two cells share. It is judged once, from
        /// one side, so both cells always get the same answer.
        func isLive(_ coord: HexCoord, _ port: Port) -> Bool {
            let neighbour = coord.neighbour(across: port.edge)
            guard neighbour.ring <= radius else { return false }
            if port.edge >= 3 {
                return isLive(neighbour, Port(edge: port.edge - 3, slot: count - 1 - port.slot))
            }
            return mask.contains(coord.center + HexGeometry.position(of: port, portsPerEdge: count), inset: inset)
        }

        var bits: [HexCoord: [Int]] = [:]
        for coord in all {
            bits[coord] = (0..<HexGeometry.edgeCount).map { edge in
                (0..<count).reduce(0) { value, slot in
                    isLive(coord, Port(edge: edge, slot: slot)) ? value | (1 << (count - 1 - slot)) : value
                }
            }
        }

        /// Cells the mask's edge passes through or near.
        func touchesEdge(_ coord: HexCoord) -> Bool {
            bits[coord]?.contains { $0 != full } ?? false || (0..<HexGeometry.edgeCount).contains { corner in
                !mask.contains(coord.center + HexGeometry.corner(corner), inset: inset)
            }
        }
        let edgeCells = all.filter(touchesEdge)

        // A port is only worth having if some pipe can leave it and reach
        // another open port of the same cell without crossing the mask.
        // Slivers of cells at the edge often have ports that are inside but
        // that nothing can be drawn from. Close those, on both sides, and
        // look again: closing one can leave another with no partner.
        let blank = Tile(portsPerEdge: count, gauge: style.gauge, shape: style.shape)
        let coverage = CoverageMap(tile: blank)
        func canBeDrawn(from port: Port, in coord: HexCoord, among live: [Port]) -> Bool {
            for partner in live where partner != port {
                for kind in [PipeKind.bezier, .corner] {
                    let pipe = Pipe(kind, a: port, b: partner)
                    if PlacementRules.error(adding: pipe, to: blank, coverage: coverage) == nil,
                       Self.staysInside(pipe, at: coord, mask: mask, style: style) {
                        return true
                    }
                }
            }
            return false
        }
        var changed = true
        while changed {
            changed = false
            for coord in edgeCells {
                guard let edges = bits[coord] else { continue }
                let live = (0..<HexGeometry.edgeCount).flatMap { edge in
                    (0..<count).filter { edges[edge] & (1 << (count - 1 - $0)) != 0 }.map { Port(edge: edge, slot: $0) }
                }
                // A cell reached through only one or two of its edges is a
                // sliver: whatever its neighbours send in has to turn straight
                // back, which few sets of pipes can do. Leaving those out
                // costs a thin strip at the edge and makes the rest reliable.
                let edgesInUse = edges.filter { $0 != 0 }.count
                let isSliver = edgesInUse > 0 && edgesInUse < Self.fewestEdges
                for port in live where isSliver || !canBeDrawn(from: port, in: coord, among: live) {
                    let bit = 1 << (count - 1 - port.slot)
                    bits[coord]?[port.edge] &= ~bit
                    let across = (port.edge + 3) % HexGeometry.edgeCount
                    bits[coord.neighbour(across: port.edge)]?[across] &= ~(1 << port.slot)
                    changed = true
                }
            }
        }

        for coord in all {
            guard let edges = bits[coord], edges.contains(where: { $0 != 0 }) else { continue }
            active.insert(coord)
            let closesPort = edges.contains { $0 != full }
            if closesPort { allowed[coord] = edges }
            if closesPort || touchesEdge(coord) { border.insert(coord) }
        }
    }

    /// Whether `pipe`, drawn in the cell at `coord`, keeps its whole width
    /// inside the mask.
    static func staysInside(_ pipe: Pipe, at coord: HexCoord, mask: Mask, style: TileStyle) -> Bool {
        let inset = style.pipeWidth / 2
        let origin = coord.center
        let shape = PipeShape(pipe, style: style)
        for segment in shape.segments {
            let points: [Point]
            switch segment {
            case let .line(start, end):
                // Sampled along its length too: a straight run can cross a
                // cut-out with both ends clear of it.
                points = (0...8).map { start + (end - start) * (Double($0) / 8) }
            case .cubic:
                points = segment.flattened(steps: 12)
            }
            for point in points where !mask.contains(origin + point, inset: inset) { return false }
        }
        if let room = shape.room, !mask.contains(origin + room.center, inset: room.diameter / 2) {
            return false
        }
        return true
    }
}
