import Foundation
import Testing
@testable import TubeKit

private func port(_ edge: Int, _ slot: Int) -> TubeKit.Port { TubeKit.Port(edge: edge, slot: slot) }

/// Every point a pipe is drawn through, in maze coordinates.
private func inkPoints(of maze: Maze) -> [(point: Point, reach: Double)] {
    let style = TileStyle(portsPerEdge: maze.portsPerEdge)
    var result: [(Point, Double)] = []
    for (coord, placed) in maze.cells {
        for pipe in placed.oriented.pipes {
            let shape = PipeShape(pipe, style: style)
            for segment in shape.segments {
                for point in segment.flattened(steps: 30) {
                    result.append((coord.center + point, style.pipeWidth / 2))
                }
            }
            if let room = shape.room {
                result.append((coord.center + room.center, room.diameter / 2))
            }
        }
    }
    return result
}

private func staysInside(_ maze: Maze) -> Bool {
    guard let mask = maze.mask else { return true }
    // A hair of slack for curves, which are checked at fewer points when
    // placed than they are sampled at here.
    return inkPoints(of: maze).allSatisfy { mask.contains($0.point, inset: $0.reach - 0.02) }
}

@Suite struct MaskTests {
    @Test func aRectangleContainsWhatIsInsideIt() {
        let mask = Mask.rectangle(center: Point(x: 1, y: 0), width: 4, height: 2)
        #expect(mask.contains(Point(x: 1, y: 0)))
        #expect(mask.contains(Point(x: 2.9, y: 0.9)))
        #expect(!mask.contains(Point(x: 3.1, y: 0)))
        #expect(!mask.contains(Point(x: 1, y: -1.1)))
        // The inset keeps things back from the edge.
        #expect(!mask.contains(Point(x: 2.9, y: 0), inset: 0.2))
        #expect(mask.contains(Point(x: 2.7, y: 0), inset: 0.2))
        let bounds = mask.bounds
        #expect(bounds?.min == Point(x: -1, y: -1))
        #expect(bounds?.max == Point(x: 3, y: 1))
    }

    @Test func laterShapesAddAndTakeAway() {
        var mask = Mask.rectangle(width: 10, height: 10)
        mask.shapes.append(Mask.Shape(center: .zero, width: 2, height: 2, subtracts: true))
        #expect(!mask.contains(.zero))
        #expect(mask.contains(Point(x: 3, y: 3)))
        // A cut-out grows by the inset.
        #expect(mask.contains(Point(x: 1.2, y: 0)))
        #expect(!mask.contains(Point(x: 1.2, y: 0), inset: 0.3))
        // Something added afterwards fills part of the hole back in.
        mask.shapes.append(Mask.Shape(center: .zero, width: 0.5, height: 0.5))
        #expect(mask.contains(.zero))
        #expect(Mask(shapes: []).bounds == nil)
        #expect(!Mask(shapes: []).contains(.zero))
    }

    @Test func bothSidesOfAnEdgeAgreeOnItsPorts() {
        let masks = [
            Mask.rectangle(width: 9, height: 6),
            Mask.rectangle(center: Point(x: 1.3, y: -0.7), width: 7.4, height: 9.1),
            Mask.rectangle(width: 3, height: 11),
        ]
        for mask in masks {
            let maze = Maze(portsPerEdge: 4, radius: 5, mask: mask)
            #expect(maze.cellCount > 0)
            #expect(maze.cellCount == maze.coords.count)
            for coord in maze.coords {
                var live = 0
                for edge in 0..<6 {
                    let mine = maze.allowedValue(at: coord, edge: edge)
                    live += mine.nonzeroBitCount
                    let neighbour = coord.neighbour(across: edge)
                    guard maze.contains(neighbour) else {
                        #expect(mine == 0)
                        continue
                    }
                    let theirs = maze.allowedValue(at: neighbour, edge: (edge + 3) % 6)
                    let flipped = (0..<4).reduce(0) { $0 | ((theirs >> $1) & 1) << (3 - $1) }
                    #expect(mine == flipped)
                }
                // A cell in play can always hold at least one pipe.
                #expect(live >= 2)
            }
        }
    }

    @Test func aMaskThatCoversTheHexagonChangesNothing() {
        let maze = Maze(portsPerEdge: 3, radius: 2, mask: .rectangle(width: 100, height: 100))
        #expect(maze.cellCount == 19)
        #expect(maze.coords.allSatisfy { !maze.isOnBorder($0) || maze.closedPorts(at: $0).isEmpty == false })
        // The hexagon's own outline is still closed.
        #expect(maze.allowedValue(at: HexCoord(q: 0, r: -2), edge: 0) == 0)
        #expect(maze.allowedValue(at: .origin, edge: 0) == 0b111)
    }

    @Test func pipesAndPortsOutsideAreRefused() throws {
        // The mask's top edge runs just below the top of the origin cell,
        // so the ports along that edge are outside it.
        let maze = Maze(portsPerEdge: 3, radius: 2, mask: .rectangle(center: Point(x: 0, y: 0.9), width: 20, height: 3.4))
        let across = try Tile(portsPerEdge: 3, pipes: [Pipe(.bezier, a: port(1, 2), b: port(5, 0))])
        let up = try Tile(portsPerEdge: 3, pipes: [Pipe(.bezier, a: port(0, 1), b: port(3, 1))])
        #expect(maze.closedPorts(at: .origin).contains(port(0, 1)))
        #expect(maze.placing(PlacedTile(up), at: .origin) == nil)
        #expect(!maze.fits(up.edgeCode, at: .origin))

        // Every pipe between open ports is judged by its drawn shape.
        let live = (0..<6).flatMap { edge in (0..<3).map { port(edge, $0) } }
            .filter { !maze.closedPorts(at: .origin).contains($0) }
        #expect(live.count >= 2)
        var kept = 0
        var refused = 0
        for a in live {
            for b in live where a < b {
                guard let tile = try? Tile(portsPerEdge: 3, pipes: [Pipe(.bezier, a: a, b: b)]) else { continue }
                if maze.staysInside(PlacedTile(tile), at: .origin) { kept += 1 } else { refused += 1 }
            }
        }
        #expect(maze.placing(PlacedTile(across), at: .origin) != nil)
        #expect(kept > 0)
        #expect(kept + refused > 0)
    }

    @Test func sliversAtTheEdgeAreLeftOut() {
        // Too thin for a row of tiles to pass pipes along.
        #expect(Maze(portsPerEdge: 3, radius: 3, mask: .rectangle(width: 20, height: 1.2)).cellCount == 0)
        // Every cell in play is open on enough edges to pass pipes through.
        let maze = Maze(portsPerEdge: 4, radius: 6, mask: .rectangle(center: Point(x: 0.4, y: 0.3), width: 11, height: 9))
        for coord in maze.coords {
            let open = (0..<6).filter { maze.allowedValue(at: coord, edge: $0) != 0 }.count
            #expect(open >= 3)
        }
    }

    @Test func aMaskedMazeHasNoOpenings() {
        var maze = Maze(portsPerEdge: 3, radius: 3, mask: .rectangle(width: 6, height: 6))
        #expect(maze.outlinePorts.isEmpty)
        maze.setOpenings([PortRef(coord: HexCoord(q: 0, r: -3), port: port(0, 1))])
        #expect(maze.openings.isEmpty)
    }

    @Test func theRadiusGrowsToHoldTheMask() {
        #expect(Maze.radius(covering: .rectangle(width: 2, height: 2), limit: 12) == 1)
        let wide = Maze.radius(covering: .rectangle(width: 12, height: 4), limit: 12)
        #expect((4...5).contains(wide))
        let covered = Maze(portsPerEdge: 4, radius: wide, mask: .rectangle(width: 12, height: 4))
        let roomier = Maze(portsPerEdge: 4, radius: wide + 2, mask: .rectangle(width: 12, height: 4))
        #expect(covered.cellCount == roomier.cellCount)
        #expect(Maze.radius(covering: .rectangle(width: 500, height: 500), limit: 6) == 6)
    }

    @Test func survivesSavingAndLoading() throws {
        let mask = Mask.rectangle(center: Point(x: 0.5, y: 0), width: 9, height: 7)
        var maze = Maze(portsPerEdge: 4, radius: 4, mask: mask)
        var random = SeededGenerator(seed: 4)
        MazeGenerator(tiles: []).fill(&maze, symmetry: .none, using: &random)
        #expect(!maze.cells.isEmpty)
        let loaded = try JSONDecoder().decode(Maze.self, from: JSONEncoder().encode(maze))
        #expect(loaded == maze)
        #expect(loaded.mask == mask)

        // Files from before masks load as plain hexagons.
        let plain = Maze(portsPerEdge: 4, radius: 2)
        let reloaded = try JSONDecoder().decode(Maze.self, from: JSONEncoder().encode(plain))
        #expect(reloaded.mask == nil)
        #expect(reloaded == plain)
    }

    @Test func reshapingKeepsOnlyWhatStillFits() {
        var maze = Maze(portsPerEdge: 4, radius: 4)
        var random = SeededGenerator(seed: 9)
        MazeGenerator(tiles: []).fill(&maze, symmetry: .none, using: &random)
        let before = maze.cells.count

        let mask = Mask.rectangle(width: 7, height: 6)
        let cut = maze.reshaped(radius: 4, mask: mask)
        #expect(cut.mask == mask)
        #expect(cut.cells.count < before)
        #expect(!cut.cells.isEmpty)
        #expect(staysInside(cut))
        for (coord, placed) in cut.cells {
            #expect(cut.contains(coord))
            #expect(cut.fits(placed.code, at: coord))
            #expect(maze.cells[coord] == placed)
        }
        // Taking the mask off again loses nothing more.
        #expect(cut.reshaped(radius: 4, mask: nil).cells == cut.cells)
    }
}

@Suite struct MaskedGenerationTests {
    static let masks: [Mask] = [
        .rectangle(width: 9, height: 9),
        .rectangle(width: 12, height: 7),
        .rectangle(width: 6.5, height: 11.3),
        .rectangle(center: Point(x: 1.1, y: -0.6), width: 8.3, height: 8.9),
    ]

    @Test(arguments: masks)
    func mazesFillTheMaskAndStayInsideIt(mask: Mask) {
        let radius = Maze.radius(covering: mask, limit: 12)
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6))
        var sealed = 0
        var filled = 0.0
        let runs = 6
        for seed in 0..<runs {
            var maze = Maze(portsPerEdge: 4, radius: radius, mask: mask)
            var random = SeededGenerator(seed: UInt64(seed))
            if generator.fill(&maze, symmetry: .none, using: &random) { sealed += 1 }
            #expect(staysInside(maze))
            for (coord, placed) in maze.cells {
                #expect(maze.fits(placed.code, at: coord))
                #expect(!CoverageMap(tile: placed.source).hasViolation)
            }
            filled += Double(maze.cells.count) / Double(maze.cellCount)

            // Merging rewires tiles, and those must stay inside too.
            if maze.isSealed {
                LoopMerger(generator: generator).mergeAll(&maze, using: &random)
                #expect(staysInside(maze))
                #expect(maze.isSealed)
            }
        }
        #expect(sealed >= runs - 1)
        // The maze should reach into the mask's corners, not huddle in the
        // middle of it.
        #expect(filled / Double(runs) > 0.7)
    }

    @Test(arguments: [Symmetry.mirror, .half, .sixth])
    func symmetryIsKeptWhereTheMaskAllows(symmetry: Symmetry) {
        let mask = Mask.rectangle(width: 9, height: 8)
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6))
        var sealed = 0
        for seed in 0..<4 {
            var maze = Maze(portsPerEdge: 4, radius: 4, mask: mask)
            var random = SeededGenerator(seed: UInt64(seed))
            if generator.fill(&maze, symmetry: symmetry, using: &random) { sealed += 1 }
            #expect(staysInside(maze))
        }
        #expect(sealed >= 3)
    }

    @Test func aGoalStillGetsItsRoom() {
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6))
        var sealed = 0
        for seed in 0..<4 {
            var maze = Maze(portsPerEdge: 4, radius: 4, mask: .rectangle(width: 9, height: 8))
            maze.setGoals([.origin, HexCoord(q: 2, r: -1)])
            var random = SeededGenerator(seed: UInt64(seed))
            if generator.fill(&maze, symmetry: .none, using: &random) { sealed += 1 }
            #expect(staysInside(maze))
        }
        #expect(sealed >= 3)
    }

    @Test func theDrawingIsCroppedToTheMask() {
        let mask = Mask.rectangle(center: Point(x: 1, y: 0), width: 9, height: 6)
        var maze = Maze(portsPerEdge: 4, radius: Maze.radius(covering: mask, limit: 12), mask: mask)
        var random = SeededGenerator(seed: 2)
        MazeGenerator(tiles: []).fill(&maze, symmetry: .none, using: &random)
        var options = MazeSVG.Options()
        options.cellSize = 100
        options.padding = 10
        let svg = MazeSVG.render(maze, options: options)
        // 9 by 6 tile units at 100 each, plus the padding on every side.
        #expect(svg.contains(#"width="920.00" height="620.00""#))
        #expect(svg.contains(#"<g id="bounds""#))
        #expect(svg.contains(#"<rect x="10.00" y="10.00" width="900.00" height="600.00"/>"#))
        #expect(svg.contains(#"clip-path="url(#bounds-clip)""#))
        // A plain hexagon has no bounds group.
        #expect(!MazeSVG.render(Maze(portsPerEdge: 4, radius: 2)).contains("bounds"))
    }

    @Test func aBriefListsThePortsTheMaskCloses() throws {
        let maze = Maze(portsPerEdge: 3, radius: 2, mask: .rectangle(center: Point(x: 0, y: 0.9), width: 20, height: 3.4))
        let brief = try #require(maze.brief(at: .origin))
        #expect(brief.closed == maze.closedPorts(at: .origin))
        #expect(brief.mustAvoid.isSuperset(of: brief.closed))
        let up = try Tile(portsPerEdge: 3, pipes: [Pipe(.bezier, a: port(0, 1), b: port(3, 1))])
        #expect(!brief.isMet(by: up))
    }
}
