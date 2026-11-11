/// Why a pipe cannot be added to a tile.
public enum PlacementError: Error, Equatable, Sendable {
    case portOutOfRange(Port)
    case samePort
    case portOccupied(Port)
    /// A bezier between neighbouring slots on one edge would fold back on itself.
    case tightUTurn
    /// Corners and rooms need two different edges to turn between.
    case needsTwoEdges
    /// Between opposite edges, corners and rooms can only run straight across.
    case mustRunStraightAcross
    /// Three pipes would overlap, or something would cross a room or bend.
    case overlap
}

/// The rules for where a pipe may go.
///
/// Shape rules depend only on the pipe's ports and kind. The overlap rule
/// (no more than two pipes crossing at any point) depends on the drawn shape
/// of every pipe on the tile and is checked with a `CoverageMap`.
public enum PlacementRules {
    /// Checks a pipe's own shape, ignoring what else is on the tile.
    public static func shapeError(for pipe: Pipe, portsPerEdge: Int) -> PlacementError? {
        for port in [pipe.a, pipe.b] where !port.isValid(portsPerEdge: portsPerEdge) {
            return .portOutOfRange(port)
        }
        if pipe.a == pipe.b { return .samePort }

        let sameEdge = pipe.a.edge == pipe.b.edge
        let offsetAcross = pipe.a.isOnOppositeEdge(from: pipe.b)
            && !pipe.a.faces(pipe.b, portsPerEdge: portsPerEdge)

        switch pipe.kind {
        case .bezier:
            if sameEdge && abs(pipe.a.slot - pipe.b.slot) <= 1 { return .tightUTurn }
        case .corner, .roomSmall, .roomMedium, .roomLarge:
            if sameEdge { return .needsTwoEdges }
            if offsetAcross { return .mustRunStraightAcross }
        }
        return nil
    }

    /// Checks a pipe against every rule: its own shape, the ports already in
    /// use, and the overlap rule.
    ///
    /// Pass the tile's `coverage` when checking many candidates against the
    /// same tile, to avoid rebuilding it each time.
    public static func error(
        adding pipe: Pipe, to tile: Tile, coverage: CoverageMap? = nil
    ) -> PlacementError? {
        if let error = shapeError(for: pipe, portsPerEdge: tile.portsPerEdge) { return error }
        for port in [pipe.a, pipe.b] where tile.pipe(at: port) != nil {
            return .portOccupied(port)
        }
        if !(coverage ?? CoverageMap(tile: tile)).fits(pipe) { return .overlap }
        return nil
    }
}
