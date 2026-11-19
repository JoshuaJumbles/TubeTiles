import Testing
@testable import TubeKit

/// Growing a maze from the tiles it already has, before reaching for new
/// ones.
@Suite struct ReuseTests {
    /// How many different tiles a maze is made of, counting a tile turned
    /// or flipped as the same tile.
    private func different(_ maze: Maze) -> Int {
        BuildSheet(maze: maze, flippedIsSame: true).entries.count
    }

    private func library(_ shape: TileShape, count: Int) -> [Tile] {
        var random = SeededGenerator(seed: 99)
        var tiles: [Tile] = []
        while tiles.count < count {
            var tile = Tile(portsPerEdge: 4, shape: shape)
            for _ in 0..<(1 + tiles.count % 4) { tile.addRandomPipe(kinds: [.bezier, .corner], using: &random) }
            if !tile.pipes.isEmpty { tiles.append(tile) }
        }
        return tiles
    }

    @Test(arguments: [Tiling.hexagonal, .square, .truncatedSquare, .trihexagonal])
    func aMazeGrownWithReuseHasFewerDifferentTiles(tiling: Tiling) {
        var plain = 0
        var reusing = 0
        var sealed = 0
        let runs = 6
        for seed in 0..<runs {
            for reuse in [false, true] {
                let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.5), prefersReuse: reuse)
                var maze = Maze(portsPerEdge: 4, radius: 3, tiling: tiling)
                var random = SeededGenerator(seed: UInt64(seed))
                let done = generator.fill(&maze, symmetry: .none, using: &random)
                if reuse {
                    reusing += different(maze)
                    if done { sealed += 1 }
                    for (coord, placed) in maze.cells {
                        #expect(placed.source.shape == tiling.shape(of: coord))
                        #expect(maze.fits(placed.code, at: coord))
                    }
                } else {
                    plain += different(maze)
                }
            }
        }
        // Well under: two thirds as many at the very most.
        #expect(reusing * 3 < plain * 2, "\(tiling): \(reusing) different tiles with reuse, \(plain) without")
        #expect(sealed >= runs - 1)
    }

    @Test func reuseFavoursTheLibraryTilesAlreadyInPlay() {
        let tiles = library(.hexagon, count: 40)
        var plain = 0
        var reusing = 0
        for seed in 0..<6 {
            for reuse in [false, true] {
                let generator = MazeGenerator(tiles: tiles, synthesis: .init(growth: 0.5), prefersReuse: reuse)
                var maze = Maze(portsPerEdge: 4, radius: 3)
                var random = SeededGenerator(seed: UInt64(seed))
                #expect(generator.fill(&maze, symmetry: .none, using: &random))
                if reuse { reusing += different(maze) } else { plain += different(maze) }
            }
        }
        #expect(reusing * 5 < plain * 4, "\(reusing) different tiles with reuse, \(plain) without")
    }

    @Test func aMadeUpTileIsUsedAgainAsTheSameTile() {
        // With no library every tile is made up. Reuse places the very same
        // tile again, so the maze's tiles share their origins.
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.5), prefersReuse: true)
        var maze = Maze(portsPerEdge: 4, radius: 3, tiling: .square)
        var random = SeededGenerator(seed: 4)
        #expect(generator.fill(&maze, symmetry: .none, using: &random))
        let origins = Set(maze.cells.values.map(\.source.id))
        #expect(origins.count * 2 < maze.cells.count)
        let allMadeUp = maze.cells.values.allSatisfy { $0.isGenerated }
        #expect(allMadeUp)
    }

    @Test(arguments: [Symmetry.mirror, .sixth])
    func reuseKeepsSymmetryAndGoals(symmetry: Symmetry) {
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6), prefersReuse: true)
        let tiling = Tiling.hexagonal
        var sealed = 0
        for seed in 0..<4 {
            var maze = Maze(portsPerEdge: 4, radius: 3)
            var random = SeededGenerator(seed: UInt64(seed))
            if generator.fill(&maze, symmetry: symmetry, using: &random) { sealed += 1 }
            for (coord, placed) in maze.cells {
                for move in tiling.images(of: coord, under: symmetry) {
                    let matches = maze.cells[move.cell]?.looksLike(placed.transformed(by: move.tile)) ?? false
                    #expect(matches)
                }
            }
        }
        #expect(sealed >= 3)

        // A goal still gets a tile with a dead end, and only the goal does.
        var maze = Maze(portsPerEdge: 4, radius: 3)
        maze.setGoals([.origin, HexCoord(q: 2, r: -1)])
        var random = SeededGenerator(seed: 2)
        if generator.fill(&maze, symmetry: .none, using: &random) {
            #expect(maze.paths.paths.filter { !$0.isClosed }.count == 1)
        }
        for (coord, placed) in maze.cells {
            #expect(placed.source.deadEnds.count == (maze.goals.contains(coord) ? 1 : 0))
        }
    }
}
