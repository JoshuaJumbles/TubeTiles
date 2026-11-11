/// Joins separate loops of a maze into fewer, longer ones.
///
/// Two loops that pass through the same tile can be merged by rewiring that
/// tile: the same ports, joined up differently. The tile's edges do not
/// change, so its neighbours are undisturbed.
public struct LoopMerger: Sendable {
    public var generator: MazeGenerator

    public init(generator: MazeGenerator) {
        self.generator = generator
    }

    /// Merges two loops somewhere in the maze. Returns false if no merge is
    /// possible, leaving the maze unchanged.
    ///
    /// - Parameter keeping: Pipe ends on loops that must be left exactly as
    ///   they are.
    public func mergeStep(
        _ maze: inout Maze,
        keeping pinned: Set<PortRef> = [],
        symmetry: Symmetry = .none,
        using generator: inout some RandomNumberGenerator
    ) -> Bool {
        let paths = maze.paths
        let kept = Set(pinned.compactMap { paths.index(of: $0) })
        let keptRefs = kept.map { paths.paths[$0].portRefs }

        /// Accepts a replacement only if it leaves fewer paths and every
        /// kept loop untouched.
        func improved(_ candidate: PlacedTile, at coord: HexCoord) -> Maze? {
            guard let next = maze.replacing(at: coord, with: candidate, symmetry: symmetry) else { return nil }
            let nextPaths = next.paths
            guard nextPaths.paths.count < paths.paths.count else { return nil }
            for refs in keptRefs {
                guard let any = refs.first, let index = nextPaths.index(of: any),
                      nextPaths.paths[index].portRefs == refs
                else { return nil }
            }
            return next
        }

        var kindOrder: [PipeKind] = []
        for kind in (self.generator.synthesis?.kinds ?? TileSynthesizer.defaultKinds) where !kindOrder.contains(kind) {
            kindOrder.append(kind)
        }

        for coord in maze.cells.keys.sorted().shuffled(using: &generator) {
            guard let placed = maze.cells[coord] else { continue }
            let pipes = placed.oriented.pipes

            // Pairs of pipes here that belong to different loops, neither kept.
            var pairs: [(Pipe, Pipe)] = []
            for (offset, first) in pipes.enumerated() {
                for second in pipes.dropFirst(offset + 1) {
                    // A dead end has no partner to swap, so it stays as it is.
                    guard !first.isDeadEnd, !second.isDeadEnd,
                          let a = paths.index(of: first, at: coord), let b = paths.index(of: second, at: coord),
                          a != b, !kept.contains(a), !kept.contains(b)
                    else { continue }
                    pairs.append((first, second))
                }
            }
            guard !pairs.isEmpty else { continue }

            // A library tile with the same edges is the first choice.
            let variants = (self.generator.options + self.generator.goalOptions).filter {
                $0.code == placed.code && !$0.looksLike(placed)
                    && Set($0.oriented.deadEnds) == Set(placed.oriented.deadEnds)
            }
            for variant in variants.shuffled(using: &generator) {
                if let next = improved(variant, at: coord) {
                    maze = next
                    return true
                }
            }

            // Otherwise swap partners between two pipes, leaving the rest of
            // the tile alone.
            for (first, second) in pairs.shuffled(using: &generator) {
                let rewirings = [
                    (first.a, second.a, first.b, second.b),
                    (first.a, second.b, first.b, second.a),
                ].shuffled(using: &generator)
                for (a1, a2, b1, b2) in rewirings {
                    let rest = Tile(
                        portsPerEdge: maze.portsPerEdge,
                        uncheckedPipes: pipes.filter { $0 != first && $0 != second }
                    )
                    // Keep the original pipe kinds if they still fit.
                    let firstKinds = [first.kind] + kindOrder.filter { $0 != first.kind }
                    let secondKinds = [second.kind] + kindOrder.filter { $0 != second.kind }
                    for kindA in firstKinds {
                        var withOne = rest
                        guard (try? withOne.add(Pipe(kindA, a: a1, b: a2))) != nil else { continue }
                        for kindB in secondKinds {
                            var tile = withOne
                            guard (try? tile.add(Pipe(kindB, a: b1, b: b2))) != nil else { continue }
                            if let next = improved(PlacedTile(tile, isGenerated: true), at: coord) {
                                maze = next
                                return true
                            }
                        }
                    }
                }
            }

            // Last resort: rebuild the whole tile on the same ports. A cell
            // the symmetry maps onto itself needs a tile that is symmetric
            // too, which swapping two pipes cannot give, so this is the only
            // route for those and gets more attempts.
            let fixing = symmetry.transforms.filter { $0 != .identity && coord.transformed(by: $0) == coord }
            let ends = placed.oriented.deadEnds
            guard ends.count <= 1, ends.isEmpty || fixing.isEmpty else { continue }
            for _ in 0..<(fixing.isEmpty ? 3 : 12) {
                guard let tile = TileSynthesizer.tile(
                    portsPerEdge: maze.portsPerEdge, ports: placed.oriented.occupiedPorts,
                    invariantUnder: fixing,
                    deadEnd: ends.first.map { ($0.a, $0.kind) },
                    kinds: self.generator.synthesis?.kinds ?? TileSynthesizer.defaultKinds, using: &generator
                ) else { continue }
                if let next = improved(PlacedTile(tile, isGenerated: true), at: coord) {
                    maze = next
                    return true
                }
            }
        }
        return false
    }

    /// Merges until nothing more can be joined. Returns how many merges
    /// were made.
    ///
    /// This always reaches a single loop when every loop shares a tile with
    /// another, except in mirror-symmetric mazes. There, each symmetric loop
    /// crosses the axis in exactly two places, and two such loops can only be
    /// joined where their crossings share a tile, so a few loops may remain.
    @discardableResult
    public func mergeAll(
        _ maze: inout Maze,
        keeping pinned: Set<PortRef> = [],
        symmetry: Symmetry = .none,
        using generator: inout some RandomNumberGenerator
    ) -> Int {
        var merges = 0
        while mergeStep(&maze, keeping: pinned, symmetry: symmetry, using: &generator) {
            merges += 1
        }
        return merges
    }
}
