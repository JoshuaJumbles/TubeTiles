import Foundation
import Testing
@testable import TubeKit

private func port(_ edge: Int, _ slot: Int) -> TubeKit.Port { TubeKit.Port(edge: edge, slot: slot) }

@Suite struct DeadEndPipeTests {
    @Test func aDeadEndUsesOnePort() throws {
        let end = Pipe(.endSmall, at: port(0, 2))
        #expect(end.isDeadEnd)
        #expect(end.ports == [port(0, 2)])
        #expect(end.otherEnd(from: port(0, 2)) == nil)
        #expect(PlacementRules.shapeError(for: end, portsPerEdge: 5) == nil)
        // A dead end cannot span two ports, and an ordinary pipe needs two.
        #expect(PlacementRules.shapeError(for: Pipe(.endSmall, a: port(0, 2), b: port(3, 2)), portsPerEdge: 5) == .deadEndNeedsOnePort)
        #expect(PlacementRules.shapeError(for: Pipe(.bezier, a: port(0, 2), b: port(0, 2)), portsPerEdge: 5) == .samePort)

        let tile = try Tile(portsPerEdge: 5, pipes: [end])
        #expect(tile.occupiedPorts == [port(0, 2)])
        #expect(tile.edgeCode.values == [0b00100, 0, 0, 0, 0, 0])
        #expect(tile.deadEnds == [end])
    }

    @Test func theRoomSitsStraightInFromThePort() {
        let style = TileStyle(portsPerEdge: 5)
        for kind in PipeKind.deadEndKinds {
            let shape = PipeShape(Pipe(kind, at: port(0, 2)), style: style)
            let start = HexGeometry.position(of: port(0, 2), portsPerEdge: 5)
            let room = shape.room!
            // Edge 0 is the top, so straight in is straight down.
            #expect(abs(room.center.x - start.x) < 1e-9)
            #expect(room.center.y > start.y)
            // The room clears the edge the pipe came from.
            #expect(room.center.y - room.diameter / 2 > start.y)
        }
        let sizes = PipeKind.deadEndKinds.map { style.roomDiameter(for: $0)! }
        #expect(sizes == sizes.sorted(by: >))
    }

    @Test(arguments: [3, 4, 5, 6])
    func theLargestRoomFitsFromMidEdge(portsPerEdge: Int) throws {
        // With an even port count there is no exact middle, so both ports
        // either side of it must work.
        for slot in Set([(portsPerEdge - 1) / 2, portsPerEdge / 2]) {
            var tile = Tile(portsPerEdge: portsPerEdge)
            try tile.add(Pipe(.endLarge, at: port(0, slot)))
            #expect(tile.pipes.count == 1)
        }
    }

    @Test func nothingCrossesADeadEndRoom() throws {
        var tile = Tile(portsPerEdge: 5)
        try tile.add(Pipe(.endMedium, at: port(0, 2)))
        #expect(throws: PlacementError.overlap) {
            try tile.add(Pipe(.corner, a: port(1, 2), b: port(4, 2)))
        }
        // A pipe that keeps clear of the room is fine.
        try tile.add(Pipe(.bezier, a: port(3, 0), b: port(3, 4)))
    }

    @Test func deadEndsSurviveTransformsAndStorage() throws {
        let tile = try Tile(portsPerEdge: 5, pipes: [
            Pipe(.endSmall, at: port(1, 1)),
            Pipe(.bezier, a: port(3, 0), b: port(4, 4)),
        ])
        for transform in TileTransform.allCases {
            let moved = tile.transformed(by: transform)
            #expect(moved.deadEnds.count == 1)
            #expect(moved.edgeCode == tile.edgeCode.transformed(by: transform))
            #expect(moved.transformed(by: transform.inverse) == tile)
        }
        let loaded = try JSONDecoder().decode(Tile.self, from: JSONEncoder().encode(tile))
        #expect(loaded == tile)
    }

    @Test func theSynthesizerBuildsAroundADeadEnd() throws {
        var random = SeededGenerator(seed: 5)
        let ports = [port(0, 1), port(2, 0), port(4, 3)]
        let tile = try #require(TileSynthesizer.tile(
            portsPerEdge: 4, ports: ports, deadEnd: (port(0, 1), .endSmall), using: &random
        ))
        #expect(tile.occupiedPorts == Set(ports))
        #expect(tile.deadEnds == [Pipe(.endSmall, at: port(0, 1))])
        #expect(tile.pipes.count == 2)
        let rebuilt = try Tile(portsPerEdge: 4, pipes: tile.pipes)
        #expect(rebuilt.pipes == tile.pipes)
        // Without a dead end, three ports cannot be paired up.
        #expect(TileSynthesizer.tile(portsPerEdge: 4, ports: ports, using: &random) == nil)
    }
}

@Suite struct DeadEndPathTests {
    @Test func twoDeadEndsFacingEachOtherAreOneShortPath() throws {
        let down = try Tile(portsPerEdge: 3, pipes: [Pipe(.endSmall, at: port(3, 1))])
        var maze = Maze(portsPerEdge: 3, radius: 1)
        maze = try #require(maze.placing(PlacedTile(down), at: HexCoord(q: 0, r: -1)))
        maze = try #require(maze.placing(PlacedTile(down, transform: TileTransform(turns: 3)), at: .origin))
        #expect(maze.isSealed)

        let paths = maze.paths
        #expect(paths.paths.count == 1)
        let path = try #require(paths.paths.first)
        #expect(!path.isClosed)
        #expect(path.steps.count == 2)
        // It sets off from one room and finishes in the other.
        #expect(path.steps[0].startsInRoom)
        #expect(path.steps[0].runsBackwards)
        #expect(!path.steps[1].startsInRoom)
        #expect(!path.steps[1].runsBackwards)
    }

    @Test func aPathIsFollowedIntoADeadEndFromEitherSide() throws {
        // A dead end below, a straight pipe, a dead end above. The trace
        // starts from the lowest cell, which here is the top dead end.
        let end = try Tile(portsPerEdge: 3, pipes: [Pipe(.endSmall, at: port(3, 1))])
        let straight = try Tile(portsPerEdge: 3, pipes: [Pipe(.corner, a: port(0, 1), b: port(3, 1))])
        var maze = Maze(portsPerEdge: 3, radius: 1)
        maze = try #require(maze.placing(PlacedTile(straight), at: .origin))
        maze = try #require(maze.placing(PlacedTile(end), at: HexCoord(q: 0, r: -1)))
        maze = try #require(maze.placing(PlacedTile(end, transform: TileTransform(turns: 3)), at: HexCoord(q: 0, r: 1)))
        let paths = maze.paths
        #expect(paths.paths.count == 1)
        let path = try #require(paths.paths.first)
        #expect(path.steps.count == 3)
        #expect(path.steps.first?.pipe.isDeadEnd == true)
        #expect(path.steps.last?.pipe.isDeadEnd == true)
        #expect(path.steps.first?.startsInRoom == true)
        #expect(path.steps.last?.startsInRoom == false)
    }
}

@Suite struct GoalTests {
    private func labyrinth(seed: UInt64, symmetry: Symmetry = .none) -> (Maze, MazeGenerator) {
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6))
        var random = SeededGenerator(seed: seed)
        var maze = Maze(portsPerEdge: 4, radius: 3)
        maze.setOpenings([PortRef(coord: HexCoord(q: 0, r: -3), port: port(0, 1))])
        maze.setGoals([.origin])
        generator.fill(&maze, symmetry: symmetry, using: &random)
        return (maze, generator)
    }

    @Test func anOddNumberOfEndsCannotBeGrown() {
        var random = SeededGenerator(seed: 1)
        var maze = Maze(portsPerEdge: 4, radius: 2)
        maze.setGoals([.origin])
        #expect(maze.endCount == 1)
        #expect(MazeGenerator(tiles: []).step(&maze, symmetry: .none, using: &random) == .stuck(.origin))
        #expect(maze.cells.isEmpty)
    }

    @Test func aGoalIsOpenUntilItIsFilledAndSwapsOutItsTile() throws {
        var maze = Maze(portsPerEdge: 4, radius: 2)
        maze.setGoals([.origin, HexCoord(q: 9, r: 9)])
        #expect(maze.goals == [.origin])
        #expect(maze.openCells == [.origin])
        let through = try Tile(portsPerEdge: 4, pipes: [Pipe(.corner, a: port(0, 1), b: port(3, 2))])
        maze = try #require(maze.placing(PlacedTile(through), at: .origin))
        // No longer a goal: its tile is taken out so an ordinary one can go in.
        maze.setGoals([])
        #expect(maze.cells[.origin] == nil)
    }

    @Test(arguments: [Symmetry.none, .mirror, .sixth])
    func oneEntranceAndOneGoalMakeALabyrinth(symmetry: Symmetry) throws {
        for seed in 0..<3 {
            let (maze, _) = labyrinth(seed: UInt64(seed), symmetry: symmetry)
            #expect(maze.isSealed, "seed \(seed)")

            // The goal tile has the only dead end in the maze.
            let goalTile = try #require(maze.cells[.origin])
            #expect(goalTile.oriented.deadEnds.count == 1)
            let elsewhere = maze.cells.filter { $0.key != .origin }.values.flatMap(\.oriented.deadEnds)
            #expect(elsewhere.isEmpty)

            // Exactly one path has ends: from the opening to the goal.
            let open = maze.paths.paths.filter { !$0.isClosed }
            #expect(open.count == 1)
            let ends = try #require(open.first?.ends)
            let opening = try #require(maze.openings.first)
            let goalEnd = PortRef(coord: .origin, port: goalTile.oriented.deadEnds[0].a)
            #expect(Set([ends.start, ends.finish]) == [opening, goalEnd])
            for (coord, placed) in maze.cells {
                #expect(maze.fits(placed.code, at: coord))
                #expect(!CoverageMap(tile: placed.source).hasViolation)
            }
        }
    }

    /// The goal goes in first and is not disturbed by later regrowth, so it
    /// keeps the largest room however the rest of the maze turns out.
    @Test(arguments: [4, 6])
    func theGoalKeepsTheLargestRoom(portsPerEdge: Int) throws {
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6))
        for seed in 0..<8 {
            var random = SeededGenerator(seed: UInt64(seed))
            var maze = Maze(portsPerEdge: portsPerEdge, radius: 3)
            maze.setOpenings([PortRef(coord: HexCoord(q: 0, r: -3), port: port(0, 1))])
            maze.setGoals([.origin])
            #expect(generator.fill(&maze, symmetry: .none, using: &random), "seed \(seed)")
            let end = try #require(maze.cells[.origin]?.oriented.deadEnds.first)
            #expect(end.kind == .endLarge, "seed \(seed)")
            #expect(maze.cells[.origin]?.oriented.pipes.count == 1)
        }
    }

    @Test func mergingLeavesOnePathFromEntranceToGoal() throws {
        var single = 0
        for seed in 0..<6 {
            var (maze, generator) = labyrinth(seed: UInt64(seed))
            var random = SeededGenerator(seed: UInt64(seed))
            LoopMerger(generator: generator).mergeAll(&maze, using: &random)
            #expect(maze.isSealed)
            #expect(maze.cells[.origin]?.oriented.deadEnds.count == 1)
            let paths = maze.paths
            #expect(paths.paths.filter { !$0.isClosed }.count == 1)
            if paths.paths.count == 1 {
                single += 1
                let pipeCount = maze.cells.values.reduce(0) { $0 + $1.oriented.pipes.count }
                #expect(paths.paths[0].steps.count == pipeCount)
                // The whole maze is one walk from the edge to the room.
                #expect(paths.paths[0].steps.first?.pipe.isDeadEnd == true || paths.paths[0].steps.last?.pipe.isDeadEnd == true)
            }
        }
        #expect(single >= 4)
    }

    /// A path that ends inside the maze cannot always alternate over and
    /// under: where a loop of the path encloses the end, some crossing has to
    /// repeat. The weave settles for as few of those as it finds, and mazes
    /// without a goal are unaffected.
    @Test func aGoalCanCostAFewCrossingsTheirAlternation() {
        var worst = 0
        for seed in 0..<12 {
            var (maze, generator) = labyrinth(seed: UInt64(seed))
            var random = SeededGenerator(seed: UInt64(seed))
            LoopMerger(generator: generator).mergeAll(&maze, using: &random)
            let weave = maze.weave()
            worst = max(worst, weave.conflicts)
            #expect(weave.conflicts * 3 <= max(weave.crossings.count, 3))
        }
        #expect(worst <= 6)
    }

    @Test func twoGoalsMakeAPathFromRoomToRoom() throws {
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6))
        var random = SeededGenerator(seed: 3)
        var maze = Maze(portsPerEdge: 4, radius: 3)
        maze.setGoals([HexCoord(q: -2, r: 1), HexCoord(q: 2, r: -1)])
        #expect(generator.fill(&maze, symmetry: .none, using: &random))
        let open = maze.paths.paths.filter { !$0.isClosed }
        #expect(open.count == 1)
        #expect(open.first?.steps.first?.pipe.isDeadEnd == true)
        #expect(open.first?.steps.last?.pipe.isDeadEnd == true)
    }

    @Test func libraryDeadEndTilesAreOnlyUsedOnGoals() throws {
        let stub = try Tile(portsPerEdge: 4, pipes: [Pipe(.endSmall, at: port(0, 1))])
        let plain = try Tile(portsPerEdge: 4, pipes: [Pipe(.corner, a: port(0, 1), b: port(3, 2))])
        let double = try Tile(portsPerEdge: 4, pipes: [Pipe(.endSmall, at: port(0, 1)), Pipe(.endSmall, at: port(3, 1))])
        let generator = MazeGenerator(tiles: [stub, plain, double])
        #expect(generator.goalOptions.allSatisfy { $0.source.id == stub.id })
        #expect(generator.goalOptions.count == 12)
        #expect(generator.options.allSatisfy { $0.source.id == plain.id })
    }

    @Test func aLabyrinthSurvivesSavingAndDrawing() throws {
        var (maze, generator) = labyrinth(seed: 1)
        var random = SeededGenerator(seed: 1)
        LoopMerger(generator: generator).mergeAll(&maze, using: &random)
        let loaded = try JSONDecoder().decode(Maze.self, from: JSONEncoder().encode(maze))
        #expect(loaded == maze)
        #expect(loaded.goals == [.origin])

        let svg = MazeSVG.render(maze)
        let openIndex = try #require(maze.paths.paths.firstIndex { !$0.isClosed }) + 1
        let wall = svg.components(separatedBy: "\n").first { $0.contains("id=\"wall-\(openIndex)\"") }
        #expect(wall?.contains(" Z\"") == false)
        #expect(!svg.contains("nan"))
    }
}

@Suite struct LibraryRuleTests {
    @Test func olderLibraryFilesStillLoad() throws {
        // As written before libraries had an identity, a note or rules.
        let json = #"{"name":"6 ports","portsPerEdge":4,"tiles":[{"id":"00000000-0000-0000-0000-000000000001","portsPerEdge":4,"pipes":[{"kind":"bezier","a":{"edge":0,"slot":0},"b":{"edge":2,"slot":3}}]}]}"#
        let library = try JSONDecoder().decode(TileLibrary.self, from: Data(json.utf8))
        #expect(library.name == "6 ports")
        #expect(library.note.isEmpty)
        #expect(library.allowedKinds == Set(PipeKind.allCases))
        #expect(library.tiles.count == 1)
    }

    @Test func rulesSurviveSavingAndStayStable() throws {
        var library = TileLibrary(name: "Curves", note: "Soft and loopy", portsPerEdge: 4, allowedKinds: [.bezier, .endSmall])
        library.save(try Tile(portsPerEdge: 4, pipes: [Pipe(.bezier, a: port(0, 0), b: port(2, 3))]))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(library)
        let loaded = try JSONDecoder().decode(TileLibrary.self, from: data)
        #expect(loaded == library)
        #expect(try encoder.encode(loaded) == data)
        #expect(loaded.throughKinds == [.bezier])
        #expect(loaded.deadEndKinds == [.endSmall])
    }

    @Test func aLibraryKnowsWhichTilesBreakItsRules() throws {
        var library = TileLibrary(name: "Curves", portsPerEdge: 4, allowedKinds: [.bezier])
        let curve = try Tile(portsPerEdge: 4, pipes: [Pipe(.bezier, a: port(0, 0), b: port(2, 3))])
        let corner = try Tile(portsPerEdge: 4, pipes: [Pipe(.corner, a: port(0, 0), b: port(2, 3))])
        library.save(curve)
        library.save(corner)
        #expect(library.allows(curve))
        #expect(!library.allows(corner))
        #expect(library.offPaletteTiles.map(\.id) == [corner.id])
    }

    @Test func duplicatingCopiesRulesAndGivesTilesNewIdentities() throws {
        var library = TileLibrary(name: "Curves", note: "n", portsPerEdge: 4, allowedKinds: [.bezier])
        library.save(try Tile(portsPerEdge: 4, pipes: [Pipe(.bezier, a: port(0, 0), b: port(2, 3))]))
        let copy = library.duplicated(named: "Curves 2")
        #expect(copy.id != library.id)
        #expect(copy.name == "Curves 2")
        #expect(copy.allowedKinds == library.allowedKinds)
        #expect(copy.tiles.map(\.pipes) == library.tiles.map(\.pipes))
        #expect(copy.tiles.map(\.id) != library.tiles.map(\.id))
    }

    @Test func weightedKindsKeepToWhatIsAllowed() {
        #expect(Set(TileSynthesizer.kinds(allowing: [.bezier, .roomSmall, .endLarge])) == [.bezier, .roomSmall])
        // None of the usual kinds allowed: fall back to whatever is.
        #expect(TileSynthesizer.kinds(allowing: [.roomLarge, .endSmall]) == [.roomLarge])
        #expect(TileSynthesizer.kinds(allowing: [.endSmall]).isEmpty)
    }

    /// The point of the rules: tiles the generator makes up use only the
    /// library's kinds, through growing, a goal, and merging.
    @Test(arguments: [Set<PipeKind>([.bezier]), [.corner], [.bezier, .roomSmall, .endMedium]])
    func madeUpTilesFollowTheLibrary(allowed: Set<PipeKind>) throws {
        let library = TileLibrary(name: "Rules", portsPerEdge: 4, allowedKinds: allowed)
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6, following: library))
        var used: Set<PipeKind> = []
        for seed in 0..<3 {
            var random = SeededGenerator(seed: UInt64(seed))
            var maze = Maze(portsPerEdge: 4, radius: 3)
            maze.setOpenings([PortRef(coord: HexCoord(q: 0, r: -3), port: port(0, 1))])
            maze.setGoals([.origin])
            generator.fill(&maze, symmetry: .none, using: &random)
            LoopMerger(generator: generator).mergeAll(&maze, using: &random)
            #expect(!maze.cells.isEmpty)
            for placed in maze.cells.values {
                used.formUnion(placed.oriented.pipes.map(\.kind))
            }
        }
        // A goal always needs a dead end; if the library allows none, any
        // size may be used for it, and only for it.
        let permitted = allowed.union(library.deadEndKinds.isEmpty ? Set(PipeKind.deadEndKinds) : [])
        #expect(used.isSubset(of: permitted), "used \(used)")
        #expect(!used.isDisjoint(with: allowed))
    }
}

@Suite struct DeadPortTests {
    @Test func deadSlotsApplyToEveryEdgeAndAreMirrored() {
        var library = TileLibrary(name: "Narrow", portsPerEdge: 6)
        #expect(library.deadPorts.isEmpty)
        #expect(library.deadSlots == [])
        #expect(library.liveSlotCount == 6)

        // Switching off the first slot also switches off the last.
        library.setDeadSlots([0])
        #expect(library.deadSlots == [0, 5])
        #expect(library.deadPorts.count == 12)
        #expect(library.liveSlotCount == 4)
        #expect(!library.isLive(port(3, 5)))
        #expect(library.isLive(port(3, 2)))

        // Out-of-range slots are ignored, and setting replaces what was there.
        library.setDeadSlots([2, 9])
        #expect(library.deadSlots == [2, 3])
    }

    /// The reason for mirroring: a tile that avoids the dead ports still
    /// avoids them however it is turned or flipped.
    @Test func liveTilesStayLiveUnderEveryPlacement() throws {
        let library = TileLibrary(name: "Narrow", portsPerEdge: 6, deadSlots: [0])
        let tile = try Tile(portsPerEdge: 6, pipes: [
            Pipe(.bezier, a: port(0, 1), b: port(2, 4)),
            Pipe(.corner, a: port(1, 2), b: port(4, 3)),
        ])
        #expect(!library.usesDeadPort(tile))
        for transform in TileTransform.allCases {
            #expect(!library.usesDeadPort(tile.transformed(by: transform)))
        }
        // And what it asks of a neighbour is live too.
        for used in tile.occupiedPorts {
            #expect(library.isLive(used.neighbourPort(portsPerEdge: 6)))
        }
    }

    @Test func deadPortsSurviveSavingAndOlderFilesHaveNone() throws {
        var library = TileLibrary(name: "Narrow", portsPerEdge: 5, deadSlots: [0])
        let onDead = try Tile(portsPerEdge: 5, pipes: [Pipe(.bezier, a: port(0, 0), b: port(2, 2))])
        library.save(onDead)
        #expect(library.deadPortTiles.map(\.id) == [onDead.id])

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(library)
        let loaded = try JSONDecoder().decode(TileLibrary.self, from: data)
        #expect(loaded == library)
        #expect(loaded.deadSlots == [0, 4])
        #expect(try encoder.encode(loaded) == data)
        #expect(library.duplicated(named: "Copy").deadPorts == library.deadPorts)

        let older = #"{"name":"Old","portsPerEdge":4,"tiles":[]}"#
        #expect(try JSONDecoder().decode(TileLibrary.self, from: Data(older.utf8)).deadPorts.isEmpty)
    }

    @Test func aPatternThatDiffersByEdgeIsNotUniform() throws {
        // Per-edge patterns are not offered yet, but the stored form allows
        // them, and a library holding one says so.
        let json = #"{"name":"Odd","portsPerEdge":4,"tiles":[],"deadPorts":[{"edge":0,"slot":1}]}"#
        let library = try JSONDecoder().decode(TileLibrary.self, from: Data(json.utf8))
        #expect(library.deadPorts == [port(0, 1)])
        #expect(library.deadSlots == nil)
        #expect(library.liveSlotCount == nil)
    }

    @Test func randomFillKeepsOffDeadPorts() {
        let library = TileLibrary(name: "Narrow", portsPerEdge: 6, deadSlots: [0, 1])
        for seed in 0..<6 {
            var random = SeededGenerator(seed: UInt64(seed))
            var tile = Tile(portsPerEdge: 6)
            let added = tile.fillRandomly(avoiding: library.deadPorts, using: &random)
            #expect(added > 0)
            #expect(!library.usesDeadPort(tile))
        }
    }

    /// Made-up tiles never put a pipe on a dead port: through growing from
    /// an entrance, placing a goal, and merging.
    @Test(arguments: [Set<Int>([0]), [0, 1], [2]])
    func madeUpTilesKeepOffDeadPorts(deadSlots: Set<Int>) throws {
        let library = TileLibrary(name: "Narrow", portsPerEdge: 6, deadSlots: deadSlots)
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6, following: library))
        let entrance = try #require((0..<6).map { port(0, $0) }.first(where: library.isLive))
        for seed in 0..<3 {
            var random = SeededGenerator(seed: UInt64(seed))
            var maze = Maze(portsPerEdge: 6, radius: 3)
            maze.setOpenings([PortRef(coord: HexCoord(q: 0, r: -3), port: entrance)])
            maze.setGoals([.origin])
            #expect(generator.fill(&maze, symmetry: .none, using: &random), "seed \(seed)")
            LoopMerger(generator: generator).mergeAll(&maze, using: &random)
            #expect(maze.isSealed)
            #expect(maze.cells.count > 6)
            for placed in maze.cells.values {
                #expect(!library.usesDeadPort(placed.oriented))
            }
        }
    }

    @Test func aPipeArrivingOnADeadPortIsStillMet() throws {
        // A hand-made tile may use a dead port. Its neighbour has to join up
        // with it regardless, or the maze could never be sealed.
        let library = TileLibrary(name: "Narrow", portsPerEdge: 4, deadSlots: [0])
        let onDead = try Tile(portsPerEdge: 4, pipes: [Pipe(.bezier, a: port(3, 0), b: port(3, 3))])
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0, following: library))
        var random = SeededGenerator(seed: 1)
        var maze = Maze(portsPerEdge: 4, radius: 2)
        maze = try #require(maze.placing(PlacedTile(onDead), at: .origin))
        #expect(generator.fill(&maze, symmetry: .none, using: &random))
        #expect(maze.isSealed)
    }
}
