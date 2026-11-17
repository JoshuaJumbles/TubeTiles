import Foundation
import Testing
@testable import TubeKit

private func port(_ edge: Int, _ slot: Int) -> TubeKit.Port { TubeKit.Port(edge: edge, slot: slot) }

@Suite struct BuildSheetTests {
    private func filledMaze(seed: UInt64, tiles: [Tile] = [], mask: Mask? = nil) -> Maze {
        var maze = Maze(portsPerEdge: 4, radius: 3, mask: mask)
        var random = SeededGenerator(seed: seed)
        MazeGenerator(tiles: tiles, synthesis: .init(growth: 0.6)).fill(&maze, symmetry: .none, using: &random)
        return maze
    }

    @Test func labelsRunPastZ() {
        #expect(BuildSheet.label(0) == "A")
        #expect(BuildSheet.label(25) == "Z")
        #expect(BuildSheet.label(26) == "AA")
        #expect(BuildSheet.label(27) == "AB")
        #expect(BuildSheet.label(26 + 26 * 26) == "AAA")
        #expect(Set((0..<1000).map(BuildSheet.label)).count == 1000)
    }

    @Test(arguments: [false, true])
    func everyCellIsItsEntryTurned(flippedIsSame: Bool) {
        for seed in 0..<4 {
            let maze = filledMaze(seed: UInt64(seed), mask: seed == 3 ? .rectangle(width: 8, height: 7) : nil)
            let sheet = BuildSheet(maze: maze, flippedIsSame: flippedIsSame)
            #expect(sheet.tileCount == maze.cells.count)
            #expect(sheet.entries.reduce(0) { $0 + $1.count } == maze.cells.count)
            #expect(Set(sheet.entries.map(\.label)).count == sheet.entries.count)
            for (coord, placed) in maze.cells {
                let placement = sheet.placements[coord]!
                if !flippedIsSame { #expect(!placement.transform.mirrored) }
                let rebuilt = sheet.entries[placement.entry].tile.transformed(by: placement.transform)
                #expect(Set(rebuilt.pipes) == Set(placed.oriented.pipes))
            }
            // Most used first.
            #expect(sheet.entries.map(\.count) == sheet.entries.map(\.count).sorted(by: >))
            // No two entries are the same tile turned.
            let turns = TileTransform.allCases.filter { flippedIsSame || !$0.mirrored }
            for (index, entry) in sheet.entries.enumerated() {
                for other in sheet.entries.dropFirst(index + 1) {
                    #expect(!turns.contains { Set(entry.tile.transformed(by: $0).pipes) == Set(other.tile.pipes) })
                }
            }
        }
    }

    @Test func turnedCopiesShareAnEntryAndFlippedOnesOnlyIfAllowed() throws {
        // A lopsided tile, so its mirror image is a different tile.
        let tile = try Tile(portsPerEdge: 3, pipes: [
            Pipe(.bezier, a: port(0, 0), b: port(2, 1)),
            Pipe(.corner, a: port(3, 2), b: port(5, 1)),
        ])
        var maze = Maze(portsPerEdge: 3, radius: 6)
        // Far apart, so no two touch and each is free to face any way.
        let spots = [HexCoord(q: 0, r: 0), HexCoord(q: 3, r: 0), HexCoord(q: -3, r: 3), HexCoord(q: 0, r: -3)]
        let ways = [TileTransform.identity, TileTransform(turns: 2), TileTransform(turns: 5), TileTransform(turns: 1, mirrored: true)]
        for (spot, way) in zip(spots, ways) {
            maze = try #require(maze.placing(PlacedTile(tile, transform: way), at: spot))
        }

        let strict = BuildSheet(maze: maze)
        #expect(strict.entries.map(\.count) == [3, 1])
        #expect(strict.entries.map(\.label) == ["A", "B"])
        #expect(Set(spots.prefix(3).map { strict.placements[$0]!.entry }) == [0])
        #expect(strict.placements[spots[3]]!.entry == 1)

        let loose = BuildSheet(maze: maze, flippedIsSame: true)
        #expect(loose.entries.map(\.count) == [4])
        #expect(loose.placements.values.filter(\.transform.mirrored).count == 1)
    }

    @Test func emptyMazesAndThickPipesAreHandled() {
        var random = SeededGenerator(seed: 21)
        var library: [Tile] = []
        while library.count < 30 {
            var tile = Tile(portsPerEdge: 4)
            tile.fillRandomly(kinds: [.bezier, .corner], avoiding: [], using: &random)
            if !tile.pipes.isEmpty { library.append(tile) }
        }
        let made = BuildSheet(maze: filledMaze(seed: 1))
        #expect(made.entries.count <= made.tileCount)
        #expect(BuildSheet(maze: Maze(portsPerEdge: 4, radius: 2)).entries.isEmpty)
        // The gauge of the maze carries over to the stencils.
        var thick = Maze(portsPerEdge: 4, radius: 2, gauge: PipeGauge(width: 0.9, wall: 0.3))
        MazeGenerator(tiles: library).fill(&thick, symmetry: .none, using: &random)
        #expect(BuildSheet(maze: thick).entries.allSatisfy { $0.tile.gauge == thick.gauge })
    }
}
