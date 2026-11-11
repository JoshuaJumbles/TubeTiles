extension Tile {
    /// Tries to add one random valid pipe. Returns it, or nil if none of the
    /// attempts fit.
    ///
    /// `kinds` may repeat entries to make some kinds more likely than others.
    /// Ports in `avoiding` are never used.
    @discardableResult
    public mutating func addRandomPipe(
        kinds: [PipeKind] = PipeKind.throughKinds,
        avoiding dead: Set<Port> = [],
        attempts: Int = 30,
        using generator: inout some RandomNumberGenerator
    ) -> Pipe? {
        let free = freePorts.filter { !dead.contains($0) }
        guard free.count >= 2, !kinds.isEmpty else { return nil }
        let coverage = CoverageMap(tile: self)
        for _ in 0..<attempts {
            let a = free.randomElement(using: &generator)!
            let b = free.randomElement(using: &generator)!
            let kind = kinds.randomElement(using: &generator)!
            let pipe = kind.isDeadEnd ? Pipe(kind, at: a) : Pipe(kind, a: a, b: b)
            if PlacementRules.error(adding: pipe, to: self, coverage: coverage) == nil {
                pipes.append(pipe)
                return pipe
            }
        }
        return nil
    }

    /// Adds random valid pipes until one fails to fit. Returns how many were added.
    @discardableResult
    public mutating func fillRandomly(
        kinds: [PipeKind] = PipeKind.throughKinds,
        avoiding dead: Set<Port> = [],
        using generator: inout some RandomNumberGenerator
    ) -> Int {
        var added = 0
        while addRandomPipe(kinds: kinds, avoiding: dead, using: &generator) != nil {
            added += 1
        }
        return added
    }
}
