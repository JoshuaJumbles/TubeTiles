import Testing
@testable import TubeKit

/// Pockets of empty cells that no tiles could ever fill, and the generator
/// keeping clear of them.
@Suite struct PocketTests {
    private func port(_ edge: Int, _ slot: Int) -> TubeKit.Port { TubeKit.Port(edge: edge, slot: slot) }

    @Test func aPocketWithAnOddNumberOfPipesPointingInCannotBeFilled() throws {
        // A three by three block of squares. The tile at the middle of the
        // top sends one pipe into the top left corner and one into the
        // centre.
        var maze = Maze(portsPerEdge: 3, radius: 1, tiling: .square)
        let corner = HexCoord(q: -1, r: -1)
        let top = try Tile(portsPerEdge: 3, shape: .square, pipes: [Pipe(.bezier, a: port(3, 1), b: port(2, 1))])
        maze = try #require(maze.placing(PlacedTile(top), at: HexCoord(q: 0, r: -1)))
        // The corner still joins the rest of the empty cells, which have
        // two pipes pointing in between them.
        #expect(!maze.hasUnfillablePocket(around: maze.coords))

        // A tile below the corner that sends nothing into it walls it off
        // with one pipe pointing in. Its own two pipes go elsewhere, so the
        // other empty cells are left with three.
        let left = try Tile(portsPerEdge: 3, shape: .square, pipes: [Pipe(.bezier, a: port(1, 1), b: port(2, 1))])
        maze = try #require(maze.placing(PlacedTile(left), at: HexCoord(q: -1, r: 0)))
        #expect(maze.hasUnfillablePocket(around: [corner]))
        #expect(maze.hasUnfillablePocket(around: [HexCoord(q: 1, r: 1)]))
        // Placed cells and cells outside the maze are not pockets.
        #expect(!maze.hasUnfillablePocket(around: [HexCoord(q: 0, r: -1), HexCoord(q: 5, r: 5)]))

        // A goal ends one pipe in a room, which is what the corner needs.
        maze.setGoals([corner])
        #expect(!maze.hasUnfillablePocket(around: [corner]))
    }

    @Test(arguments: Tiling.allCases)
    func growingAMazeNeverLeavesSuchAPocket(tiling: Tiling) {
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6))
        for symmetry in tiling.symmetries {
            var maze = Maze(portsPerEdge: 3, radius: 2, tiling: tiling)
            var random = SeededGenerator(seed: 3)
            for _ in 0..<400 {
                let step = generator.step(&maze, symmetry: symmetry, using: &random)
                let stranded = maze.hasUnfillablePocket(around: maze.coords, symmetry: symmetry)
                #expect(!stranded)
                if step == .sealed || stranded { break }
            }
        }
    }

    @Test(arguments: Tiling.allCases)
    func everySymmetrySeals(tiling: Tiling) {
        // Half turns on hexagons and triangles used to seal about half the
        // time: a band of empty cells right round the centre was left with
        // an odd number of pipes pointing into each half.
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6))
        let runs = 8
        for symmetry in tiling.symmetries {
            var sealed = 0
            for seed in 0..<runs {
                var maze = Maze(portsPerEdge: 3, radius: 2, tiling: tiling)
                var random = SeededGenerator(seed: UInt64(seed))
                if generator.fill(&maze, symmetry: symmetry, using: &random) { sealed += 1 }
            }
            #expect(sealed >= runs - 1, "\(tiling) with \(symmetry): \(sealed) of \(runs)")
        }
    }
}

/// Two pipes whose ends alternate round the tile have to cross an odd number
/// of times, and two whose ends do not, an even number. The weave depends on
/// every crossing being found.
@Suite struct CrossingCountTests {
    @Test func aCrossingExactlyOnAJointOfACurveIsFound() throws {
        // The curve passes through the straight pipe at one of the points
        // the curve itself is drawn through.
        let tile = try Tile(portsPerEdge: 4, shape: .square, pipes: [
            Pipe(.corner, a: TubeKit.Port(edge: 0, slot: 2), b: TubeKit.Port(edge: 2, slot: 1)),
            Pipe(.bezier, a: TubeKit.Port(edge: 0, slot: 1), b: TubeKit.Port(edge: 2, slot: 0)),
        ])
        #expect(tile.crossings().count == 1)
    }

    @Test(arguments: TileShape.allCases)
    func crossingsMatchTheOrderOfThePorts(shape: TileShape) {
        var random = SeededGenerator(seed: 17)
        var pairs = 0
        for ports in [3, 4] {
            for _ in 0..<150 {
                var tile = Tile(portsPerEdge: ports, shape: shape)
                tile.fillRandomly(kinds: [.bezier, .corner], using: &random)
                func place(_ port: TubeKit.Port) -> Int { port.edge * ports + port.slot }
                let crossings = tile.crossings()
                for i in tile.pipes.indices {
                    for j in tile.pipes.indices where j > i {
                        let (a, b) = (tile.pipes[i], tile.pipes[j])
                        let low = min(place(a.a), place(a.b))
                        let high = max(place(a.a), place(a.b))
                        let between = [place(b.a), place(b.b)].filter { $0 > low && $0 < high }.count
                        let found = crossings.filter { $0.first == a && $0.second == b }.count
                        #expect((found % 2 == 1) == (between == 1), "\(shape) \(a) \(b): \(found) crossings")
                        pairs += 1
                    }
                }
            }
        }
        #expect(pairs > 50)
    }
}
