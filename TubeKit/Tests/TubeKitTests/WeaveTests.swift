import Foundation
import Testing
@testable import TubeKit

private func port(_ edge: Int, _ slot: Int) -> TubeKit.Port { TubeKit.Port(edge: edge, slot: slot) }

private func sealedMaze(seed: UInt64, symmetry: Symmetry = .none, radius: Int = 3) -> Maze {
    let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6))
    var random = SeededGenerator(seed: seed)
    var maze = Maze(portsPerEdge: 4, radius: radius)
    generator.fill(&maze, symmetry: symmetry, using: &random)
    return maze
}

@Suite struct PolylineTests {
    @Test func measuresAndSlices() {
        let line = Polyline(points: [Point(x: 0, y: 0), Point(x: 2, y: 0), Point(x: 2, y: 2)])
        #expect(line.length == 4)
        #expect(line.point(at: 1) == Point(x: 1, y: 0))
        #expect(line.point(at: 3) == Point(x: 2, y: 1))
        #expect(line.point(at: 99) == Point(x: 2, y: 2))
        // A slice across the corner keeps the corner.
        #expect(line.slice(from: 1, to: 3) == [Point(x: 1, y: 0), Point(x: 2, y: 0), Point(x: 2, y: 1)])
    }
}

@Suite struct CrossingTests {
    @Test func twoStraightPipesCrossOnce() throws {
        let tile = try Tile(portsPerEdge: 5, pipes: [
            Pipe(.corner, a: port(0, 2), b: port(3, 2)),
            Pipe(.corner, a: port(1, 2), b: port(4, 2)),
        ])
        let crossings = tile.crossings()
        #expect(crossings.count == 1)
        let crossing = try #require(crossings.first)
        // Both run through the middle of the tile.
        #expect(crossing.point.distance(to: Point.zero) < 1e-9)
        #expect(abs(crossing.sharpness - (3.0).squareRoot() / 2) < 1e-9)
        #expect(abs(crossing.firstDistance - HexGeometry.inradius) < 1e-9)
    }

    @Test func parallelPipesDoNotCross() throws {
        let tile = try Tile(portsPerEdge: 5, pipes: [
            Pipe(.corner, a: port(0, 1), b: port(3, 3)),
            Pipe(.corner, a: port(0, 3), b: port(3, 1)),
        ])
        #expect(tile.crossings().isEmpty)
    }
}

@Suite struct WeaveTests {
    /// Follows each path and checks it goes over, under, over, under.
    private func alternationBreaks(in maze: Maze, weave: Weave) -> Int {
        var breaks = 0
        for path in maze.paths.paths {
            var overs: [Bool] = []
            for step in path.steps {
                let here = weave.crossings(at: step.coord)
                    .filter { $0.first == step.pipe || $0.second == step.pipe }
                    .map { crossing -> (Double, Bool) in
                        let isFirst = crossing.first == step.pipe
                        return (isFirst ? crossing.firstDistance : crossing.secondDistance, crossing.firstIsOver == isFirst)
                    }
                let forwards = step.entry == step.pipe.a
                overs += here.sorted { forwards ? $0.0 < $1.0 : $0.0 > $1.0 }.map(\.1)
            }
            guard overs.count > 1 else { continue }
            for index in 0..<(path.isClosed ? overs.count : overs.count - 1)
            where overs[index] == overs[(index + 1) % overs.count] {
                breaks += 1
            }
        }
        return breaks
    }

    @Test(arguments: Symmetry.allCases)
    func everyPathAlternates(symmetry: Symmetry) {
        for seed in 0..<3 {
            let maze = sealedMaze(seed: UInt64(seed), symmetry: symmetry)
            let weave = maze.weave()
            #expect(!weave.crossings.isEmpty)
            #expect(weave.conflicts == 0)
            #expect(alternationBreaks(in: maze, weave: weave) == 0)
        }
    }

    @Test func alternationSurvivesMerging() {
        var maze = sealedMaze(seed: 2)
        var random = SeededGenerator(seed: 7)
        LoopMerger(generator: MazeGenerator(tiles: [])).mergeAll(&maze, using: &random)
        let weave = maze.weave()
        #expect(weave.conflicts == 0)
        #expect(alternationBreaks(in: maze, weave: weave) == 0)
    }

    @Test func eachPathCrossesAnEvenNumberOfTimes() {
        // A loop that alternates all the way round must meet an even number
        // of crossings, counting a crossing with itself twice.
        let maze = sealedMaze(seed: 1)
        let weave = maze.weave()
        for path in maze.paths.paths where path.isClosed {
            var visits = 0
            for step in path.steps {
                visits += weave.crossings(at: step.coord).filter { $0.first == step.pipe }.count
                visits += weave.crossings(at: step.coord).filter { $0.second == step.pipe }.count
            }
            #expect(visits % 2 == 0)
        }
    }
}

@Suite struct MazeSVGTests {
    @Test func hasOneOutlinePerPathInEachLayer() {
        let maze = sealedMaze(seed: 3)
        let svg = MazeSVG.render(maze)
        let pathCount = maze.paths.paths.count
        #expect(svg.hasPrefix("<?xml"))
        #expect(svg.contains(#"<g id="walls""#))
        #expect(svg.contains(#"<g id="tubes""#))
        #expect(svg.contains(#"<g id="crossings""#))
        #expect(svg.components(separatedBy: #"<path id="wall-"#).count - 1 == pathCount)
        #expect(svg.components(separatedBy: #"<path id="tube-"#).count - 1 == pathCount)
        #expect(svg.components(separatedBy: "<g>").count - 1 == maze.weave().crossings.count)
        // Closed paths are closed outlines, and curves are real curves.
        #expect(svg.contains(" Z\""))
        #expect(svg.contains(" C "))
        #expect(!svg.contains("nan"))
    }

    @Test func pathColoursAndBackgroundAreOptional() {
        let maze = sealedMaze(seed: 3)
        var options = MazeSVG.Options()
        options.pathColors = [0: "#ff8800"]
        options.background = "#eeeeee"
        options.includesCells = false
        let svg = MazeSVG.render(maze, options: options)
        #expect(svg.contains("stroke=\"#ff8800\""))
        #expect(svg.contains(#"<rect id="background""#))
        #expect(!svg.contains(#"<g id="cells""#))
    }

    /// Writes a sample drawing when `TUBETILES_SVG_OUT` names a file, for
    /// checking the export by eye.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TUBETILES_SVG_OUT"] != nil))
    func writesASample() throws {
        let path = ProcessInfo.processInfo.environment["TUBETILES_SVG_OUT"]!
        var maze = sealedMaze(seed: 4, symmetry: .third)
        var random = SeededGenerator(seed: 4)
        LoopMerger(generator: MazeGenerator(tiles: [])).mergeAll(&maze, symmetry: .third, using: &random)
        var options = MazeSVG.Options()
        options.background = "#ede8dc"
        try MazeSVG.render(maze, options: options).write(toFile: path, atomically: true, encoding: .utf8)
    }
}
