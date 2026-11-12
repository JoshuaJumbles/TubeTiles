import Testing
@testable import TubeKit

private func port(_ edge: Int, _ slot: Int) -> TubeKit.Port { TubeKit.Port(edge: edge, slot: slot) }

@Suite struct TileBriefTests {
    /// A straight pipe down the middle column, with the middle cell empty.
    private func mazeWithGap() throws -> Maze {
        let straight = try Tile(portsPerEdge: 3, pipes: [Pipe(.corner, a: port(0, 1), b: port(3, 1))])
        var maze = Maze(portsPerEdge: 3, radius: 2)
        for r in [-1, 1] {
            maze = try #require(maze.placing(PlacedTile(straight), at: HexCoord(q: 0, r: r)))
        }
        return maze
    }

    @Test func aGapAsksForWhatItsNeighboursShow() throws {
        let maze = try mazeWithGap()
        let brief = try #require(maze.brief(at: .origin))
        // The tiles above and below each send one pipe in; the other four
        // neighbours are empty, so those edges are free.
        #expect(brief.mustUse == [port(0, 1), port(3, 1)])
        #expect(brief.mustAvoid == [port(0, 0), port(0, 2), port(3, 0), port(3, 2)])
        #expect(brief.required.filter { $0 == nil }.count == 4)
        #expect(!brief.needsDeadEnd)
    }

    @Test func aTileMeetsTheBriefExactlyWhenItCanBePlaced() throws {
        let maze = try mazeWithGap()
        let brief = try #require(maze.brief(at: .origin))

        let fits = try Tile(portsPerEdge: 3, pipes: [Pipe(.bezier, a: port(0, 1), b: port(3, 1))])
        #expect(brief.isMet(by: fits))
        #expect(maze.placing(PlacedTile(fits), at: .origin) != nil)

        // Extra pipes on the free edges are welcome.
        var more = fits
        try more.add(Pipe(.bezier, a: port(1, 1), b: port(2, 1)))
        #expect(brief.isMet(by: more))
        #expect(maze.placing(PlacedTile(more), at: .origin) != nil)

        let half = try Tile(portsPerEdge: 3, pipes: [Pipe(.bezier, a: port(0, 1), b: port(1, 1))])
        #expect(!brief.isMet(by: half))
        #expect(brief.missing(in: half) == [port(3, 1)])
        #expect(maze.placing(PlacedTile(half), at: .origin) == nil)

        let wrong = try Tile(portsPerEdge: 3, pipes: [Pipe(.bezier, a: port(0, 0), b: port(3, 1))])
        #expect(!brief.isMet(by: wrong))
        #expect(brief.unwanted(in: wrong) == [port(0, 0)])
        #expect(brief.missing(in: wrong) == [port(0, 1)])

        #expect(!brief.isMet(by: Tile(portsPerEdge: 3)))
    }

    @Test func theOutlineMustStayClosedExceptAtOpenings() throws {
        var maze = Maze(portsPerEdge: 3, radius: 1)
        let corner = HexCoord(q: 0, r: -1)
        let before = try #require(maze.brief(at: corner))
        // Three edges of this cell face outside and take no pipes.
        #expect(before.required.filter { $0 == 0 }.count == 3)
        #expect(before.mustUse.isEmpty)

        let opening = try #require(maze.outlinePorts.first { $0.coord == corner })
        maze.setOpenings([opening])
        let after = try #require(maze.brief(at: corner))
        #expect(after.mustUse == [opening.port])
    }

    @Test func aGoalAsksForOneDeadEnd() throws {
        var maze = Maze(portsPerEdge: 3, radius: 1)
        maze.setGoals([.origin])
        let brief = try #require(maze.brief(at: .origin))
        #expect(brief.needsDeadEnd)
        let through = try Tile(portsPerEdge: 3, pipes: [Pipe(.bezier, a: port(0, 1), b: port(3, 1))])
        #expect(!brief.isMet(by: through))
        let ending = try Tile(portsPerEdge: 3, pipes: [Pipe(.endSmall, at: port(0, 1))])
        #expect(brief.isMet(by: ending))
        #expect(maze.brief(at: HexCoord(q: 5, r: 5)) == nil)
    }

    @Test func aFilledCellIsBriefedAsIfEmpty() throws {
        var maze = try mazeWithGap()
        let empty = try #require(maze.brief(at: .origin))
        let fits = try Tile(portsPerEdge: 3, pipes: [Pipe(.bezier, a: port(0, 1), b: port(3, 1))])
        maze = try #require(maze.placing(PlacedTile(fits), at: .origin))
        #expect(maze.brief(at: .origin) == empty)
    }
}
