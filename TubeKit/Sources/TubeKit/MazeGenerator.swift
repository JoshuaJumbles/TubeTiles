import Foundation

/// Grows a maze one cell at a time.
///
/// Each step fills the most constrained open cell. Library tiles are tried
/// first. If none matches the neighbours and synthesis is on, a tile is built
/// to fit. A tile is only placed if every cell it opens up can still be
/// filled, which avoids most dead ends; when a cell cannot be filled at all,
/// the tiles around it are taken out and the area regrows.
public struct MazeGenerator: Sendable {
    /// How tiles are made up when the library has nothing that fits.
    public struct Synthesis: Sendable, Hashable {
        /// Chance, per free edge, that a made-up tile sends new pipes across
        /// it. 0 only ever closes off what is open; higher values keep the
        /// maze spreading towards the outline.
        public var growth: Double
        /// Pipe kinds made-up tiles may use; repeats make a kind more likely.
        public var kinds: [PipeKind]
        /// Room sizes to try for a goal, in order.
        public var deadEndKinds: [PipeKind]
        /// Ports made-up tiles never open a pipe on. A pipe a neighbour
        /// already sends in is still met, whatever port it arrives at.
        public var deadPorts: Set<Port>

        public init(
            growth: Double = 0.5,
            kinds: [PipeKind] = TileSynthesizer.defaultKinds,
            deadEndKinds: [PipeKind] = PipeKind.deadEndKinds,
            deadPorts: Set<Port> = []
        ) {
            self.growth = growth
            self.kinds = kinds
            self.deadEndKinds = deadEndKinds
            self.deadPorts = deadPorts
        }

        /// The slots on an edge that new pipes may use.
        func liveSlots(onEdge edge: Int, portsPerEdge: Int) -> [Int] {
            (0..<portsPerEdge).filter { !deadPorts.contains(Port(edge: edge, slot: $0)) }
        }

        /// Made-up tiles that keep to a library's rules, so they look like
        /// they belong with its hand-made ones.
        ///
        /// A goal has to end in a room, so if the library allows no dead-end
        /// kind at all, every size is tried for goals anyway.
        public init(growth: Double = 0.5, following library: TileLibrary) {
            self.init(
                growth: growth,
                kinds: TileSynthesizer.kinds(allowing: library.allowedKinds),
                deadEndKinds: library.deadEndKinds.isEmpty ? PipeKind.deadEndKinds : library.deadEndKinds,
                deadPorts: library.deadPorts
            )
        }
    }

    /// Every distinct way of placing an ordinary library tile on one cell.
    public let options: [PlacedTile]
    /// Placements of library tiles that have exactly one dead end. These are
    /// only used on goal cells, so dead ends appear where they were asked
    /// for and nowhere else.
    public let goalOptions: [PlacedTile]
    /// Nil restricts the maze to library tiles only.
    public var synthesis: Synthesis?

    public init(tiles: [Tile], synthesis: Synthesis? = Synthesis()) {
        var seen: Set<Set<Pipe>> = []
        var options: [PlacedTile] = []
        var goalOptions: [PlacedTile] = []
        for tile in tiles where !tile.pipes.isEmpty {
            let ends = tile.deadEnds.count
            // Tiles with several dead ends would add path ends nobody asked
            // for, so they are left out.
            guard ends <= 1 else { continue }
            for transform in TileTransform.allCases {
                let placed = PlacedTile(tile, transform: transform)
                guard seen.insert(Set(placed.oriented.pipes)).inserted else { continue }
                if ends == 1 {
                    goalOptions.append(placed)
                } else {
                    options.append(placed)
                }
            }
        }
        self.options = options
        self.goalOptions = goalOptions
        self.synthesis = synthesis
    }

    public enum Step: Equatable, Sendable {
        /// A tile was placed here (and at its images).
        case placed(HexCoord)
        /// Nothing fitted here, so the tiles around it were taken out.
        case cleared(HexCoord)
        /// No pipe is left hanging: the maze is finished.
        case sealed
        /// Nothing could be done for this cell.
        case stuck(HexCoord)
    }

    // MARK: Choosing a tile

    /// Library options whose edges match what is already around `coord`.
    private func matching(_ maze: Maze, at coord: HexCoord) -> [PlacedTile] {
        let required = (0..<HexGeometry.edgeCount).map { maze.requirement(at: coord, edge: $0) }
        return (maze.goals.contains(coord) ? goalOptions : options).filter { option in
            for edge in 0..<HexGeometry.edgeCount {
                if let value = required[edge], value != option.code.values[edge] { return false }
            }
            return true
        }
    }

    /// The symmetry transforms, other than doing nothing, that map `coord`
    /// onto itself. A tile there must look the same under each of them.
    private func stabilizer(of coord: HexCoord, symmetry: Symmetry) -> [TileTransform] {
        symmetry.transforms.filter { $0 != .identity && coord.transformed(by: $0) == coord }
    }

    /// Builds a tile for `coord` that meets every neighbour, optionally
    /// opening new pipes across edges that are still free.
    private func synthesize(
        for maze: Maze,
        at coord: HexCoord,
        symmetry: Symmetry,
        using generator: inout some RandomNumberGenerator
    ) -> PlacedTile? {
        guard let synthesis else { return nil }
        if maze.goals.contains(coord) {
            return synthesizeGoal(for: maze, at: coord, using: &generator)
        }
        let count = maze.portsPerEdge
        let fixing = stabilizer(of: coord, symmetry: symmetry)

        var ports: Set<Port> = []
        var freeEdges: [Int] = []
        for edge in 0..<HexGeometry.edgeCount {
            if let value = maze.requirement(at: coord, edge: edge) {
                for slot in 0..<count where value & (1 << (count - 1 - slot)) != 0 {
                    ports.insert(Port(edge: edge, slot: slot))
                }
            } else {
                freeEdges.append(edge)
            }
        }

        /// A port together with its images, so additions keep the symmetry.
        func images(of port: Port) -> Set<Port> {
            Set([port] + fixing.map { $0.apply(to: port, portsPerEdge: count) })
        }
        var grown: [Port] = []
        func open(_ port: Port) {
            for image in images(of: port) where ports.insert(image).inserted {
                grown.append(image)
            }
        }

        for edge in freeEdges where Double.random(in: 0..<1, using: &generator) < synthesis.growth {
            let slots = (count >= 4 && Bool.random(using: &generator)) ? 2 : 1
            let live = synthesis.liveSlots(onEdge: edge, portsPerEdge: count)
            for slot in live.shuffled(using: &generator).prefix(slots) {
                open(Port(edge: edge, slot: slot))
            }
        }
        // A tile needs at least one pipe.
        var tries = 0
        while ports.count < 2, let edge = freeEdges.randomElement(using: &generator), tries < 8 {
            if let slot = synthesis.liveSlots(onEdge: edge, portsPerEdge: count).randomElement(using: &generator) {
                open(Port(edge: edge, slot: slot))
            }
            tries += 1
        }
        // Pipes have two ends, so the port count must be even.
        if ports.count % 2 == 1 {
            if fixing.isEmpty, let extra = grown.randomElement(using: &generator) {
                ports.remove(extra)
            } else if let spare = freeEdges.shuffled(using: &generator).lazy
                .flatMap({ edge in (0..<count).map { Port(edge: edge, slot: $0) } })
                .first(where: {
                    !ports.contains($0) && !synthesis.deadPorts.contains($0) && images(of: $0).count == 1
                }) {
                ports.insert(spare)
            } else {
                return nil
            }
        }
        guard !ports.isEmpty else { return nil }

        guard let tile = TileSynthesizer.tile(
            portsPerEdge: count, ports: ports, invariantUnder: fixing,
            kinds: synthesis.kinds, using: &generator
        ) else { return nil }
        return PlacedTile(tile, isGenerated: true)
    }

    /// Builds a tile with one dead end for a goal cell.
    ///
    /// With nothing around it yet, the tile is a single pipe into the biggest
    /// room that fits, which makes the goal a centrepiece. If neighbours
    /// already point pipes in, those are joined up around a smaller room.
    private func synthesizeGoal(
        for maze: Maze,
        at coord: HexCoord,
        using generator: inout some RandomNumberGenerator
    ) -> PlacedTile? {
        guard let synthesis else { return nil }
        let count = maze.portsPerEdge
        var ports: Set<Port> = []
        var freeEdges: [Int] = []
        for edge in 0..<HexGeometry.edgeCount {
            if let value = maze.requirement(at: coord, edge: edge) {
                for slot in 0..<count where value & (1 << (count - 1 - slot)) != 0 {
                    ports.insert(Port(edge: edge, slot: slot))
                }
            } else {
                freeEdges.append(edge)
            }
        }
        // One port ends in the room and the rest pair off, so the total has
        // to be odd. Add one on a free edge if it is not, as near the middle
        // of the edge as possible so a large room has space.
        if ports.count % 2 == 0 {
            let centre = Double(count - 1) / 2
            let choices: [Port] = freeEdges.shuffled(using: &generator).compactMap { edge in
                // The live slot nearest mid-edge, either side at random when
                // two are equally near.
                let live = synthesis.liveSlots(onEdge: edge, portsPerEdge: count).shuffled(using: &generator)
                return live.min { abs(Double($0) - centre) < abs(Double($1) - centre) }
                    .map { Port(edge: edge, slot: $0) }
            }
            guard let port = choices.first else { return nil }
            ports.insert(port)
        }

        for kind in synthesis.deadEndKinds {
            for port in ports.sorted().shuffled(using: &generator) {
                if let tile = TileSynthesizer.tile(
                    portsPerEdge: count, ports: ports, deadEnd: (port, kind),
                    kinds: synthesis.kinds, using: &generator
                ) {
                    return PlacedTile(tile, isGenerated: true)
                }
            }
        }
        return nil
    }

    /// Whether some tile could still go at `coord`.
    private func canFill(
        _ maze: Maze,
        at coord: HexCoord,
        symmetry: Symmetry,
        using generator: inout some RandomNumberGenerator
    ) -> Bool {
        if matching(maze, at: coord).contains(where: { maze.placing($0, at: coord, symmetry: symmetry) != nil }) {
            return true
        }
        guard synthesis != nil else { return false }
        if !stabilizer(of: coord, symmetry: symmetry).isEmpty {
            // Symmetric tiles are hard to build, so actually try.
            guard let made = synthesize(for: maze, at: coord, symmetry: symmetry, using: &generator) else {
                return false
            }
            return maze.placing(made, at: coord, symmetry: symmetry) != nil
        }
        // Otherwise a tile can almost always be built unless the cell is
        // boxed in with the wrong number of pipe ends: even for an ordinary
        // tile, odd for a goal, whose dead end uses one port on its own.
        var fixedPorts = 0
        var hasFreeEdge = false
        for edge in 0..<HexGeometry.edgeCount {
            if let value = maze.requirement(at: coord, edge: edge) {
                fixedPorts += value.nonzeroBitCount
            } else {
                hasFreeEdge = true
            }
        }
        return hasFreeEdge || fixedPorts % 2 == (maze.goals.contains(coord) ? 1 : 0)
    }

    /// Whether placing at `coord` left any neighbouring open cell unfillable.
    private func strandsNeighbour(
        _ next: Maze,
        placedAt coord: HexCoord,
        symmetry: Symmetry,
        using generator: inout some RandomNumberGenerator
    ) -> Bool {
        let open = Set(next.openCells)
        let touched = Set(next.images(of: coord, symmetry: symmetry).flatMap { target in
            (0..<HexGeometry.edgeCount).map { target.neighbour(across: $0) }
        }).intersection(open).sorted()
        for cell in touched where !canFill(next, at: cell, symmetry: symmetry, using: &generator) {
            return true
        }
        return false
    }

    /// The maze with a tile placed at `coord`, or nil if nothing fits there
    /// without stranding a neighbouring cell.
    public func placingRandomTile(
        in maze: Maze,
        at coord: HexCoord,
        symmetry: Symmetry,
        using generator: inout some RandomNumberGenerator
    ) -> Maze? {
        guard maze.contains(coord), maze.cells[coord] == nil else { return nil }

        for option in matching(maze, at: coord).shuffled(using: &generator) {
            guard let next = maze.placing(option, at: coord, symmetry: symmetry) else { continue }
            if !strandsNeighbour(next, placedAt: coord, symmetry: symmetry, using: &generator) {
                return next
            }
        }
        guard synthesis != nil else { return nil }
        for _ in 0..<6 {
            guard let made = synthesize(for: maze, at: coord, symmetry: symmetry, using: &generator),
                  let next = maze.placing(made, at: coord, symmetry: symmetry)
            else { continue }
            if !strandsNeighbour(next, placedAt: coord, symmetry: symmetry, using: &generator) {
                return next
            }
        }
        return nil
    }

    // MARK: Growing

    /// Makes one move towards a sealed maze.
    public func step(
        _ maze: inout Maze,
        symmetry: Symmetry,
        using generator: inout some RandomNumberGenerator
    ) -> Step {
        // Every path has two ends, so an odd number of openings and goals
        // can never be satisfied.
        guard maze.endCount % 2 == 0 else { return .stuck(.origin) }

        // Goals go in first, while there is room around them for a large
        // room, and the rest of the maze grows out to meet them.
        let pendingGoal = maze.goals.sorted().first { maze.cells[$0] == nil }

        if pendingGoal == nil, maze.cells.isEmpty {
            // Start at the centre if a tile can sit there under this
            // symmetry, otherwise as close to it as possible.
            let starts = maze.coords.sorted { $0.ring != $1.ring ? $0.ring < $1.ring : $0 < $1 }
            for start in starts.prefix(7) {
                if let next = placingRandomTile(in: maze, at: start, symmetry: symmetry, using: &generator) {
                    maze = next
                    return .placed(start)
                }
            }
            return .stuck(.origin)
        }

        let target: HexCoord
        if let pendingGoal {
            target = pendingGoal
        } else {
            let open = maze.openCells
            guard !open.isEmpty else { return .sealed }
            // Fill the cell with the most fixed edges first: it has the
            // fewest choices, so it is the one most likely to fail if left
            // for later.
            func fixedEdges(_ coord: HexCoord) -> Int {
                (0..<HexGeometry.edgeCount).filter { maze.requirement(at: coord, edge: $0) != nil }.count
            }
            let most = open.map(fixedEdges).max() ?? 0
            target = open.filter { fixedEdges($0) == most }.randomElement(using: &generator)!
        }

        if let next = placingRandomTile(in: maze, at: target, symmetry: symmetry, using: &generator) {
            maze = next
            return .placed(target)
        }
        // Openings and goals rarely respect the symmetry: an entrance on one
        // side has no twin on the other. Once a maze has any, symmetry is
        // kept where a symmetric placement works and dropped, cell by cell,
        // where not.
        if symmetry != .none, maze.endCount > 0,
           let next = placingRandomTile(in: maze, at: target, symmetry: .none, using: &generator) {
            maze = next
            return .placed(target)
        }

        // Nothing fits. Clear the tiles around the cell so the area can
        // regrow differently; taking out just one tends to rebuild the same
        // impossible corner.
        var neighbours = (0..<HexGeometry.edgeCount)
            .map { target.neighbour(across: $0) }
            .filter { maze.cells[$0] != nil }
        // A goal placed early has the biggest room it will ever get, so
        // leave it standing unless it is the only thing in the way.
        let ordinary = neighbours.filter { !maze.goals.contains($0) }
        if !ordinary.isEmpty { neighbours = ordinary }
        guard !neighbours.isEmpty else { return .stuck(target) }
        for neighbour in neighbours {
            maze.remove(at: neighbour, symmetry: symmetry)
        }
        return .cleared(target)
    }

    /// Steps until the maze is sealed or `maxSteps` runs out. Returns whether
    /// it sealed.
    @discardableResult
    public func fill(
        _ maze: inout Maze,
        symmetry: Symmetry,
        maxSteps: Int? = nil,
        using generator: inout some RandomNumberGenerator
    ) -> Bool {
        for _ in 0..<(maxSteps ?? maze.cellCount * 30) {
            switch step(&maze, symmetry: symmetry, using: &generator) {
            case .sealed: return true
            case .stuck: return false
            case .placed, .cleared: continue
            }
        }
        return maze.isSealed
    }
}
