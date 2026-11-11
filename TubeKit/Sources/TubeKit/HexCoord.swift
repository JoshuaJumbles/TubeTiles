import Foundation

/// A cell on the grid of flat-top hexes that mazes are built on.
///
/// Axial coordinates: `q` counts columns to the right, and `r` counts cells
/// down within a column. Stepping across edge 0 goes straight up.
public struct HexCoord: Hashable, Sendable, Codable, Comparable {
    public var q: Int
    public var r: Int

    public init(q: Int, r: Int) {
        self.q = q
        self.r = r
    }

    public static let origin = HexCoord(q: 0, r: 0)

    private static let steps: [(q: Int, r: Int)] = [
        (0, -1), (1, -1), (1, 0), (0, 1), (-1, 1), (-1, 0),
    ]

    /// The cell on the other side of the given edge.
    public func neighbour(across edge: Int) -> HexCoord {
        let step = Self.steps[edge]
        return HexCoord(q: q + step.q, r: r + step.r)
    }

    /// Centre of the cell, in units of the tile circumradius.
    public var center: Point {
        Point(x: 1.5 * Double(q), y: (3.0).squareRoot() * (Double(r) + Double(q) / 2))
    }

    /// How many cells from the origin: the ring this cell sits on.
    public var ring: Int {
        max(abs(q), abs(r), abs(q + r))
    }

    /// Where the cell lands when the whole grid is flipped and turned about
    /// the origin, using the same convention as tiles.
    public func transformed(by transform: TileTransform) -> HexCoord {
        var q = q
        var r = r
        if transform.mirrored {
            (q, r) = (-q, r + q)
        }
        for _ in 0..<transform.turns {
            (q, r) = (-r, q + r)
        }
        return HexCoord(q: q, r: r)
    }

    public static func < (lhs: HexCoord, rhs: HexCoord) -> Bool {
        (lhs.q, lhs.r) < (rhs.q, rhs.r)
    }
}

/// A symmetry the maze keeps as it grows. Every placement and removal is
/// repeated at each image of the cell.
public enum Symmetry: String, CaseIterable, Sendable, Codable {
    case none
    /// Left and right halves mirror each other.
    case mirror
    /// Looks the same after a half turn.
    case half
    /// Looks the same after a third of a turn.
    case third
    /// Looks the same after a sixth of a turn.
    case sixth

    /// The grid transforms that leave a maze with this symmetry unchanged.
    public var transforms: [TileTransform] {
        switch self {
        case .none: [.identity]
        case .mirror: [.identity, TileTransform(mirrored: true)]
        case .half: [.identity, TileTransform(turns: 3)]
        case .third: [0, 2, 4].map { TileTransform(turns: $0) }
        case .sixth: (0..<6).map { TileTransform(turns: $0) }
        }
    }
}
