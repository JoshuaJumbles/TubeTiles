import Foundation
import Testing
@testable import TubeKit

private let thin = PipeGauge(width: 0.35, wall: 0.2)
private let thick = PipeGauge(width: 0.95, wall: 0.3)

private func filledTiles(gauge: PipeGauge, count: Int, seed: UInt64) -> [Tile] {
    var random = SeededGenerator(seed: seed)
    return (0..<count).map { _ in
        var tile = Tile(portsPerEdge: 5, gauge: gauge)
        tile.fillRandomly(kinds: [.bezier, .bezier, .corner], avoiding: [], using: &random)
        return tile
    }
}

@Suite struct GaugeTests {
    @Test func sizesFollowTheGauge() {
        let standard = TileStyle(portsPerEdge: 4)
        #expect(standard.gauge == .standard)
        #expect(abs(standard.pipeWidth - 0.175) < 1e-9)
        #expect(abs(standard.wallThickness - 0.035) < 1e-9)
        let wide = TileStyle(portsPerEdge: 4, gauge: thick)
        #expect(wide.pipeWidth > standard.pipeWidth)
        #expect(wide.clearanceWidth > standard.clearanceWidth)
        #expect(abs(wide.wallThickness - wide.pipeWidth * 0.3) < 1e-9)
        // Out-of-range values are pulled back in.
        #expect(PipeGauge(width: 5, wall: -1) == PipeGauge(width: 0.95, wall: 0.06))
    }

    @Test func thickerPipesLeaveLessRoom() {
        let roomy = filledTiles(gauge: thin, count: 20, seed: 3)
        let tight = filledTiles(gauge: thick, count: 20, seed: 3)
        let thinPipes = roomy.reduce(0) { $0 + $1.pipes.count }
        let thickPipes = tight.reduce(0) { $0 + $1.pipes.count }
        #expect(thinPipes > thickPipes)
        // Each is legal at the thickness it was made at.
        #expect(roomy.allSatisfy { !CoverageMap(tile: $0).hasViolation })
        #expect(tight.allSatisfy { !CoverageMap(tile: $0).hasViolation })
        // Tiles packed with thin pipes mostly do not survive being thickened.
        #expect(roomy.filter { CoverageMap(tile: $0.gauged(thick)).hasViolation }.count > 10)
    }

    @Test func aLibrarySetsTheGaugeOfItsTiles() throws {
        var library = TileLibrary(name: "Test", portsPerEdge: 5)
        #expect(library.gauge == .standard)
        for tile in filledTiles(gauge: thin, count: 12, seed: 8) { library.save(tile) }
        // Saving brings a tile to the library's thickness.
        #expect(library.tiles.allSatisfy { $0.gauge == .standard })

        let crowded = library.crowdedTileCount(at: thick)
        #expect(crowded > 0)
        #expect(library.crowdedTileCount(at: thin) == 0)

        library.setGauge(thick)
        #expect(library.gauge == thick)
        #expect(library.tiles.count == 12)
        #expect(library.tiles.allSatisfy { $0.gauge == thick })
        #expect(library.duplicated(named: "Copy").gauge == thick)

        let loaded = try JSONDecoder().decode(TileLibrary.self, from: JSONEncoder().encode(library))
        #expect(loaded == library)
    }

    @Test func oldFilesLoadAtTheStandardGauge() throws {
        let tile = try Tile(portsPerEdge: 3, pipes: [Pipe(.bezier, a: Port(edge: 0, slot: 1), b: Port(edge: 3, slot: 1))])
        let data = try JSONEncoder().encode(tile)
        // A standard tile is written exactly as it was before gauges.
        #expect(!String(decoding: data, as: UTF8.self).contains("gauge"))
        #expect(try JSONDecoder().decode(Tile.self, from: data) == tile)

        let library = TileLibrary(name: "Old", portsPerEdge: 3)
        let libraryData = try JSONEncoder().encode(library)
        #expect(!String(decoding: libraryData, as: UTF8.self).contains("gauge"))
        let maze = Maze(portsPerEdge: 3, radius: 2)
        #expect(!String(decoding: try JSONEncoder().encode(maze), as: UTF8.self).contains("gauge"))

        let thickTile = tile.gauged(thick)
        #expect(try JSONDecoder().decode(Tile.self, from: JSONEncoder().encode(thickTile)).gauge == thick)
        #expect(thickTile.transformed(by: TileTransform(turns: 2)).gauge == thick)
    }

    @Test(arguments: [thin, thick])
    func aMazeIsMadeAtItsGauge(gauge: PipeGauge) throws {
        let mask = Mask.rectangle(width: 9, height: 8)
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6))
        var sealed = 0
        for seed in 0..<4 {
            var maze = Maze(portsPerEdge: 4, radius: 4, mask: mask, gauge: gauge)
            var random = SeededGenerator(seed: UInt64(seed))
            if generator.fill(&maze, symmetry: .none, using: &random) { sealed += 1 }
            #expect(maze.style.gauge == gauge)
            for placed in maze.cells.values {
                #expect(placed.source.gauge == gauge)
                #expect(!CoverageMap(tile: placed.source).hasViolation)
            }
            // Nothing pokes out of the mask at this thickness.
            let reach = maze.style.pipeWidth / 2
            for (coord, placed) in maze.cells {
                for pipe in placed.oriented.pipes {
                    for segment in PipeShape(pipe, style: maze.style).segments {
                        for point in segment.flattened(steps: 30) {
                            #expect(mask.contains(coord.center + point, inset: reach - 0.02))
                        }
                    }
                }
            }
            if maze.isSealed {
                LoopMerger(generator: generator).mergeAll(&maze, using: &random)
                #expect(maze.cells.values.allSatisfy { $0.source.gauge == gauge })
            }
            let loaded = try JSONDecoder().decode(Maze.self, from: JSONEncoder().encode(maze))
            #expect(loaded == maze)
        }
        #expect(sealed >= 3)
    }

    @Test func thickeningAMazeDropsWhatNoLongerFitsItsMask() {
        let mask = Mask.rectangle(width: 9, height: 8)
        var maze = Maze(portsPerEdge: 4, radius: 4, mask: mask, gauge: thin)
        var random = SeededGenerator(seed: 5)
        MazeGenerator(tiles: []).fill(&maze, symmetry: .none, using: &random)
        let before = maze.cells.count

        let thickened = maze.regauged(thick)
        #expect(thickened.gauge == thick)
        #expect(thickened.cells.count <= before)
        #expect(thickened.cells.values.allSatisfy { $0.source.gauge == thick })
        for (coord, placed) in thickened.cells {
            #expect(thickened.staysInside(placed, at: coord))
            #expect(placed.looksLike(maze.cells[coord]!))
        }
        // Without a mask nothing has to go.
        var open = Maze(portsPerEdge: 4, radius: 3, gauge: thin)
        MazeGenerator(tiles: []).fill(&open, symmetry: .none, using: &random)
        #expect(open.regauged(thick).cells.count == open.cells.count)
    }
}
