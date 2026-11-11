import Testing
@testable import TubeKit

private func port(_ edge: Int, _ slot: Int) -> Port { Port(edge: edge, slot: slot) }

/// A varied library of sparse tiles, the kind a hand-built set has.
private func sampleTiles(portsPerEdge: Int, count: Int, seed: UInt64) -> [Tile] {
    var generator = SeededGenerator(seed: seed)
    return (0..<count).compactMap { _ in
        var tile = Tile(portsPerEdge: portsPerEdge)
        for _ in 0..<Int.random(in: 1...4, using: &generator) {
            tile.addRandomPipe(kinds: [.bezier, .bezier, .corner], using: &generator)
        }
        return tile.pipes.isEmpty ? nil : tile
    }
}

@Suite struct HexCoordTests {
    @Test func neighboursSitAcrossTheirEdge() {
        let cell = HexCoord(q: 2, r: -1)
        for edge in 0..<6 {
            let middle = (HexGeometry.corner(edge) + HexGeometry.corner(edge + 1)) * 0.5
            let expected = cell.center + middle * 2
            #expect(cell.neighbour(across: edge).center.distance(to: expected) < 1e-9)
            #expect(cell.neighbour(across: edge).neighbour(across: (edge + 3) % 6) == cell)
        }
    }

    @Test func transformsMatchGeometry() {
        let cells = Maze(portsPerEdge: 2, radius: 3).coords
        for transform in TileTransform.allCases {
            for cell in cells {
                let moved = cell.transformed(by: transform)
                #expect(moved.center.distance(to: transform.apply(to: cell.center)) < 1e-9)
                #expect(moved.ring == cell.ring)
            }
        }
    }

    @Test func regionsAreHexagons() {
        #expect(Maze(portsPerEdge: 2, radius: 0).coords == [.origin])
        for radius in 1...4 {
            let maze = Maze(portsPerEdge: 2, radius: radius)
            #expect(maze.coords.count == maze.cellCount)
        }
        #expect(Maze(portsPerEdge: 2, radius: 3).cellCount == 37)
    }
}

@Suite struct MazeTests {
    /// One straight pipe from the top edge to the bottom edge.
    private func straight() throws -> Tile {
        try Tile(portsPerEdge: 3, pipes: [Pipe(.corner, a: port(0, 1), b: port(3, 1))])
    }

    @Test func theOutlineIsSealed() throws {
        let maze = Maze(portsPerEdge: 3, radius: 1)
        let top = HexCoord(q: 0, r: -1)
        #expect(maze.requirement(at: top, edge: 0) == 0)
        #expect(maze.requirement(at: top, edge: 3) == nil)
        // A pipe pointing out of the region is refused.
        #expect(maze.placing(PlacedTile(try straight()), at: top) == nil)
        #expect(maze.placing(PlacedTile(try straight()), at: .origin) != nil)
    }

    @Test func neighboursMustMatch() throws {
        var maze = Maze(portsPerEdge: 3, radius: 2)
        maze = try #require(maze.placing(PlacedTile(try straight()), at: .origin))
        #expect(maze.openCells == [HexCoord(q: 0, r: -1), HexCoord(q: 0, r: 1)])
        #expect(!maze.isSealed)

        let below = HexCoord(q: 0, r: 1)
        #expect(maze.requirement(at: below, edge: 0) == 0b010)
        #expect(maze.placing(PlacedTile(try straight()), at: below) != nil)
        // Turned a sixth, the pipe no longer meets the one above.
        #expect(maze.placing(PlacedTile(try straight(), transform: TileTransform(turns: 1)), at: below) == nil)
        // An occupied cell cannot be placed on.
        #expect(maze.placing(PlacedTile(try straight()), at: .origin) == nil)
    }

    @Test func symmetryPlacesEveryImage() throws {
        let tile = try Tile(portsPerEdge: 3, pipes: [Pipe(.bezier, a: port(2, 0), b: port(4, 2))])
        let cell = HexCoord(q: 1, r: -2)
        for symmetry in Symmetry.allCases {
            let maze = Maze(portsPerEdge: 3, radius: 2)
            let next = try #require(maze.placing(PlacedTile(tile), at: cell, symmetry: symmetry))
            #expect(next.cells.count == symmetry.transforms.count)
            var removed = next
            removed.remove(at: cell, symmetry: symmetry)
            #expect(removed.cells.isEmpty)
        }
    }

    @Test func aCellOnTheAxisNeedsASymmetricTile() throws {
        let maze = Maze(portsPerEdge: 3, radius: 2)
        let lopsided = try Tile(portsPerEdge: 3, pipes: [Pipe(.bezier, a: port(1, 0), b: port(2, 2))])
        #expect(maze.placing(PlacedTile(lopsided), at: .origin, symmetry: .mirror) == nil)
        #expect(maze.placing(PlacedTile(try straight()), at: .origin, symmetry: .mirror) != nil)
        #expect(maze.placing(PlacedTile(try straight()), at: .origin, symmetry: .half) != nil)
        #expect(maze.placing(PlacedTile(try straight()), at: .origin, symmetry: .third) == nil)
    }
}

@Suite struct MazeGeneratorTests {
    @Test func optionsAreDistinctPlacements() throws {
        // A straight pipe through the middle looks the same after a half
        // turn or a flip, so it has three placements rather than twelve.
        let straight = try Tile(portsPerEdge: 3, pipes: [Pipe(.corner, a: port(0, 1), b: port(3, 1))])
        #expect(MazeGenerator(tiles: [straight]).options.count == 3)
        #expect(MazeGenerator(tiles: [Tile(portsPerEdge: 3)]).options.isEmpty)
    }

    /// Checks a finished or part-finished maze is internally consistent and
    /// has the symmetry it was grown with.
    private func expectValid(_ maze: Maze, symmetry: Symmetry) {
        for (coord, placed) in maze.cells {
            #expect(maze.fits(placed.code, at: coord))
            #expect(!CoverageMap(tile: placed.source).hasViolation)
            for transform in symmetry.transforms {
                let image = maze.cells[coord.transformed(by: transform)]
                #expect(image?.looksLike(placed.transformed(by: transform)) == true)
            }
        }
    }

    @Test(arguments: Symmetry.allCases)
    func fillsSealAndStaySymmetric(symmetry: Symmetry) {
        let generator = MazeGenerator(tiles: sampleTiles(portsPerEdge: 3, count: 40, seed: 5))
        for seed in 0..<4 {
            var random = SeededGenerator(seed: UInt64(seed))
            var maze = Maze(portsPerEdge: 3, radius: 2)
            #expect(generator.fill(&maze, symmetry: symmetry, using: &random), "seed \(seed)")
            #expect(maze.isSealed)
            #expect(maze.cells.count > 3)
            expectValid(maze, symmetry: symmetry)
        }
    }

    @Test func anEmptyLibraryStillGrowsAMaze() {
        var random = SeededGenerator(seed: 2)
        var maze = Maze(portsPerEdge: 4, radius: 2)
        #expect(MazeGenerator(tiles: []).fill(&maze, symmetry: .mirror, using: &random))
        let madeUp = maze.cells.values.filter { $0.isGenerated }.count
        #expect(madeUp == maze.cells.count)
        expectValid(maze, symmetry: .mirror)
    }

    @Test func libraryOnlyModeNeverMakesTilesUp() {
        let generator = MazeGenerator(tiles: sampleTiles(portsPerEdge: 3, count: 40, seed: 5), synthesis: nil)
        var random = SeededGenerator(seed: 3)
        var maze = Maze(portsPerEdge: 3, radius: 2)
        generator.fill(&maze, symmetry: .none, using: &random)
        let madeUp = maze.cells.values.filter { $0.isGenerated }.count
        #expect(madeUp == 0)
        expectValid(maze, symmetry: .none)
    }

    /// Growth controls how readily made-up tiles send out new pipes, so a
    /// maze grown with none is far sparser than one grown with plenty.
    @Test func growthControlsHowBusyTheMazeIs() {
        func pipeCount(growth: Double) -> Int {
            let generator = MazeGenerator(tiles: [], synthesis: .init(growth: growth))
            var random = SeededGenerator(seed: 6)
            var maze = Maze(portsPerEdge: 4, radius: 3)
            generator.fill(&maze, symmetry: .none, using: &random)
            return maze.cells.values.reduce(0) { $0 + $1.oriented.pipes.count }
        }
        let sparse = pipeCount(growth: 0)
        let busy = pipeCount(growth: 0.9)
        #expect(sparse > 0)
        #expect(busy > sparse * 2)
    }

    @Test func reportsWhenNothingCanStart() {
        var random = SeededGenerator(seed: 1)
        var maze = Maze(portsPerEdge: 3, radius: 2)
        let generator = MazeGenerator(tiles: [], synthesis: nil)
        #expect(generator.step(&maze, symmetry: .none, using: &random) == .stuck(.origin))
    }

    @Test func sameSeedGrowsTheSameMaze() {
        let generator = MazeGenerator(tiles: sampleTiles(portsPerEdge: 3, count: 30, seed: 9))
        var first = SeededGenerator(seed: 4)
        var second = SeededGenerator(seed: 4)
        var a = Maze(portsPerEdge: 3, radius: 2)
        var b = Maze(portsPerEdge: 3, radius: 2)
        generator.fill(&a, symmetry: .none, using: &first)
        generator.fill(&b, symmetry: .none, using: &second)
        #expect(a.cells.mapValues(\.oriented.pipes) == b.cells.mapValues(\.oriented.pipes))
    }
}

@Suite struct TileSynthesizerTests {
    @Test func usesExactlyTheGivenPorts() throws {
        var random = SeededGenerator(seed: 8)
        let ports = [port(0, 0), port(0, 3), port(2, 1), port(3, 2), port(4, 0), port(5, 3)]
        for _ in 0..<10 {
            let tile = try #require(TileSynthesizer.tile(portsPerEdge: 4, ports: ports, using: &random))
            #expect(tile.occupiedPorts == Set(ports))
            #expect(tile.pipes.count == 3)
            // Rebuilding through the checked initialiser proves it is legal.
            let rebuilt = try Tile(portsPerEdge: 4, pipes: tile.pipes)
            #expect(rebuilt.pipes == tile.pipes)
        }
    }

    @Test func refusesAnOddNumberOfPorts() {
        var random = SeededGenerator(seed: 8)
        #expect(TileSynthesizer.tile(portsPerEdge: 4, ports: [port(0, 0)], using: &random) == nil)
        #expect(TileSynthesizer.tile(portsPerEdge: 4, ports: [port(0, 0), port(0, 9)], using: &random) == nil)
    }

    @Test func givesUpWhenNoPairingIsLegal() {
        var random = SeededGenerator(seed: 8)
        // Two neighbouring ports on one edge: too tight for a curve, and
        // corners and rooms need two edges.
        #expect(TileSynthesizer.tile(portsPerEdge: 4, ports: [port(0, 0), port(0, 1)], using: &random) == nil)
    }

    @Test func canBuildMirrorSymmetricTiles() throws {
        var random = SeededGenerator(seed: 8)
        let mirror = TileTransform(mirrored: true)
        let half: [Port] = [port(1, 0), port(2, 2)]
        let ports = Set(half + half.map { mirror.apply(to: $0, portsPerEdge: 4) })
        let tile = try #require(TileSynthesizer.tile(
            portsPerEdge: 4, ports: ports, invariantUnder: [mirror], using: &random
        ))
        #expect(Set(tile.transformed(by: mirror).pipes) == Set(tile.pipes))
    }
}
