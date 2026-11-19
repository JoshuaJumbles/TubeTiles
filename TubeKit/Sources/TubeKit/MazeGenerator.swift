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

    /// Every distinct way of placing an ordinary library tile on a cell of
    /// its shape.
    public let options: [PlacedTile]
    /// Placements of library tiles that have exactly one dead end. These are
    /// only used on goal cells, so dead ends appear where they were asked
    /// for and nowhere else.
    public let goalOptions: [PlacedTile]
    /// The same placements by the shape of cell they go in, so a cell is
    /// only ever offered tiles of its own shape.
    private let optionsByShape: [TileShape: [PlacedTile]]
    private let goalOptionsByShape: [TileShape: [PlacedTile]]
    /// Nil restricts the maze to library tiles only.
    public var synthesis: Synthesis?

    public init(tiles: [Tile], synthesis: Synthesis? = Synthesis()) {
        // Two shapes can have pipes between the same ports, so what has
        // been seen is kept by shape.
        var seen: [TileShape: Set<Set<Pipe>>] = [:]
        var options: [PlacedTile] = []
        var goalOptions: [PlacedTile] = []
        for tile in tiles where !tile.pipes.isEmpty {
            let ends = tile.deadEnds.count
            // Tiles with several dead ends would add path ends nobody asked
            // for, so they are left out.
            guard ends <= 1 else { continue }
            for transform in tile.shape.transforms {
                let placed = PlacedTile(tile, transform: transform)
                guard seen[tile.shape, default: []].insert(Set(placed.oriented.pipes)).inserted else { continue }
                if ends == 1 {
                    goalOptions.append(placed)
                } else {
                    options.append(placed)
                }
            }
        }
        self.options = options
        self.goalOptions = goalOptions
        optionsByShape = Dictionary(grouping: options) { $0.source.shape }
        goalOptionsByShape = Dictionary(grouping: goalOptions) { $0.source.shape }
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
        let edges = maze.edges(at: coord)
        let required = edges.map { maze.requirement(at: coord, edge: $0) }
        let allowed = edges.map { maze.allowedValue(at: coord, edge: $0) }
        let shape = maze.tiling.shape(of: coord)
        let candidates = (maze.goals.contains(coord) ? goalOptionsByShape : optionsByShape)[shape] ?? []
        return candidates.filter { option in
            for edge in edges {
                if let value = required[edge], value != option.code.values[edge] { return false }
                if option.code.values[edge] & ~allowed[edge] != 0 { return false }
            }
            return true
        }
    }

    /// The slots on a free edge of `coord` that a made-up tile may open a
    /// pipe on: live in the library's rules and inside the maze's mask.
    private func openSlots(_ maze: Maze, at coord: HexCoord, edge: Int) -> [Int] {
        guard let synthesis else { return [] }
        let count = maze.portsPerEdge
        let allowed = maze.allowedValue(at: coord, edge: edge)
        return synthesis.liveSlots(onEdge: edge, portsPerEdge: count).filter {
            allowed & (1 << (count - 1 - $0)) != 0
        }
    }

    /// The test a made-up pipe has to pass to stay inside the maze's mask,
    /// or nil where the cell is clear of its edge.
    private func insideMask(_ maze: Maze, at coord: HexCoord) -> ((Pipe) -> Bool)? {
        maze.isOnBorder(coord) ? { maze.staysInside($0, at: coord) } : nil
    }

    /// The symmetry transforms, other than doing nothing, that map `coord`
    /// onto itself. A tile there must look the same under each of them.
    private func stabilizer(_ maze: Maze, of coord: HexCoord, symmetry: Symmetry) -> [TileTransform] {
        maze.tiling.stabilizer(of: coord, symmetry: symmetry)
    }

    /// The pockets of empty cells that the free edges of `coord` lead into,
    /// and whether each needs an odd number of pipes from this cell to be
    /// fillable later (see `Maze.hasUnfillablePocket`). Several edges can
    /// lead into one pocket.
    ///
    /// Only small pockets that this cell alone borders are listed. A large
    /// one has room to put things right, and one shared with an image of
    /// the cell gets pipes from both; the check after placing covers those.
    private func pockets(
        _ maze: Maze, at coord: HexCoord, freeEdges: [Int], symmetry: Symmetry
    ) -> [(edges: [Int], odd: Bool)] {
        let blocked = Set(maze.images(of: coord, symmetry: symmetry))
        let limit = 24
        var result: [(edges: [Int], odd: Bool)] = []
        var owner: [HexCoord: Int] = [:]
        for edge in freeEdges where maze.allowedValue(at: coord, edge: edge) != 0 {
            let start = maze.tiling.neighbour(of: coord, across: edge).cell
            if let index = owner[start] {
                if index >= 0 { result[index].edges.append(edge) }
                continue
            }
            var ends = 0
            var known = true
            var members = [start]
            var frontier = [start]
            var seen: Set<HexCoord> = [start]
            while let cell = frontier.popLast() {
                if maze.goals.contains(cell) { ends += 1 }
                for side in maze.edges(at: cell) {
                    let next = maze.tiling.neighbour(of: cell, across: side).cell
                    if next == coord { continue }
                    if blocked.contains(next) {
                        known = false
                        continue
                    }
                    if let required = maze.requirement(at: cell, edge: side) {
                        ends += required.nonzeroBitCount
                    } else if maze.allowedValue(at: cell, edge: side) != 0, seen.insert(next).inserted {
                        members.append(next)
                        frontier.append(next)
                    }
                }
                if members.count > limit {
                    known = false
                    break
                }
            }
            let index = known ? result.count : -1
            for member in members { owner[member] = index }
            if known { result.append(([edge], ends % 2 == 1)) }
        }
        return result
    }

    /// Builds a tile for `coord` that meets every neighbour, optionally
    /// opening new pipes across edges that are still free. An eager tile
    /// settles an odd count by opening one more pipe, never one fewer, so
    /// that it keeps the maze going.
    private func synthesize(
        for maze: Maze,
        at coord: HexCoord,
        symmetry: Symmetry,
        growth: Double? = nil,
        eager: Bool = false,
        using generator: inout some RandomNumberGenerator
    ) -> PlacedTile? {
        guard let synthesis else { return nil }
        if maze.goals.contains(coord) {
            return synthesizeGoal(for: maze, at: coord, using: &generator)
        }
        let growth = growth ?? synthesis.growth
        let count = maze.portsPerEdge
        let fixing = stabilizer(maze, of: coord, symmetry: symmetry)

        var ports: Set<Port> = []
        var freeEdges: [Int] = []
        for edge in maze.edges(at: coord) {
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

        for edge in freeEdges where Double.random(in: 0..<1, using: &generator) < growth {
            let slots = (count >= 4 && Bool.random(using: &generator)) ? 2 : 1
            let live = openSlots(maze, at: coord, edge: edge)
            for slot in live.shuffled(using: &generator).prefix(slots) {
                open(Port(edge: edge, slot: slot))
            }
        }
        // A tile needs at least one pipe.
        var tries = 0
        while ports.count < 2, let edge = freeEdges.randomElement(using: &generator), tries < 8 {
            if let slot = openSlots(maze, at: coord, edge: edge).randomElement(using: &generator) {
                open(Port(edge: edge, slot: slot))
            }
            tries += 1
        }
        // Each pocket of empty cells beyond a free edge has to be sent an
        // odd or an even number of pipes, or nothing will ever fill it.
        var settled: Set<Int> = []
        if fixing.isEmpty {
            for pocket in pockets(maze, at: coord, freeEdges: freeEdges, symmetry: symmetry) {
                settled.formUnion(pocket.edges)
                let sent = ports.filter { pocket.edges.contains($0.edge) }
                guard (sent.count % 2 == 1) != pocket.odd else { continue }
                let spare = pocket.edges.flatMap { edge in
                    openSlots(maze, at: coord, edge: edge).map { Port(edge: edge, slot: $0) }
                }.filter { !ports.contains($0) }
                if let extra = spare.randomElement(using: &generator), sent.isEmpty || eager || Bool.random(using: &generator) {
                    ports.insert(extra)
                    grown.append(extra)
                } else if let extra = sent.sorted().randomElement(using: &generator) {
                    ports.remove(extra)
                    grown.removeAll { $0 == extra }
                } else if let extra = spare.randomElement(using: &generator) {
                    ports.insert(extra)
                    grown.append(extra)
                } else {
                    return nil
                }
            }
        }
        // Pipes have two ends, so the port count must be even. Ports
        // already counted out for a pocket are left alone if possible.
        if ports.count % 2 == 1 {
            let loose = grown.filter { !settled.contains($0.edge) }
            let more = eager && fixing.isEmpty
                ? freeEdges.filter { !settled.contains($0) }.flatMap { edge in
                    openSlots(maze, at: coord, edge: edge).map { Port(edge: edge, slot: $0) }
                }.filter { !ports.contains($0) }.randomElement(using: &generator)
                : nil
            if let more {
                ports.insert(more)
            } else if fixing.isEmpty, let extra = (loose.isEmpty ? grown : loose).randomElement(using: &generator) {
                ports.remove(extra)
            } else if let spare = freeEdges.shuffled(using: &generator).lazy
                .flatMap({ edge in self.openSlots(maze, at: coord, edge: edge).map { Port(edge: edge, slot: $0) } })
                .first(where: { !ports.contains($0) && images(of: $0).count == 1 }) {
                ports.insert(spare)
            } else {
                return nil
            }
        }
        guard !ports.isEmpty else { return nil }

        guard let tile = TileSynthesizer.tile(
            portsPerEdge: count, gauge: maze.gauge, shape: maze.tiling.shape(of: coord), ports: ports,
            invariantUnder: fixing,
            kinds: synthesis.kinds, where: insideMask(maze, at: coord), using: &generator
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
        for edge in maze.edges(at: coord) {
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
                let live = openSlots(maze, at: coord, edge: edge).shuffled(using: &generator)
                return live.min { abs(Double($0) - centre) < abs(Double($1) - centre) }
                    .map { Port(edge: edge, slot: $0) }
            }
            guard let port = choices.first else { return nil }
            ports.insert(port)
        }

        for kind in synthesis.deadEndKinds {
            for port in ports.sorted().shuffled(using: &generator) {
                if let tile = TileSynthesizer.tile(
                    portsPerEdge: count, gauge: maze.gauge, shape: maze.tiling.shape(of: coord), ports: ports,
                    deadEnd: (port, kind),
                    kinds: synthesis.kinds, where: insideMask(maze, at: coord), using: &generator
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
        if !stabilizer(maze, of: coord, symmetry: symmetry).isEmpty || maze.isOnBorder(coord) {
            // Symmetric tiles are hard to build, and so are tiles at the
            // edge of a mask, so actually try: first only closing off what
            // points in, which is the easiest tile to make, then opening new
            // pipes as well in case the count of ends was the trouble.
            for growth in [0, 0, nil, nil] as [Double?] {
                if let made = synthesize(for: maze, at: coord, symmetry: symmetry, growth: growth, using: &generator),
                   maze.placing(made, at: coord, symmetry: symmetry) != nil {
                    return true
                }
            }
            return false
        }
        // Otherwise a tile can almost always be built unless the cell is
        // boxed in with the wrong number of pipe ends: even for an ordinary
        // tile, odd for a goal, whose dead end uses one port on its own.
        var fixedPorts = 0
        var hasFreeEdge = false
        for edge in maze.edges(at: coord) {
            if let value = maze.requirement(at: coord, edge: edge) {
                fixedPorts += value.nonzeroBitCount
            } else {
                hasFreeEdge = true
            }
        }
        if hasFreeEdge { return true }
        guard fixedPorts % 2 == (maze.goals.contains(coord) ? 1 : 0) else { return false }
        // Boxed in on every side with the right number of ends. That is
        // still no promise: two pipes arriving side by side on one edge
        // with nothing else to join may have no legal way to meet. Only
        // making the tile tells, and with nothing to choose it is quick.
        for _ in 0..<2 {
            if let made = synthesize(for: maze, at: coord, symmetry: symmetry, growth: 0, using: &generator),
               maze.placing(made, at: coord, symmetry: symmetry) != nil {
                return true
            }
        }
        return false
    }

    /// Whether placing at `coord` left any neighbouring open cell unfillable.
    private func strandsNeighbour(
        _ next: Maze,
        placedAt coord: HexCoord,
        symmetry: Symmetry,
        using generator: inout some RandomNumberGenerator
    ) -> Bool {
        let open = Set(next.openCells)
        let around = Set(next.images(of: coord, symmetry: symmetry).flatMap { target in
            next.edges(at: target).map { next.tiling.neighbour(of: target, across: $0).cell }
        })
        // A tile that walls off empty cells with an odd number of pipes
        // pointing in has made something no later tile can put right.
        let empty = around.filter { next.contains($0) && next.cells[$0] == nil }
        if next.hasUnfillablePocket(around: empty.sorted(), symmetry: symmetry) { return true }
        let touched = around.intersection(open).sorted()
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

        // Growth is also how much of the space the maze should fill before
        // it closes up. Until then a tile that would leave no pipe hanging
        // is kept back, and used only if nothing else fits.
        let hasRoom = synthesis.map { Double(maze.cells.count) < $0.growth * Double(maze.cellCount) } ?? false
        var closing: Maze?

        for option in matching(maze, at: coord).shuffled(using: &generator) {
            guard let next = maze.placing(option, at: coord, symmetry: symmetry) else { continue }
            if !strandsNeighbour(next, placedAt: coord, symmetry: symmetry, using: &generator) {
                guard hasRoom, next.openCells.isEmpty else { return next }
                closing = closing ?? next
            }
        }
        guard synthesis != nil else { return closing }
        for attempt in 0..<6 {
            // If the first few made-up tiles would all close the maze, the
            // rest open a pipe on every edge they can.
            let pressing = closing != nil && attempt > 1
            guard let made = synthesize(
                for: maze, at: coord, symmetry: symmetry, growth: pressing ? 1 : nil, eager: pressing,
                using: &generator
            ),
                  let next = maze.placing(made, at: coord, symmetry: symmetry)
            else { continue }
            if !strandsNeighbour(next, placedAt: coord, symmetry: symmetry, using: &generator) {
                guard hasRoom, next.openCells.isEmpty else { return next }
                closing = closing ?? next
            }
        }
        return closing
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
            let ring = maze.tiling.ring
            let starts = maze.coords.sorted { ring($0) != ring($1) ? ring($0) < ring($1) : $0 < $1 }
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
                maze.edges(at: coord).filter { maze.requirement(at: coord, edge: $0) != nil }.count
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
        // A mask is the same: few are symmetric about the centre of the grid.
        if symmetry != .none, maze.endCount > 0 || maze.mask != nil,
           let next = placingRandomTile(in: maze, at: target, symmetry: .none, using: &generator) {
            maze = next
            return .placed(target)
        }

        // Nothing fits. Clear the tiles around the cell so the area can
        // regrow differently; taking out just one tends to rebuild the same
        // impossible corner.
        var neighbours = maze.edges(at: target)
            .map { maze.tiling.neighbour(of: target, across: $0).cell }
            .filter { maze.cells[$0] != nil }
        // A goal placed early has the biggest room it will ever get, so
        // leave it standing unless it is the only thing in the way.
        let ordinary = neighbours.filter { !maze.goals.contains($0) }
        if !ordinary.isEmpty { neighbours = ordinary }
        guard !neighbours.isEmpty else { return .stuck(target) }
        // Sometimes the trouble is one step further out: the tiles next to
        // the cell are themselves pinned by their neighbours into sending an
        // odd number of pipes into a pocket that needs an even one, and they
        // regrow the same way however often they are cleared. So now and
        // then, take out the tiles around those as well.
        if Double.random(in: 0..<1, using: &generator) < 0.3 {
            let wider = Set(neighbours.flatMap { near in
                maze.edges(at: near).map { maze.tiling.neighbour(of: near, across: $0).cell }
            }).filter { maze.cells[$0] != nil && !maze.goals.contains($0) }
            neighbours = Array(Set(neighbours).union(wider)).sorted()
        }
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
