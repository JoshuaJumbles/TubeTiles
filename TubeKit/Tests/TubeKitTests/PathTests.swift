import Testing
@testable import TubeKit

private func port(_ edge: Int, _ slot: Int) -> Port { Port(edge: edge, slot: slot) }

private func sealedMaze(seed: UInt64, symmetry: Symmetry = .none, radius: Int = 3) -> (Maze, MazeGenerator) {
    let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6))
    var random = SeededGenerator(seed: seed)
    var maze = Maze(portsPerEdge: 4, radius: radius)
    generator.fill(&maze, symmetry: symmetry, using: &random)
    return (maze, generator)
}

@Suite struct PathTracingTests {
    @Test func aLooseStrandIsFollowedBothWays() throws {
        let straight = try Tile(portsPerEdge: 3, pipes: [Pipe(.corner, a: port(0, 1), b: port(3, 1))])
        var maze = Maze(portsPerEdge: 3, radius: 2)
        // Placed out of order so the trace has to walk back from its start.
        for r in [0, 1, -1] {
            maze = try #require(maze.placing(PlacedTile(straight), at: HexCoord(q: 0, r: r)))
        }
        let paths = maze.paths
        #expect(paths.paths.count == 1)
        #expect(paths.loopCount == 0)
        let path = try #require(paths.paths.first)
        #expect(!path.isClosed)
        #expect(path.steps.map(\.coord.r) == [1, 0, -1] || path.steps.map(\.coord.r) == [-1, 0, 1])
        // Each step leaves through the edge the next one enters by.
        for (step, next) in zip(path.steps, path.steps.dropFirst()) {
            #expect(step.coord.neighbour(across: step.exit.edge) == next.coord)
            #expect(step.exit.neighbourPort(portsPerEdge: 3) == next.entry)
        }
    }

    @Test func twoUTurnsMakeALoop() throws {
        // A curve leaving and returning through the bottom edge, and its
        // half-turned twin below it.
        let turn = try Tile(portsPerEdge: 4, pipes: [Pipe(.bezier, a: port(3, 0), b: port(3, 3))])
        var maze = Maze(portsPerEdge: 4, radius: 1)
        maze = try #require(maze.placing(PlacedTile(turn), at: HexCoord(q: 0, r: -1)))
        maze = try #require(maze.placing(PlacedTile(turn, transform: TileTransform(turns: 3)), at: .origin))
        #expect(maze.isSealed)
        let paths = maze.paths
        #expect(paths.paths.count == 1)
        #expect(paths.paths[0].isClosed)
        #expect(paths.paths[0].steps.count == 2)
    }

    @Test func aSealedMazeIsAllLoopsAndEveryPipeIsOnOne() {
        for seed in 0..<4 {
            let (maze, _) = sealedMaze(seed: UInt64(seed))
            #expect(maze.isSealed)
            let paths = maze.paths
            #expect(paths.loopCount == paths.paths.count)
            let pipeCount = maze.cells.values.reduce(0) { $0 + $1.oriented.pipes.count }
            #expect(paths.paths.reduce(0) { $0 + $1.steps.count } == pipeCount)
            for (coord, placed) in maze.cells {
                for pipe in placed.oriented.pipes {
                    #expect(paths.index(of: pipe, at: coord) != nil)
                    #expect(paths.index(of: PortRef(coord: coord, port: pipe.b)) == paths.index(of: pipe, at: coord))
                }
            }
        }
    }
}

@Suite struct LoopMergerTests {
    @Test(arguments: Symmetry.allCases)
    func mergingOnlyEverReducesLoops(symmetry: Symmetry) {
        for seed in 0..<3 {
            var (maze, generator) = sealedMaze(seed: UInt64(seed), symmetry: symmetry)
            let merger = LoopMerger(generator: generator)
            var random = SeededGenerator(seed: 100 + UInt64(seed))
            var count = maze.paths.paths.count
            let before = maze.cells.mapValues(\.code)
            var merges = 0
            while merger.mergeStep(&maze, symmetry: symmetry, using: &random) {
                let now = maze.paths.paths.count
                #expect(now < count)
                count = now
                merges += 1
            }
            // Rewiring never changes a tile's edges, so the maze stays sealed.
            #expect(maze.isSealed)
            #expect(maze.cells.mapValues(\.code) == before)
            #expect(maze.paths.loopCount == count)
            for (coord, placed) in maze.cells {
                #expect(maze.fits(placed.code, at: coord))
                #expect(!CoverageMap(tile: placed.source).hasViolation)
            }
            #expect(merges >= 0)
        }
    }

    @Test func mostMazesReduceToASinglePath() {
        var single = 0
        for seed in 0..<8 {
            var (maze, generator) = sealedMaze(seed: UInt64(seed))
            var random = SeededGenerator(seed: UInt64(seed))
            LoopMerger(generator: generator).mergeAll(&maze, using: &random)
            if maze.paths.paths.count == 1 { single += 1 }
        }
        #expect(single >= 5)
    }

    /// Merging used to fall back to every kind when it had no rules to go
    /// by, which put angular pipes into mazes made of curves.
    @Test func mergingKeepsToTheAllowedKinds() {
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6, kinds: [.bezier]))
        var merged = 0
        for seed in 0..<6 {
            var random = SeededGenerator(seed: UInt64(seed))
            var maze = Maze(portsPerEdge: 4, radius: 3)
            generator.fill(&maze, symmetry: .none, using: &random)
            merged += LoopMerger(generator: generator).mergeAll(&maze, using: &random)
            for placed in maze.cells.values {
                #expect(placed.oriented.pipes.allSatisfy { $0.kind == .bezier })
            }
        }
        #expect(merged > 0)
    }

    @Test func withoutMadeUpTilesMergingOnlyUsesLibraryTiles() {
        var merged = 0
        for seed in 0..<6 {
            var (maze, maker) = sealedMaze(seed: UInt64(seed))
            var random = SeededGenerator(seed: 50 + UInt64(seed))
            // A library of the maze's own tiles and their rewired forms.
            var rewired = maze
            LoopMerger(generator: maker).mergeAll(&rewired, using: &random)
            let tiles = (Array(maze.cells.values) + Array(rewired.cells.values)).map(\.oriented)
            let library = MazeGenerator(tiles: tiles, synthesis: nil)

            let before = maze.paths.paths.count
            merged += LoopMerger(generator: library).mergeAll(&maze, using: &random)
            #expect(maze.paths.paths.count <= before)
            #expect(maze.isSealed)
            let known = library.options + library.goalOptions
            for placed in maze.cells.values {
                #expect(known.contains { $0.looksLike(placed) })
            }
        }
        #expect(merged > 0)
    }

    @Test func withoutMadeUpTilesOrVariantsNothingIsMerged() {
        var (maze, _) = sealedMaze(seed: 1)
        let before = maze
        var random = SeededGenerator(seed: 3)
        let merges = LoopMerger(generator: MazeGenerator(tiles: [], synthesis: nil)).mergeAll(&maze, using: &random)
        #expect(merges == 0)
        #expect(maze == before)
    }

    @Test func keptLoopsAreLeftAlone() throws {
        var (maze, generator) = sealedMaze(seed: 2)
        let paths = maze.paths
        try #require(paths.paths.count >= 3)
        let kept = try #require(paths.paths.min { $0.steps.count < $1.steps.count })
        let pin = try #require(kept.portRefs.first)

        var random = SeededGenerator(seed: 7)
        LoopMerger(generator: generator).mergeAll(&maze, keeping: [pin], using: &random)

        let after = maze.paths
        let index = try #require(after.index(of: pin))
        #expect(after.paths[index].portRefs == kept.portRefs)
        #expect(after.paths.count < paths.paths.count)
        #expect(after.paths.count >= 2)
    }
}
