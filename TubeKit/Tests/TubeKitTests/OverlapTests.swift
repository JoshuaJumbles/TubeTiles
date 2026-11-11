import Testing
@testable import TubeKit

private func port(_ edge: Int, _ slot: Int) -> Port { Port(edge: edge, slot: slot) }

/// A small deterministic generator so random fills are repeatable.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

@Suite struct PipeShapeTests {
    let style = TileStyle(portsPerEdge: 6)

    @Test func shapesStartAndEndOnTheirPorts() {
        for kind in PipeKind.throughKinds {
            let pipe = Pipe(kind, a: port(0, 1), b: port(2, 4))
            let shape = PipeShape(pipe, style: style)
            let points = shape.segments.flatMap { $0.flattened() }
            #expect(points.first!.distance(to: HexGeometry.position(of: pipe.a, portsPerEdge: 6)) < 1e-9)
            #expect(points.last!.distance(to: HexGeometry.position(of: pipe.b, portsPerEdge: 6)) < 1e-9)
        }
    }

    @Test func cornerBendsWhereThePortsLookAtEachOther() {
        let bent = PipeShape(Pipe(.corner, a: port(0, 1), b: port(2, 4)), style: style)
        #expect(bent.segments.count == 2)
        #expect(bent.elbow != nil)

        let straight = PipeShape(Pipe(.corner, a: port(0, 1), b: port(3, 4)), style: style)
        #expect(straight.segments.count == 1)
        #expect(straight.elbow == nil)
    }

    @Test func roomsGrowWithSize() {
        let sizes = [PipeKind.roomSmall, .roomMedium, .roomLarge].map {
            PipeShape(Pipe($0, a: port(0, 2), b: port(2, 2)), style: style).room!.diameter
        }
        #expect(sizes == sizes.sorted())
        #expect(sizes[0] > style.pipeWidth)
    }

    @Test func aRoomStraightAcrossSitsInTheMiddle() {
        let shape = PipeShape(Pipe(.roomSmall, a: port(0, 2), b: port(3, 3)), style: style)
        let a = HexGeometry.position(of: port(0, 2), portsPerEdge: 6)
        let b = HexGeometry.position(of: port(3, 3), portsPerEdge: 6)
        #expect(shape.room!.center.distance(to: (a + b) * 0.5) < 1e-9)
    }
}

@Suite struct OverlapTests {
    @Test func anEmptyTileHasNoViolations() {
        #expect(!CoverageMap(style: TileStyle(portsPerEdge: 6)).hasViolation)
    }

    @Test func twoPipesMayCross() throws {
        var tile = Tile(portsPerEdge: 6)
        try tile.add(Pipe(.corner, a: port(0, 2), b: port(3, 3)))
        try tile.add(Pipe(.bezier, a: port(1, 2), b: port(4, 3)))
        #expect(tile.pipes.count == 2)
    }

    /// Three straight pipes through the middle all meet at one point.
    @Test func threePipesMayNotCrossAtOnePoint() throws {
        var tile = Tile(portsPerEdge: 5)
        try tile.add(Pipe(.corner, a: port(0, 2), b: port(3, 2)))
        try tile.add(Pipe(.corner, a: port(1, 2), b: port(4, 2)))
        #expect(throws: PlacementError.overlap) {
            try tile.add(Pipe(.corner, a: port(2, 2), b: port(5, 2)))
        }
        #expect(!CoverageMap(tile: tile).conflicts(adding: Pipe(.corner, a: port(2, 2), b: port(5, 2))).isEmpty)
    }

    /// The same three directions, shifted so they cross in pairs, are fine.
    @Test func threePipesMayCrossInPairs() throws {
        var tile = Tile(portsPerEdge: 5)
        try tile.add(Pipe(.corner, a: port(0, 0), b: port(3, 4)))
        try tile.add(Pipe(.corner, a: port(1, 0), b: port(4, 4)))
        try tile.add(Pipe(.corner, a: port(2, 0), b: port(5, 4)))
        #expect(tile.pipes.count == 3)
    }

    @Test func nothingCrossesARoom() throws {
        var tile = Tile(portsPerEdge: 5)
        try tile.add(Pipe(.roomMedium, a: port(0, 2), b: port(3, 2)))
        #expect(throws: PlacementError.overlap) {
            try tile.add(Pipe(.corner, a: port(1, 2), b: port(4, 2)))
        }
    }

    @Test func nothingCrossesACornerBend() throws {
        var tile = Tile(portsPerEdge: 5)
        // Bends at the centre of the tile.
        try tile.add(Pipe(.corner, a: port(0, 2), b: port(2, 2)))
        #expect(throws: PlacementError.overlap) {
            try tile.add(Pipe(.corner, a: port(1, 2), b: port(4, 2)))
        }
    }

    @Test func parallelNeighboursDoNotCollide() throws {
        var tile = Tile(portsPerEdge: 6)
        for slot in 0..<6 {
            try tile.add(Pipe(.corner, a: port(0, slot), b: port(3, 5 - slot)))
        }
        #expect(tile.pipes.count == 6)
    }

    /// Mirroring and half turns map the sampling grid onto itself, so a
    /// valid tile stays exactly valid. Sixth turns do not, so a tightly
    /// packed tile may pick up a handful of cells; this keeps that small.
    @Test func coverageSurvivesPlacement() {
        for seed in 0..<6 {
            var generator = SeededGenerator(seed: UInt64(seed))
            var tile = Tile(portsPerEdge: 5)
            tile.fillRandomly(using: &generator)
            for transform in TileTransform.allCases {
                let stray = CoverageMap(tile: tile.transformed(by: transform)).violationCount
                if transform.turns % 3 == 0 {
                    #expect(stray == 0)
                } else {
                    #expect(stray < 10)
                }
            }
        }
    }
}

@Suite struct RandomFillTests {
    @Test(arguments: [3, 4, 5, 6])
    func fillsProduceValidTiles(portsPerEdge: Int) throws {
        for seed in 0..<8 {
            var generator = SeededGenerator(seed: UInt64(seed))
            var tile = Tile(portsPerEdge: portsPerEdge)
            let added = tile.fillRandomly(using: &generator)
            #expect(added > 0)
            #expect(added == tile.pipes.count)
            // Rebuilding through the checked initialiser proves every pipe is legal.
            let rebuilt = try Tile(portsPerEdge: portsPerEdge, pipes: tile.pipes)
            #expect(rebuilt.pipes == tile.pipes)
        }
    }

    @Test func sameSeedGivesTheSameTile() {
        var first = SeededGenerator(seed: 42)
        var second = SeededGenerator(seed: 42)
        var a = Tile(portsPerEdge: 6)
        var b = Tile(portsPerEdge: 6)
        a.fillRandomly(using: &first)
        b.fillRandomly(using: &second)
        #expect(a.pipes == b.pipes)
    }
}

@Suite struct TileLibraryTests {
    @Test func savingReplacesByIdentity() throws {
        var library = TileLibrary(name: "Test", portsPerEdge: 4)
        var tile = Tile(portsPerEdge: 4)
        try tile.add(Pipe(.bezier, a: port(0, 0), b: port(2, 3)))
        library.save(tile)
        try tile.add(Pipe(.bezier, a: port(1, 0), b: port(4, 3)))
        library.save(tile)
        #expect(library.tiles.count == 1)
        #expect(library.tiles[0].pipes.count == 2)

        var other = Tile(portsPerEdge: 4)
        try other.add(Pipe(.corner, a: port(0, 0), b: port(2, 3)))
        try other.add(Pipe(.corner, a: port(1, 0), b: port(4, 3)))
        library.save(other)
        #expect(library.tilesByEdgeCode.count == 1)
        #expect(library.tilesByEdgeCode[tile.edgeCode]?.count == 2)

        library.remove(id: tile.id)
        #expect(library.tiles.map(\.id) == [other.id])
    }

    @Test func profilesGroupTurnedAndFlippedTiles() throws {
        var library = TileLibrary(name: "Test", portsPerEdge: 4)
        var tile = Tile(portsPerEdge: 4)
        try tile.add(Pipe(.bezier, a: port(0, 0), b: port(2, 3)))
        try tile.add(Pipe(.bezier, a: port(1, 1), b: port(4, 2)))
        library.save(tile)
        for transform in [TileTransform(turns: 2), TileTransform(turns: 5, mirrored: true)] {
            var copy = Tile(portsPerEdge: 4)
            for pipe in tile.transformed(by: transform).pipes {
                try copy.add(pipe)
            }
            library.save(copy)
        }
        #expect(library.tilesByEdgeCode.count == 3)
        #expect(library.tilesByProfile.count == 1)
        #expect(library.tilesByProfile[tile.edgeCode.canonical]?.count == 3)
    }

    @Test func canonicalCodeIsTheSameForEveryPlacement() {
        var generator = SeededGenerator(seed: 11)
        var tile = Tile(portsPerEdge: 5)
        tile.fillRandomly(using: &generator)
        let canonical = tile.edgeCode.canonical
        for transform in TileTransform.allCases {
            #expect(tile.edgeCode.transformed(by: transform).canonical == canonical)
        }
    }

    @Test func edgePatterns() throws {
        #expect(EdgeCode.allPatterns(portsPerEdge: 6).count == 36)
        #expect(EdgeCode.allPatterns(portsPerEdge: 3) == [0, 1, 2, 3, 5, 7])
        #expect(EdgeCode.pattern(0b100, width: 3) == 0b001)

        var library = TileLibrary(name: "Test", portsPerEdge: 3)
        var tile = Tile(portsPerEdge: 3)
        // Edge 0 shows 100, edge 2 shows 001: the same pattern, counted once.
        try tile.add(Pipe(.bezier, a: port(0, 0), b: port(2, 2)))
        library.save(tile)
        #expect(library.edgePatternCounts == [0: 1, 1: 1])
    }
}
