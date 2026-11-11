import Foundation
import Testing
@testable import TubeKit

private func port(_ edge: Int, _ slot: Int) -> TubeKit.Port { TubeKit.Port(edge: edge, slot: slot) }

/// An opening at the top of the region and one at the bottom.
private func topAndBottom(radius: Int) -> [PortRef] {
    [
        PortRef(coord: HexCoord(q: 0, r: -radius), port: port(0, 1)),
        PortRef(coord: HexCoord(q: 0, r: radius), port: port(3, 2)),
    ]
}

private func openMaze(seed: UInt64, symmetry: Symmetry = .none, radius: Int = 3) -> (Maze, MazeGenerator) {
    let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6))
    var random = SeededGenerator(seed: seed)
    var maze = Maze(portsPerEdge: 4, radius: radius)
    maze.setOpenings(topAndBottom(radius: radius))
    generator.fill(&maze, symmetry: symmetry, using: &random)
    return (maze, generator)
}

@Suite struct OpeningTests {
    @Test func onlyOutlinePortsCanBeOpenings() {
        var maze = Maze(portsPerEdge: 4, radius: 2)
        // Six corner cells with three outward edges, six side cells with two.
        #expect(maze.outlinePorts.count == (6 * 3 + 6 * 2) * 4)
        maze.setOpenings([
            PortRef(coord: HexCoord(q: 0, r: -2), port: port(0, 1)),
            // Faces into the region, so it is not on the outline.
            PortRef(coord: HexCoord(q: 0, r: -2), port: port(3, 1)),
            PortRef(coord: .origin, port: port(0, 1)),
        ])
        #expect(maze.openings == [PortRef(coord: HexCoord(q: 0, r: -2), port: port(0, 1))])
    }

    @Test func anOpeningIsRequiredNotJustAllowed() throws {
        var maze = Maze(portsPerEdge: 4, radius: 2)
        let top = HexCoord(q: 0, r: -2)
        maze.setOpenings([PortRef(coord: top, port: port(0, 1))])
        #expect(maze.requirement(at: top, edge: 0) == 0b0100)
        #expect(maze.openCells.contains(top))

        let through = try Tile(portsPerEdge: 4, pipes: [Pipe(.corner, a: port(0, 1), b: port(3, 2))])
        let other = try Tile(portsPerEdge: 4, pipes: [Pipe(.corner, a: port(0, 2), b: port(3, 1))])
        #expect(maze.placing(PlacedTile(through), at: top) != nil)
        #expect(maze.placing(PlacedTile(other), at: top) == nil)
    }

    @Test func changingOpeningsRemovesTilesThatNoLongerFit() throws {
        var maze = Maze(portsPerEdge: 4, radius: 2)
        let top = HexCoord(q: 0, r: -2)
        let opening = PortRef(coord: top, port: port(0, 1))
        maze.setOpenings([opening])
        let through = try Tile(portsPerEdge: 4, pipes: [Pipe(.corner, a: port(0, 1), b: port(3, 2))])
        maze = try #require(maze.placing(PlacedTile(through), at: top))

        maze.setOpenings([opening])
        #expect(maze.cells[top] != nil)
        maze.setOpenings([])
        #expect(maze.cells[top] == nil)
    }

    @Test(arguments: [Symmetry.none, .mirror, .sixth])
    func aMazeWithTwoOpeningsHasOnePathBetweenThem(symmetry: Symmetry) throws {
        for seed in 0..<3 {
            let (maze, _) = openMaze(seed: UInt64(seed), symmetry: symmetry)
            #expect(maze.isSealed, "seed \(seed)")
            let open = maze.paths.paths.filter { !$0.isClosed }
            #expect(open.count == 1)
            let ends = try #require(open.first?.ends)
            #expect(Set([ends.start, ends.finish]) == maze.openings)
            for (coord, placed) in maze.cells {
                #expect(maze.fits(placed.code, at: coord))
            }
        }
    }

    @Test func mergingLeavesASinglePathFromEntranceToExit() throws {
        var single = 0
        for seed in 0..<6 {
            var (maze, generator) = openMaze(seed: UInt64(seed))
            var random = SeededGenerator(seed: UInt64(seed))
            LoopMerger(generator: generator).mergeAll(&maze, using: &random)
            let paths = maze.paths
            // The path between the openings always survives merging.
            let open = paths.paths.filter { !$0.isClosed }
            #expect(open.count == 1)
            let ends = try #require(open.first?.ends)
            #expect(Set([ends.start, ends.finish]) == maze.openings)
            #expect(maze.isSealed)
            if paths.paths.count == 1 {
                single += 1
                let pipeCount = maze.cells.values.reduce(0) { $0 + $1.oriented.pipes.count }
                #expect(open.first?.steps.count == pipeCount)
            }
        }
        #expect(single >= 4)
    }

    @Test func anOpenPathStillWeavesCleanly() {
        var (maze, generator) = openMaze(seed: 1)
        var random = SeededGenerator(seed: 1)
        LoopMerger(generator: generator).mergeAll(&maze, using: &random)
        #expect(maze.weave().conflicts == 0)
    }

    @Test func theDrawingLeavesAnOpenPathUnclosed() {
        var (maze, generator) = openMaze(seed: 1)
        var random = SeededGenerator(seed: 1)
        LoopMerger(generator: generator).mergeAll(&maze, using: &random)
        let svg = MazeSVG.render(maze)
        #expect(svg.contains(#"<g id="openings""#))
        let openIndex = maze.paths.paths.firstIndex { !$0.isClosed }! + 1
        let wall = svg.components(separatedBy: "\n").first { $0.contains(#"id="wall-\#(openIndex)""#) }
        #expect(wall?.contains(" Z\"") == false)
    }
}

@Suite struct MazeStorageTests {
    @Test func aMazeSurvivesSavingAndLoading() throws {
        var (maze, generator) = openMaze(seed: 2, symmetry: .mirror)
        var random = SeededGenerator(seed: 2)
        LoopMerger(generator: generator).mergeAll(&maze, using: &random)

        let data = try JSONEncoder().encode(maze)
        let loaded = try JSONDecoder().decode(Maze.self, from: data)
        #expect(loaded == maze)
        #expect(loaded.openings == maze.openings)
        #expect(loaded.isSealed)
        #expect(loaded.paths.paths.count == maze.paths.paths.count)
        #expect(loaded.weave().conflicts == 0)
    }

    @Test func savingIsStableAndCompact() throws {
        let (maze, _) = openMaze(seed: 2)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let first = try encoder.encode(maze)
        let second = try encoder.encode(try JSONDecoder().decode(Maze.self, from: first))
        #expect(first == second)
        // The oriented copy of each tile is not stored.
        let text = String(decoding: first, as: UTF8.self)
        #expect(!text.contains("oriented"))
    }

    @Test func loadingDropsWhatCannotBelong() throws {
        let json = """
        {"portsPerEdge":4,"radius":1,"openings":[{"coord":{"q":0,"r":0},"port":{"edge":0,"slot":1}}],
         "cells":[
          {"coord":{"q":5,"r":5},"tile":{"source":{"id":"00000000-0000-0000-0000-000000000001","portsPerEdge":4,"pipes":[]},"transform":{"turns":0,"mirrored":false}}},
          {"coord":{"q":0,"r":0},"tile":{"source":{"id":"00000000-0000-0000-0000-000000000002","portsPerEdge":3,"pipes":[]},"transform":{"turns":0,"mirrored":false}}},
          {"coord":{"q":0,"r":0},"tile":{"source":{"id":"00000000-0000-0000-0000-000000000003","portsPerEdge":4,"pipes":[]},"transform":{"turns":7,"mirrored":false}}}
         ]}
        """
        let maze = try JSONDecoder().decode(Maze.self, from: Data(json.utf8))
        // Outside the region and wrong port count are dropped; the opening
        // is not on the outline.
        #expect(maze.cells.count == 1)
        #expect(maze.cells[.origin]?.transform.turns == 1)
        #expect(maze.openings.isEmpty)
    }
}
