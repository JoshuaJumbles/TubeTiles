/// Builds a valid tile that uses exactly a given set of ports.
///
/// This is what lets a maze continue where the library has no tile with the
/// right edges: the ports are fixed by the neighbours, and the synthesizer
/// finds some legal way to join them up.
public enum TileSynthesizer {
    /// Mostly curves, some corners, the occasional small room.
    public static let defaultKinds: [PipeKind] =
        Array(repeating: .bezier, count: 8) + Array(repeating: .corner, count: 3) + [.roomSmall]

    /// A tile whose pipes use every port in `ports` once, or nil if no legal
    /// pairing was found within the search budget.
    ///
    /// - Parameters:
    ///   - invariantUnder: Transforms the finished tile must look the same
    ///     under. Needed for cells that a maze symmetry maps onto themselves.
    ///     `ports` must already be closed under them.
    ///   - kinds: Pipe kinds to draw from; repeats make a kind more likely.
    public static func tile(
        portsPerEdge: Int,
        ports: some Collection<Port>,
        invariantUnder symmetries: [TileTransform] = [],
        kinds: [PipeKind] = defaultKinds,
        using generator: inout some RandomNumberGenerator
    ) -> Tile? {
        let wanted = Set(ports)
        guard wanted.count == ports.count, wanted.count % 2 == 0,
              wanted.allSatisfy({ $0.isValid(portsPerEdge: portsPerEdge) })
        else { return nil }

        let empty = Tile(portsPerEdge: portsPerEdge)
        var budget = 300
        return pair(
            wanted, into: empty, coverage: CoverageMap(tile: empty),
            symmetries: symmetries, kinds: kinds, budget: &budget, using: &generator
        )
    }

    private static func pair(
        _ remaining: Set<Port>,
        into tile: Tile,
        coverage: CoverageMap,
        symmetries: [TileTransform],
        kinds: [PipeKind],
        budget: inout Int,
        using generator: inout some RandomNumberGenerator
    ) -> Tile? {
        guard let first = remaining.min() else { return tile }
        budget -= 1
        guard budget >= 0 else { return nil }

        var kindOrder: [PipeKind] = []
        for kind in kinds.shuffled(using: &generator) where !kindOrder.contains(kind) {
            kindOrder.append(kind)
        }

        for partner in remaining.subtracting([first]).sorted().shuffled(using: &generator) {
            for kind in kindOrder {
                // The pipe and its images under the required symmetries go in
                // together, so the tile stays symmetric at every step.
                let pipe = Pipe(kind, a: first, b: partner)
                var group = [pipe]
                for symmetry in symmetries {
                    let image = symmetry.apply(to: pipe, portsPerEdge: tile.portsPerEdge)
                    if !group.contains(image) { group.append(image) }
                }
                let used = group.flatMap { [$0.a, $0.b] }
                guard Set(used).count == used.count, Set(used).isSubset(of: remaining) else { continue }

                var next = tile
                var nextCoverage = coverage
                var fits = true
                for member in group {
                    if PlacementRules.error(adding: member, to: next, coverage: nextCoverage) != nil {
                        fits = false
                        break
                    }
                    next.pipes.append(member)
                    nextCoverage.add(member)
                }
                guard fits else { continue }

                if let finished = pair(
                    remaining.subtracting(used), into: next, coverage: nextCoverage,
                    symmetries: symmetries, kinds: kinds, budget: &budget, using: &generator
                ) {
                    return finished
                }
                if budget < 0 { return nil }
            }
        }
        return nil
    }
}
