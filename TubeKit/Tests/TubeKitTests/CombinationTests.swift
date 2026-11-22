import Testing
@testable import TubeKit

/// Saving every combination of a tile's pipes.
@Suite struct CombinationTests {
    private func port(_ edge: Int, _ slot: Int) -> TubeKit.Port { TubeKit.Port(edge: edge, slot: slot) }

    /// Three pipes on a hexagon that no turn or flip maps onto each other.
    private func threePipes() throws -> Tile {
        try Tile(portsPerEdge: 4, pipes: [
            // Each curls round a different corner, each a little differently.
            Pipe(.bezier, a: port(0, 3), b: port(1, 0)),
            Pipe(.bezier, a: port(2, 2), b: port(3, 0)),
            Pipe(.bezier, a: port(4, 3), b: port(5, 2)),
        ])
    }

    @Test func threePipesMakeThreePairs() throws {
        let tile = try threePipes()
        let library = TileLibrary(name: "L", portsPerEdge: 4)
        let found = try #require(library.combinations(of: tile))
        // AB, AC and BC. Single pipes are left out, and so is ABC itself.
        #expect(found.distinct == 3)
        #expect(found.alreadyThere == 0)
        #expect(found.tiles.count == 3)
        #expect(found.tiles.allSatisfy { $0.pipes.count == 2 })
        #expect(Set(found.tiles.map(\.id)).count == 3)
        #expect(!found.tiles.map(\.id).contains(tile.id))
        for made in found.tiles {
            #expect(made.pipes.allSatisfy(tile.pipes.contains))
            #expect(!CoverageMap(tile: made).hasViolation)
            #expect(made.shape == tile.shape && made.portsPerEdge == 4)
        }
        // With single pipes let in there are three more.
        #expect(library.combinations(of: tile, minimumPipes: 1)?.tiles.count == 6)
    }

    @Test func combinationsTheLibraryHasAreLeftOut() throws {
        let tile = try threePipes()
        var library = TileLibrary(name: "L", portsPerEdge: 4)
        // The first two pipes, saved turned and flipped.
        let pair = try Tile(portsPerEdge: 4, pipes: Array(tile.pipes.prefix(2)))
        library.save(Tile(
            portsPerEdge: 4,
            uncheckedPipes: pair.transformed(by: TileTransform(turns: 2, mirrored: true)).pipes
        ))
        let found = try #require(library.combinations(of: tile))
        #expect(found.distinct == 3)
        #expect(found.alreadyThere == 1)
        #expect(found.tiles.count == 2)
        let twins = found.tiles.filter { library.twin(of: $0) != nil }
        #expect(twins.isEmpty)

        // Saving them all leaves nothing to add the second time.
        for made in found.tiles { library.save(made) }
        let again = try #require(library.combinations(of: tile))
        #expect(again.tiles.isEmpty)
        #expect(again.alreadyThere == 3)
    }

    @Test func combinationsThatAreCopiesOfEachOtherCountOnce() throws {
        // The same curve on three edges of a hexagon, a third of a turn
        // apart: every pair is the same tile turned.
        let curve = Pipe(.bezier, a: port(0, 1), b: port(1, 1))
        let third = TileTransform(turns: 2)
        let pipes = [curve, third.apply(to: curve, portsPerEdge: 3), third.then(third).apply(to: curve, portsPerEdge: 3)]
        let tile = try Tile(portsPerEdge: 3, pipes: pipes)
        let found = try #require(TileLibrary(name: "L", portsPerEdge: 3).combinations(of: tile))
        #expect(found.distinct == 1)
        #expect(found.tiles.count == 1)
    }

    @Test func theTileBeingSavedDoesNotCountAgainstItsOwnCombinations() throws {
        // Saved with two pipes, then given a third: the two-pipe tile in
        // the library is about to be replaced, so that pair is still new.
        var tile = try Tile(portsPerEdge: 4, pipes: Array(try threePipes().pipes.prefix(2)))
        var library = TileLibrary(name: "L", portsPerEdge: 4)
        library.save(tile)
        try tile.add(try threePipes().pipes[2])
        let found = try #require(library.combinations(of: tile))
        #expect(found.alreadyThere == 0)
        #expect(found.tiles.count == 3)
    }

    @Test func tooFewOrTooManyPipes() throws {
        let library = TileLibrary(name: "L", portsPerEdge: 6)
        // Two pipes have no combination of two that leaves one out.
        let two = try Tile(portsPerEdge: 6, pipes: [
            Pipe(.bezier, a: port(0, 0), b: port(1, 1)), Pipe(.bezier, a: port(2, 0), b: port(4, 3)),
        ])
        #expect(library.combinations(of: two)?.tiles.isEmpty == true)
        #expect(library.combinations(of: Tile(portsPerEdge: 6))?.tiles.isEmpty == true)

        // Thirteen pipes are over the limit. They need not make a sound
        // tile to be counted.
        let many = (0..<13).map { Pipe(.bezier, a: port($0 % 6, $0 / 6), b: port(($0 + 3) % 6, 3 + $0 / 6)) }
        #expect(Set(many.flatMap(\.ports)).count == 26)
        #expect(library.combinations(of: Tile(portsPerEdge: 6, uncheckedPipes: many)) == nil)
        let twelve = Tile(portsPerEdge: 6, uncheckedPipes: Array(many.prefix(12)))
        let found = try #require(library.combinations(of: twelve))
        // Every way of keeping two to eleven of twelve, less copies.
        #expect(found.distinct <= 4095 - 12 - 1)
        #expect(found.distinct > 300)

        // The wrong port count or shape.
        #expect(library.combinations(of: Tile(portsPerEdge: 4)) == nil)
        #expect(library.combinations(of: Tile(portsPerEdge: 6, shape: .square)) == nil)
    }

    @Test func combinationsKeepToTheTilesShape() throws {
        var library = TileLibrary(name: "Both", portsPerEdge: 3, shapes: [.octagon, .square])
        let pipes = [
            Pipe(.bezier, a: port(0, 0), b: port(1, 0)),
            Pipe(.bezier, a: port(2, 1), b: port(3, 1)),
            Pipe(.bezier, a: port(0, 2), b: port(2, 2)),
        ]
        let square = try Tile(portsPerEdge: 3, shape: .square, pipes: pipes)
        // The same pairs on an octagon are different tiles and do not get
        // in the way.
        let octagon = try Tile(portsPerEdge: 3, shape: .octagon, pipes: Array(pipes.prefix(2)))
        library.save(octagon)
        let found = try #require(library.combinations(of: square))
        #expect(found.alreadyThere == 0)
        #expect(found.tiles.allSatisfy { $0.shape == .square })
    }
}
