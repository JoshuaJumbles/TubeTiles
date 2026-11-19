import Foundation
import Testing
@testable import TubeKit

private func close(_ a: Point, _ b: Point) -> Bool { a.distance(to: b) < 1e-9 }

/// Things that have to hold for any shape and any tiling.
@Suite struct ShapeAndTilingTests {
    @Test(arguments: TileShape.allCases)
    func edgesAreOneUnitLongAndFaceInwards(shape: TileShape) {
        #expect(shape.corners.count == shape.edgeCount)
        for edge in 0..<shape.edgeCount {
            let start = shape.corner(edge)
            let end = shape.corner(edge + 1)
            #expect(abs(start.distance(to: end) - 1) < 1e-9)
            let inward = shape.inwardDirection(edge: edge)
            let along = end - start
            #expect(abs(inward.x * along.x + inward.y * along.y) < 1e-9)
            // Stepping in from the middle of the edge lands inside.
            let middle = (start + end) * 0.5
            #expect(shape.contains(middle + inward * 0.1))
            #expect(!shape.contains(middle + inward * -0.1))
            // No edge comes closer to the centre than the inradius.
            let offset = Point.zero - start
            #expect(offset.x * inward.x + offset.y * inward.y >= shape.inradius - 1e-9)
            if shape.isRegular { #expect(abs(middle.distance(to: .zero) - shape.inradius) < 1e-9) }
        }
        #expect(shape.contains(.zero))
        #expect(shape.corners.allSatisfy { $0.distance(to: .zero) <= shape.circumradius + 1e-9 })
        // A regular shape can be turned to any edge and flipped; an
        // irregular one has fewer ways to sit.
        #expect(shape.transforms.first?.isIdentity == true)
        #expect(Set(shape.transforms).count == shape.transforms.count)
        #expect(shape.transforms.count == (shape.isRegular ? shape.edgeCount * 2 : 2))
        // Each placement puts the outline back on itself.
        for transform in shape.transforms {
            let moved = shape.corners.map { transform.apply(to: $0) }
            #expect(moved.allSatisfy { point in shape.corners.contains { close($0, point) } })
        }
    }

    @Test(arguments: TileShape.allCases)
    func placementsMoveAPortToWhereItsPointGoes(shape: TileShape) {
        for ports in [1, 3, 4] {
            for transform in shape.transforms {
                for port in shape.ports(portsPerEdge: ports) {
                    let moved = transform.apply(to: port, portsPerEdge: ports)
                    #expect(shape.isValid(moved, portsPerEdge: ports))
                    #expect(close(
                        shape.position(of: moved, portsPerEdge: ports),
                        transform.apply(to: shape.position(of: port, portsPerEdge: ports))
                    ))
                    #expect(transform.inverse.apply(to: moved, portsPerEdge: ports) == port)
                }
                for other in shape.transforms {
                    let both = transform.then(other)
                    #expect(both.sides == shape.edgeCount)
                    for port in shape.ports(portsPerEdge: ports) {
                        #expect(both.apply(to: port, portsPerEdge: ports)
                            == other.apply(to: transform.apply(to: port, portsPerEdge: ports), portsPerEdge: ports))
                    }
                }
            }
        }
    }

    @Test(arguments: Tiling.allCases)
    func neighboursMeetAlongAWholeEdge(tiling: Tiling) {
        // A shape names the tiling made of it alone, or the first it was added for.
        for shape in tiling.shapes { #expect(Tiling(shape: shape).shapes.contains(shape)) }
        for cell in tiling.cells(radius: 2) {
            let shape = tiling.shape(of: cell)
            for edge in 0..<shape.edgeCount {
                let other = tiling.neighbour(of: cell, across: edge)
                #expect(other.cell != cell)
                // Going back across the same edge returns to the start.
                let back = tiling.neighbour(of: other.cell, across: other.edge)
                #expect(back.cell == cell)
                #expect(back.edge == edge)
                // Touching ports sit on the same spot.
                for slot in 0..<3 {
                    let port = TubeKit.Port(edge: edge, slot: slot)
                    let twin = tiling.touching(port, of: cell, portsPerEdge: 3)
                    #expect(close(
                        tiling.frame(of: cell).place(shape.position(of: port, portsPerEdge: 3)),
                        tiling.frame(of: twin.coord)
                            .place(tiling.shape(of: twin.coord).position(of: twin.port, portsPerEdge: 3))
                    ))
                }
            }
        }
    }

    @Test(arguments: Tiling.allCases)
    func regionsAreCentredAndCounted(tiling: Tiling) {
        for radius in 0...4 {
            let cells = tiling.cells(radius: radius)
            #expect(cells.count == tiling.cellCount(radius: radius))
            #expect(Set(cells).count == cells.count)
            #expect(cells.contains(.origin))
            // The region just fits its stated extent.
            let extent = tiling.extent(radius: radius)
            var width = 0.0
            var height = 0.0
            for cell in cells {
                for corner in tiling.shape(of: cell).corners {
                    let point = tiling.frame(of: cell).place(corner)
                    width = max(width, abs(point.x) * 2)
                    height = max(height, abs(point.y) * 2)
                }
            }
            #expect(abs(width - extent.width) < 1e-9)
            #expect(abs(height - extent.height) < 1e-9)
            #expect(tiling.radius(covering: (Point(x: -width / 2, y: -height / 2), Point(x: width / 2, y: height / 2)), limit: 20) >= radius)
        }
        #expect(tiling.columns(inWidth: tiling.width(ofColumns: 7)) == 7)
    }

    @Test(arguments: Tiling.allCases)
    func gridSymmetriesMoveCellsLikeTheirPoints(tiling: Tiling) {
        #expect(tiling.symmetries.first == Symmetry.none)
        for symmetry in Symmetry.allCases {
            let transforms = tiling.transforms(for: symmetry)
            #expect(transforms.first?.isIdentity == true)
            // A symmetry the grid cannot keep falls back to none.
            if !tiling.symmetries.contains(symmetry) { #expect(transforms.count == 1) }
            for transform in transforms {
                for cell in tiling.cells(radius: 3) {
                    let moved = tiling.transformed(cell, by: transform)
                    #expect(close(tiling.center(of: moved), transform.apply(to: tiling.center(of: cell))))
                    #expect(tiling.ring(of: moved) == tiling.ring(of: cell))
                }
            }
            // A tile is turned through its own number of sides.
            let sides = tiling.images(of: .origin, under: symmetry).map(\.tile.sides)
            #expect(sides.allSatisfy { $0 == tiling.shape(of: .origin).edgeCount })
            // Where the centre of the grid is a cell, every symmetry maps
            // that cell onto itself. On Cairo tiles the centre is a corner,
            // and no cell is mapped onto itself.
            let fixed = tiling.stabilizer(of: .origin, symmetry: symmetry).count
            #expect(fixed == (tiling == .cairo ? 0 : transforms.count - 1))
        }
    }
}

@Suite struct SquareTileTests {
    private func port(_ edge: Int, _ slot: Int) -> TubeKit.Port { TubeKit.Port(edge: edge, slot: slot) }

    @Test func aSquareTileFollowsTheSameRules() throws {
        var tile = Tile(portsPerEdge: 3, shape: .square)
        #expect(tile.freePorts.count == 12)
        #expect(tile.edgeCode.values == [0, 0, 0, 0])
        // Straight down the middle, top to bottom.
        try tile.add(Pipe(.corner, a: port(0, 1), b: port(2, 1)))
        // Across, left to right, crossing it.
        try tile.add(Pipe(.bezier, a: port(3, 1), b: port(1, 1)))
        #expect(tile.edgeCode.values == [2, 2, 2, 2])
        #expect(!CoverageMap(tile: tile).hasViolation)
        // There is no fifth edge.
        var copy = tile
        let fifthEdge: Void? = try? copy.add(Pipe(.bezier, a: port(4, 0), b: port(0, 0)))
        #expect(fifthEdge == nil)
        // Across the tile, a corner pipe only runs straight.
        let slanted: Void? = try? copy.add(Pipe(.corner, a: port(0, 0), b: port(2, 0)))
        #expect(slanted == nil)
        #expect(copy == tile)
        // Every pipe stays inside the square.
        for pipe in tile.pipes {
            for segment in PipeShape(pipe, style: tile.style).segments {
                #expect(segment.flattened().allSatisfy { abs($0.x) <= 0.5 + 1e-9 && abs($0.y) <= 0.5 + 1e-9 })
            }
        }
        let loaded = try JSONDecoder().decode(Tile.self, from: JSONEncoder().encode(tile))
        #expect(loaded == tile)
        #expect(loaded.shape == .square)
    }

    @Test func aSquareHasEightPlacements() throws {
        let tile = try Tile(portsPerEdge: 3, shape: .square, pipes: [Pipe(.bezier, a: port(0, 0), b: port(1, 1))])
        let placements = Set(TileShape.square.transforms.map { Set(tile.transformed(by: $0).pipes) })
        #expect(placements.count == 8)
        #expect(tile.edgeCode.canonical == tile.transformed(by: TileTransform(turns: 3, mirrored: true, sides: 4)).edgeCode.canonical)
        // "As it is" for a hexagon still means as it is for a square.
        #expect(PlacedTile(tile).transform.sides == 4)
        #expect(PlacedTile(tile).oriented.pipes == tile.pipes)
    }

    @Test func aLibraryHoldsOneShape() throws {
        var squares = TileLibrary(name: "Squares", portsPerEdge: 3, deadSlots: [0], shapes: [.square])
        #expect(squares.deadPorts.count == 8)
        var random = SeededGenerator(seed: 3)
        for _ in 0..<6 {
            var tile = Tile(portsPerEdge: 3, shape: .square)
            tile.fillRandomly(using: &random)
            squares.save(tile)
        }
        #expect(squares.tiles.allSatisfy { $0.shape == .square && !CoverageMap(tile: $0).hasViolation })
        let loaded = try JSONDecoder().decode(TileLibrary.self, from: JSONEncoder().encode(squares))
        #expect(loaded == squares)
        // A tile of this library, turned, is recognised.
        let first = squares.tiles[0]
        let turned = Tile(portsPerEdge: 3, shape: .square, uncheckedPipes: first.transformed(by: TileTransform(turns: 1, sides: 4)).pipes)
        #expect(squares.twin(of: turned)?.tile.id == first.id)
        // Libraries of different shapes do not mix.
        var hexes = TileLibrary(name: "Hexes", portsPerEdge: 3)
        #expect(hexes.merge(squares).added == 0)
    }
}

@Suite struct SquareMazeTests {
    private func staysInside(_ maze: Maze) -> Bool {
        guard let mask = maze.mask else { return true }
        for (coord, placed) in maze.cells {
            for pipe in placed.oriented.pipes {
                for segment in PipeShape(pipe, style: maze.style(at: coord)).segments {
                    for point in segment.flattened(steps: 30)
                    where !mask.contains(maze.center(of: coord) + point, inset: maze.style.pipeWidth / 2 - 0.02) {
                        return false
                    }
                }
            }
        }
        return true
    }

    @Test(arguments: [Symmetry.none, .mirror, .half, .quarter])
    func squareMazesSealAndKeepTheirSymmetry(symmetry: Symmetry) throws {
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6))
        var sealed = 0
        for seed in 0..<5 {
            var maze = Maze(portsPerEdge: 4, radius: 3, tiling: .square)
            #expect(maze.cellCount == 49)
            var random = SeededGenerator(seed: UInt64(seed))
            if generator.fill(&maze, symmetry: symmetry, using: &random) { sealed += 1 }
            for (coord, placed) in maze.cells {
                #expect(placed.source.shape == .square)
                #expect(placed.code.values.count == 4)
                #expect(maze.fits(placed.code, at: coord))
                #expect(!CoverageMap(tile: placed.source).hasViolation)
                // Each image of a cell holds the image of its tile.
                for transform in maze.tiling.transforms(for: symmetry) {
                    let image = try #require(maze.cells[maze.tiling.transformed(coord, by: transform)])
                    #expect(image.looksLike(placed.transformed(by: transform)))
                }
            }
            guard maze.isSealed else { continue }
            // Every pipe leads somewhere: no path just stops.
            let allClosed = maze.paths.paths.allSatisfy { $0.isClosed }
            #expect(allClosed)
            let before = maze.paths.paths.count
            LoopMerger(generator: generator).mergeAll(&maze, symmetry: symmetry, using: &random)
            #expect(maze.isSealed)
            #expect(maze.paths.paths.count <= before)
            #expect(maze.weave().conflicts == 0)
            let loaded = try JSONDecoder().decode(Maze.self, from: JSONEncoder().encode(maze))
            #expect(loaded == maze)
            #expect(loaded.tiling == .square)
        }
        #expect(sealed >= 4)
    }

    @Test func squareMazesReduceToFewPaths() {
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6))
        var single = 0
        for seed in 0..<6 {
            var maze = Maze(portsPerEdge: 3, radius: 3, tiling: .square)
            var random = SeededGenerator(seed: UInt64(seed))
            generator.fill(&maze, symmetry: .none, using: &random)
            LoopMerger(generator: generator).mergeAll(&maze, using: &random)
            if maze.paths.paths.count == 1 { single += 1 }
        }
        #expect(single >= 3)
    }

    @Test func aBoundedSquareMazeStaysInside() {
        let mask = Mask.rectangle(center: Point(x: 0.3, y: 0), width: 6.4, height: 4.7)
        let radius = Maze.radius(covering: mask, limit: 12, tiling: .square)
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6))
        var sealed = 0
        for seed in 0..<5 {
            var maze = Maze(portsPerEdge: 3, radius: radius, mask: mask, tiling: .square)
            #expect(maze.cellCount > 12)
            var random = SeededGenerator(seed: UInt64(seed))
            if generator.fill(&maze, symmetry: .none, using: &random) { sealed += 1 }
            #expect(staysInside(maze))
            #expect(!maze.cells.isEmpty)
        }
        #expect(sealed >= 4)
    }

    @Test func goalsOpeningsAndTheLibraryWorkOnSquares() throws {
        var random = SeededGenerator(seed: 12)
        var library: [Tile] = []
        // Sparse tiles, one to three pipes each, so plenty of them fit.
        while library.count < 60 {
            var tile = Tile(portsPerEdge: 3, shape: .square)
            for _ in 0..<(1 + library.count % 3) {
                tile.addRandomPipe(kinds: [.bezier, .corner], using: &random)
            }
            if !tile.pipes.isEmpty { library.append(tile) }
        }
        let generator = MazeGenerator(tiles: library, synthesis: .init(growth: 0.5))
        #expect(!generator.options.isEmpty)
        #expect(generator.options.allSatisfy { $0.transform.sides == 4 })

        var maze = Maze(portsPerEdge: 3, radius: 2, tiling: .square)
        // An entrance at the top and a goal in the middle.
        let entrance = PortRef(coord: HexCoord(q: 0, r: -2), port: TubeKit.Port(edge: 0, slot: 1))
        #expect(maze.isOnOutline(entrance))
        #expect(maze.outlinePorts.count == 5 * 4 * 3)
        maze.setOpenings([entrance])
        maze.setGoals([.origin])
        #expect(generator.fill(&maze, symmetry: .none, using: &random))
        #expect(maze.cells.values.contains { !$0.isGenerated })
        let open = maze.paths.paths.filter { !$0.isClosed }
        #expect(open.count == 1)

        let sheet = BuildSheet(maze: maze)
        #expect(sheet.tileCount == maze.cells.count)
        for (coord, placed) in maze.cells {
            let placement = try #require(sheet.placements[coord])
            let rebuilt = sheet.entries[placement.entry].tile.transformed(by: placement.transform)
            #expect(Set(rebuilt.pipes) == Set(placed.oriented.pipes))
        }
        #expect(MazeSVG.render(maze).contains("<polygon"))
        let brief = try #require(maze.brief(at: HexCoord(q: 2, r: 2)))
        #expect(brief.required.count == 4)
    }
}

@Suite struct CairoTests {
    private func port(_ edge: Int, _ slot: Int) -> TubeKit.Port { TubeKit.Port(edge: edge, slot: slot) }

    /// Every point a maze's pipes are drawn through, in the plane.
    private func ink(of maze: Maze) -> [(point: Point, reach: Double)] {
        var result: [(Point, Double)] = []
        for (coord, placed) in maze.cells {
            let style = maze.style(at: coord)
            let frame = maze.frame(of: coord)
            for pipe in placed.oriented.pipes {
                let shape = PipeShape(pipe, style: style)
                for segment in shape.segments {
                    for point in segment.flattened(steps: 30) { result.append((frame.place(point), style.pipeWidth / 2)) }
                }
                if let room = shape.room { result.append((frame.place(room.center), room.diameter / 2)) }
            }
        }
        return result
    }

    @Test func thePentagonHasTwoRightAnglesAndPointsFourWays() {
        let shape = TileShape.cairo
        func angle(at index: Int) -> Double {
            let here = shape.corner(index)
            let before = shape.corner(index + 4) - here
            let after = shape.corner(index + 1) - here
            let cosine = (before.x * after.x + before.y * after.y)
            return acos(max(-1, min(1, cosine))) * 180 / .pi
        }
        let angles = (0..<5).map(angle)
        #expect(abs(angles[2] - 90) < 1e-6)
        #expect(abs(angles[4] - 90) < 1e-6)
        #expect(abs(angles[0] - angles[1]) < 1e-6)
        #expect(abs(angles.reduce(0, +) - 540) < 1e-6)
        #expect(angles[3] > 131 && angles[3] < 132)

        // The four cells nearest the middle each point a different way.
        let tiling = Tiling.cairo
        let turns = Set(tiling.cells(radius: 1).map { Int((tiling.turn(of: $0) / (.pi / 2)).rounded()) })
        #expect(turns == [0, 1, 2, 3])
        #expect(tiling.cells(radius: 0).count == 8)
    }

    @Test func pipesStayInsideThePentagon() throws {
        var random = SeededGenerator(seed: 5)
        var pipes = 0
        for _ in 0..<40 {
            var tile = Tile(portsPerEdge: 4, shape: .cairo)
            tile.fillRandomly(using: &random)
            #expect(!CoverageMap(tile: tile).hasViolation)
            #expect(tile.edgeCode.values.count == 5)
            pipes += tile.pipes.count
            for pipe in tile.pipes {
                let shape = PipeShape(pipe, style: tile.style)
                for segment in shape.segments {
                    for point in segment.flattened(steps: 30) {
                        // Allow for the slight bulge of a curve near an edge.
                        let inside = TileShape.cairo.corners.indices.allSatisfy { edge in
                            let offset = point - TileShape.cairo.corner(edge)
                            let inward = TileShape.cairo.inwardDirection(edge: edge)
                            return offset.x * inward.x + offset.y * inward.y > -0.02
                        }
                        #expect(inside)
                    }
                }
            }
            let loaded = try JSONDecoder().decode(Tile.self, from: JSONEncoder().encode(tile))
            #expect(loaded == tile)
        }
        #expect(pipes > 120)
    }

    @Test func aPentagonSitsTwoWays() throws {
        let tile = try Tile(portsPerEdge: 3, shape: .cairo, pipes: [
            Pipe(.bezier, a: port(0, 0), b: port(2, 1)),
            Pipe(.bezier, a: port(1, 2), b: port(3, 0)),
        ])
        #expect(TileShape.cairo.transforms.count == 2)
        let flipped = tile.transformed(by: TileShape.cairo.transforms[1])
        #expect(Set(flipped.pipes) != Set(tile.pipes))
        #expect(flipped.edgeCode.values.count == 5)
        #expect(flipped.transformed(by: TileShape.cairo.transforms[1]).pipes.sorted { ($0.a, $0.b) < ($1.a, $1.b) }
            == tile.pipes.sorted { ($0.a, $0.b) < ($1.a, $1.b) })
        #expect(tile.profile == flipped.profile)

        var library = TileLibrary(name: "Cairo", portsPerEdge: 3, shapes: [.cairo])
        library.save(tile)
        let again = Tile(portsPerEdge: 3, shape: .cairo, uncheckedPipes: flipped.pipes)
        #expect(library.twin(of: again)?.tile.id == tile.id)
        #expect(MazeGenerator(tiles: library.tiles).options.count == 2)
    }

    @Test(arguments: [3, 4, 6])
    func cairoMazesSeal(ports: Int) throws {
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6))
        var sealed = 0
        let runs = 6
        for seed in 0..<runs {
            var maze = Maze(portsPerEdge: ports, radius: 2, tiling: .cairo)
            #expect(maze.cellCount == 72)
            var random = SeededGenerator(seed: UInt64(seed))
            if generator.fill(&maze, symmetry: .none, using: &random) { sealed += 1 }
            for (coord, placed) in maze.cells {
                #expect(placed.source.shape == .cairo)
                #expect(maze.fits(placed.code, at: coord))
                #expect(!CoverageMap(tile: placed.source).hasViolation)
                #expect(placed.transform.turns == 0)
            }
            guard maze.isSealed else { continue }
            let allClosed = maze.paths.paths.allSatisfy { $0.isClosed }
            #expect(allClosed)
            let before = maze.paths.paths.count
            LoopMerger(generator: generator).mergeAll(&maze, using: &random)
            #expect(maze.isSealed)
            #expect(maze.paths.paths.count <= before)
            let loaded = try JSONDecoder().decode(Maze.self, from: JSONEncoder().encode(maze))
            #expect(loaded == maze)

            let sheet = BuildSheet(maze: maze)
            for (coord, placed) in maze.cells {
                let placement = try #require(sheet.placements[coord])
                let rebuilt = sheet.entries[placement.entry].tile.transformed(by: placement.transform)
                #expect(Set(rebuilt.pipes) == Set(placed.oriented.pipes))
            }
            #expect(MazeSVG.render(maze).contains("<polygon"))
        }
        #expect(sealed >= runs - 1)
    }

    @Test func pathsRunUnbrokenFromCellToCell() {
        // Where a path crosses from one pentagon to the next, the two pipe
        // ends are at the same spot in the plane, whichever way the cells
        // are turned.
        var maze = Maze(portsPerEdge: 4, radius: 2, tiling: .cairo)
        var random = SeededGenerator(seed: 8)
        MazeGenerator(tiles: []).fill(&maze, symmetry: .none, using: &random)
        var joins = 0
        for (coord, placed) in maze.cells {
            for port in placed.oriented.occupiedPorts {
                let other = maze.tiling.touching(port, of: coord, portsPerEdge: 4)
                guard let neighbour = maze.cells[other.coord] else { continue }
                #expect(neighbour.oriented.occupiedPorts.contains(other.port))
                let here = maze.frame(of: coord).place(TileShape.cairo.position(of: port, portsPerEdge: 4))
                let there = maze.frame(of: other.coord).place(TileShape.cairo.position(of: other.port, portsPerEdge: 4))
                #expect(here.distance(to: there) < 1e-9)
                joins += 1
            }
        }
        #expect(joins > 40)
    }

    @Test func aBoundedCairoMazeStaysInside() {
        let mask = Mask.rectangle(center: Point(x: 0.4, y: -0.2), width: 8.5, height: 6.5)
        let radius = Maze.radius(covering: mask, limit: 12, tiling: .cairo)
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6))
        var sealed = 0
        for seed in 0..<5 {
            var maze = Maze(portsPerEdge: 4, radius: radius, mask: mask, tiling: .cairo)
            #expect(maze.cellCount > 15)
            var random = SeededGenerator(seed: UInt64(seed))
            if generator.fill(&maze, symmetry: .none, using: &random) { sealed += 1 }
            #expect(!maze.cells.isEmpty)
            let inside = ink(of: maze).allSatisfy { mask.contains($0.point, inset: $0.reach - 0.02) }
            #expect(inside)
        }
        #expect(sealed >= 4)
    }

    @Test func theGridTurnsAQuarterAboutACornerBetweenFourPentagons() {
        let tiling = Tiling.cairo
        #expect(tiling.symmetries == [.none, .half, .quarter])
        // Four pentagons have a corner at the centre.
        let atCentre = tiling.cells(radius: 0).filter { cell in
            TileShape.cairo.corners.contains { tiling.frame(of: cell).place($0).distance(to: .zero) < 1e-9 }
        }
        #expect(atCentre.count == 4)

        let quarter = TileTransform(turns: 1, sides: 4)
        for cell in tiling.cells(radius: 3) {
            let image = tiling.transformed(cell, by: quarter)
            #expect(image != cell)
            #expect(tiling.ring(of: image) == tiling.ring(of: cell))
            // The image is the cell turned a quarter clockwise about the
            // centre: every corner lands on the matching corner.
            for corner in TileShape.cairo.corners {
                let from = tiling.frame(of: cell).place(corner)
                let to = tiling.frame(of: image).place(corner)
                #expect(to.distance(to: Point(x: -from.y, y: from.x)) < 1e-9)
            }
            // Neighbours go with it, across the same edges.
            for edge in 0..<5 {
                let before = tiling.neighbour(of: cell, across: edge)
                let after = tiling.neighbour(of: image, across: edge)
                #expect(after.cell == tiling.transformed(before.cell, by: quarter))
                #expect(after.edge == before.edge)
            }
            var round = cell
            for _ in 0..<4 { round = tiling.transformed(round, by: quarter) }
            #expect(round == cell)
            #expect(tiling.transformed(cell, by: TileTransform(turns: 2, sides: 4))
                == tiling.transformed(image, by: quarter))
            #expect(tiling.stabilizer(of: cell, symmetry: .quarter).isEmpty)
        }
    }

    @Test(arguments: [Symmetry.half, .quarter])
    func cairoMazesKeepTheirTurns(symmetry: Symmetry) {
        let tiling = Tiling.cairo
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6))
        let turns = tiling.transforms(for: symmetry).dropFirst()
        #expect(turns.count == (symmetry == .quarter ? 3 : 1))
        var sealed = 0
        let runs = 6
        for seed in 0..<runs {
            var maze = Maze(portsPerEdge: 4, radius: 2, tiling: tiling)
            var random = SeededGenerator(seed: UInt64(seed))
            if generator.fill(&maze, symmetry: symmetry, using: &random) { sealed += 1 }
            #expect(!maze.cells.isEmpty)
            for (coord, placed) in maze.cells {
                #expect(maze.fits(placed.code, at: coord))
                for turn in turns {
                    // The same tile, the same way up, in a cell that is
                    // itself turned.
                    let image = maze.cells[tiling.transformed(coord, by: turn)]
                    #expect(image?.oriented.pipes == placed.oriented.pipes)
                }
            }
            guard maze.isSealed else { continue }
            LoopMerger(generator: generator).mergeAll(&maze, symmetry: symmetry, using: &random)
            #expect(maze.isSealed)
            for (coord, placed) in maze.cells {
                for turn in turns {
                    let image = maze.cells[tiling.transformed(coord, by: turn)]
                    #expect(image.map { Set($0.oriented.pipes) } == Set(placed.oriented.pipes))
                }
            }
        }
        #expect(sealed >= runs - 1)
    }

    @Test func goalsWorkOnCairoTiles() {
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6))
        var sealed = 0
        for seed in 0..<4 {
            var maze = Maze(portsPerEdge: 4, radius: 2, tiling: .cairo)
            maze.setGoals([.origin, HexCoord(q: 1, r: 2)])
            var random = SeededGenerator(seed: UInt64(seed))
            if generator.fill(&maze, symmetry: .none, using: &random) {
                sealed += 1
                #expect(maze.paths.paths.filter { !$0.isClosed }.count == 1)
            }
        }
        #expect(sealed >= 3)
    }
}

/// A library that holds tiles of more than one shape.
@Suite struct MixedLibraryTests {
    private func randomTiles(_ shape: TileShape, count: Int, seed: UInt64) -> [Tile] {
        var random = SeededGenerator(seed: seed)
        var tiles: [Tile] = []
        while tiles.count < count {
            var tile = Tile(portsPerEdge: 3, shape: shape)
            for _ in 0..<(1 + tiles.count % 3) {
                tile.addRandomPipe(kinds: [.bezier, .corner], using: &random)
            }
            if !tile.pipes.isEmpty { tiles.append(tile) }
        }
        return tiles
    }

    private func mixed() -> TileLibrary {
        var library = TileLibrary(name: "Mixed", portsPerEdge: 3, shapes: [.hexagon, .square])
        for tile in randomTiles(.hexagon, count: 12, seed: 1) + randomTiles(.square, count: 9, seed: 2) {
            library.save(tile)
        }
        return library
    }

    @Test func aLibraryKeepsItsTilesByShape() throws {
        let library = mixed()
        #expect(library.shapes == [.hexagon, .square])
        #expect(library.tiles(of: .hexagon).count == 12)
        #expect(library.tiles(of: .square).count == 9)
        #expect(library.tiles(of: .cairo).isEmpty)
        // No shape twice, and never none.
        #expect(TileLibrary(name: "A", portsPerEdge: 3, shapes: [.square, .square]).shapes == [.square])
        #expect(TileLibrary(name: "B", portsPerEdge: 3, shapes: []).shapes == [.hexagon])

        let loaded = try JSONDecoder().decode(TileLibrary.self, from: JSONEncoder().encode(library))
        #expect(loaded == library)
    }

    @Test func aLibraryOfOneShapeIsStoredAsItAlwaysWas() throws {
        func keys(_ library: TileLibrary) throws -> Set<String> {
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(library))
            return Set((object as? [String: Any] ?? [:]).keys)
        }
        let hexes = try keys(TileLibrary(name: "Hexes", portsPerEdge: 3))
        #expect(!hexes.contains("shape") && !hexes.contains("shapes"))
        let squares = try keys(TileLibrary(name: "Squares", portsPerEdge: 3, shapes: [.square]))
        #expect(squares.contains("shape") && !squares.contains("shapes"))
        let both = try keys(mixed())
        #expect(both.contains("shapes") && !both.contains("shape"))
    }

    @Test func aLibraryLaysEveryTilingItHasTheShapesFor() {
        #expect(mixed().tilings == [.hexagonal, .square])
        #expect(TileLibrary(name: "Squares", portsPerEdge: 3, shapes: [.square]).tilings == [.square])
        for tiling in Tiling.allCases {
            #expect(Set(tiling.cells(radius: 2).map(tiling.shape(of:))) == Set(tiling.shapes))
            // Made for a tiling, a library lays it first, and any tiling
            // that needs only some of its shapes after.
            // Two tilings can use the same shapes, and then either may come
            // first.
            let able = TileLibrary(name: "One", portsPerEdge: 3, shapes: tiling.shapes).tilings
            #expect(able.contains(tiling))
            #expect(able.first?.shapes == tiling.shapes)
        }
    }

    @Test func deadSlotsApplyToEveryEdgeOfEveryShape() {
        var library = mixed()
        library.setDeadSlots([0])
        #expect(library.deadSlots == [0, 2])
        for shape in library.shapes {
            for edge in 0..<shape.edgeCount {
                #expect(!library.isLive(TubeKit.Port(edge: edge, slot: 0)))
                #expect(library.isLive(TubeKit.Port(edge: edge, slot: 1)))
            }
        }
    }

    @Test func twinsAndMergingKeepToOneShape() throws {
        var library = mixed()
        // The same pipes on a hexagon and on a square are different tiles.
        let pipe = Pipe(.bezier, a: TubeKit.Port(edge: 0, slot: 1), b: TubeKit.Port(edge: 2, slot: 1))
        let onSquare = try Tile(portsPerEdge: 3, shape: .square, pipes: [pipe])
        let onHexagon = try Tile(portsPerEdge: 3, shape: .hexagon, pipes: [pipe])
        library.save(onSquare)
        #expect(library.twin(of: onHexagon) == nil)
        let again = try Tile(portsPerEdge: 3, shape: .square, pipes: [pipe])
        #expect(library.twin(of: again)?.tile.id == onSquare.id)

        // Only the squares of a mixed library go into a library of squares.
        var squares = TileLibrary(name: "Squares", portsPerEdge: 3, shapes: [.square])
        #expect(squares.canTakeTiles(from: library))
        let result = squares.merge(library)
        #expect(result.added == squares.tiles.count)
        #expect(result.added + result.skipped == library.tiles.count)
        #expect(result.skipped >= 12)
        #expect(squares.tiles.allSatisfy { $0.shape == .square })

        let cairo = TileLibrary(name: "Cairo", portsPerEdge: 3, shapes: [.cairo])
        #expect(!cairo.canTakeTiles(from: library))
        #expect(!TileLibrary(name: "Four", portsPerEdge: 4, shapes: [.square]).canTakeTiles(from: library))
    }

    @Test(arguments: [Tiling.hexagonal, .square])
    func aCellIsOnlyOfferedTilesOfItsOwnShape(tiling: Tiling) {
        // Library tiles only, so every tile placed came from the library.
        let library = TileLibrary(name: "Mixed", portsPerEdge: 3, shapes: [.hexagon, .square])
        let tiles = randomTiles(.hexagon, count: 60, seed: 3) + randomTiles(.square, count: 60, seed: 4)
        let generator = MazeGenerator(tiles: tiles, synthesis: nil)
        #expect(Set(generator.options.map(\.source.shape)) == [.hexagon, .square])
        #expect(library.tilings.contains(tiling))

        var maze = Maze(portsPerEdge: 3, radius: 2, tiling: tiling)
        var random = SeededGenerator(seed: 5)
        generator.fill(&maze, symmetry: .none, using: &random)
        #expect(maze.cells.count > 3)
        for (coord, placed) in maze.cells {
            #expect(placed.source.shape == tiling.shape(of: coord))
            #expect(maze.fits(placed.code, at: coord))
        }
    }
}

/// Octagons with squares in the gaps.
@Suite struct TruncatedSquareTests {
    private let tiling = Tiling.truncatedSquare

    /// Where every pipe of a maze meets the edge of its cell, in the plane.
    private func portSpots(of maze: Maze) -> [Point] {
        maze.cells.flatMap { coord, placed in
            placed.oriented.occupiedPorts.map {
                maze.frame(of: coord).place(maze.tiling.shape(of: coord).position(of: $0, portsPerEdge: maze.portsPerEdge))
            }
        }
    }

    @Test func octagonsMeetOctagonsAndSquaresFillTheGaps() {
        #expect(TileShape.octagon.transforms.count == 16)
        #expect(abs(TileShape.octagon.inradius * 2 - (1 + (2.0).squareRoot())) < 1e-12)
        #expect(tiling.shapes == [.octagon, .square])
        #expect(tiling.shape(of: .origin) == .octagon)
        #expect(tiling.cells(radius: 0) == [.origin])
        // Nine octagons and the four squares between them.
        let cells = tiling.cells(radius: 1)
        #expect(cells.filter { tiling.shape(of: $0) == .octagon }.count == 9)
        #expect(cells.filter { tiling.shape(of: $0) == .square }.count == 4)
        #expect(!tiling.isCell(HexCoord(q: 1, r: 0)))
        #expect(!Maze(portsPerEdge: 3, radius: 2, tiling: tiling).contains(HexCoord(q: 1, r: 0)))

        for cell in tiling.cells(radius: 2) {
            let shape = tiling.shape(of: cell)
            for edge in 0..<shape.edgeCount {
                let other = tiling.shape(of: tiling.neighbour(of: cell, across: edge).cell)
                // A square only ever touches octagons; an octagon touches
                // octagons and squares by turns.
                #expect(other == (shape == .square || edge % 2 == 0 ? .octagon : .square))
            }
        }
        // A library made for it lays it first, and plain squares too.
        let library = TileLibrary(name: "Both", portsPerEdge: 3, shapes: tiling.shapes)
        #expect(library.tilings == [.truncatedSquare, .square])
    }

    @Test(arguments: [3, 4])
    func mazesSealWithTheRightShapeInEveryCell(ports: Int) throws {
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6))
        var sealed = 0
        let runs = 6
        for seed in 0..<runs {
            var maze = Maze(portsPerEdge: ports, radius: 2, tiling: tiling)
            #expect(maze.cellCount == 41)
            var random = SeededGenerator(seed: UInt64(seed))
            if generator.fill(&maze, symmetry: .none, using: &random) { sealed += 1 }
            for (coord, placed) in maze.cells {
                #expect(placed.source.shape == tiling.shape(of: coord))
                #expect(maze.fits(placed.code, at: coord))
                #expect(!CoverageMap(tile: placed.source).hasViolation)
            }
            guard maze.isSealed else { continue }
            #expect(Set(maze.cells.values.map(\.source.shape)) == [.octagon, .square])
            let before = maze.paths.paths.count
            LoopMerger(generator: generator).mergeAll(&maze, using: &random)
            #expect(maze.isSealed)
            #expect(maze.paths.paths.count <= before)
            let loaded = try JSONDecoder().decode(Maze.self, from: JSONEncoder().encode(maze))
            #expect(loaded == maze)

            let sheet = BuildSheet(maze: maze)
            for (coord, placed) in maze.cells {
                let placement = try #require(sheet.placements[coord])
                let entry = sheet.entries[placement.entry].tile
                #expect(entry.shape == placed.source.shape)
                #expect(Set(entry.transformed(by: placement.transform).pipes) == Set(placed.oriented.pipes))
            }
            #expect(MazeSVG.render(maze).contains("<polygon"))
        }
        #expect(sealed >= runs - 1)
    }

    @Test(arguments: [Symmetry.mirror, .half, .quarter])
    func mazesKeepTheirSymmetry(symmetry: Symmetry) {
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6))
        let moves = tiling.transforms(for: symmetry).dropFirst()
        #expect(tiling.stabilizer(of: .origin, symmetry: symmetry).count == moves.count)
        var sealed = 0
        let runs = 6
        for seed in 0..<runs {
            var maze = Maze(portsPerEdge: 4, radius: 2, tiling: tiling)
            var random = SeededGenerator(seed: UInt64(seed))
            if generator.fill(&maze, symmetry: symmetry, using: &random) { sealed += 1 }
            #expect(maze.cells.count > 8)
            // Turned or flipped about the centre, the pipe ends land on
            // pipe ends: the drawing is the same, not just the cells.
            let spots = portSpots(of: maze)
            for move in moves {
                for spot in spots {
                    let image = move.apply(to: spot)
                    #expect(spots.contains { $0.distance(to: image) < 1e-9 })
                }
                for (coord, placed) in maze.cells {
                    let target = tiling.transformed(coord, by: move)
                    #expect(maze.cells[target]?.source.shape == placed.source.shape)
                }
            }
        }
        #expect(sealed >= runs - 1)
    }

    @Test func aBoundedMazeStaysInsideAndGoalsWork() {
        let mask = Mask.rectangle(center: Point(x: 0.3, y: -0.2), width: 11, height: 8)
        let radius = Maze.radius(covering: mask, limit: 12, tiling: tiling)
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6))
        var sealed = 0
        for seed in 0..<4 {
            var maze = Maze(portsPerEdge: 4, radius: radius, mask: mask, tiling: tiling)
            #expect(maze.cellCount > 15)
            // One goal in an octagon and one in a square.
            maze.setGoals([.origin, HexCoord(q: 1, r: 1)])
            var random = SeededGenerator(seed: UInt64(seed))
            if generator.fill(&maze, symmetry: .none, using: &random) {
                sealed += 1
                #expect(maze.paths.paths.filter { !$0.isClosed }.count == 1)
            }
            for spot in portSpots(of: maze) { #expect(mask.contains(spot, inset: 0)) }
        }
        #expect(sealed >= 3)
    }

    @Test func aMixedLibraryFillsBothShapes() {
        var random = SeededGenerator(seed: 21)
        var tiles: [Tile] = []
        for shape in [TileShape.octagon, .square] {
            var made = 0
            while made < 80 {
                var tile = Tile(portsPerEdge: 3, shape: shape)
                for _ in 0..<(1 + made % 4) { tile.addRandomPipe(kinds: [.bezier, .corner], using: &random) }
                if !tile.pipes.isEmpty {
                    tiles.append(tile)
                    made += 1
                }
            }
        }
        let generator = MazeGenerator(tiles: tiles, synthesis: .init(growth: 0.5))
        var maze = Maze(portsPerEdge: 3, radius: 2, tiling: tiling)
        #expect(generator.fill(&maze, symmetry: .none, using: &random))
        let fromLibrary = maze.cells.filter { !$0.value.isGenerated }
        #expect(fromLibrary.contains { $0.value.source.shape == .octagon })
        #expect(fromLibrary.contains { $0.value.source.shape == .square })
        for (coord, placed) in maze.cells { #expect(placed.source.shape == tiling.shape(of: coord)) }
    }
}

/// Pipes are drawn to the shape of their own cell.
@Suite struct MixedDrawingTests {
    /// The first and last points of the first wall in a maze's drawing.
    private func ends(of svg: String) throws -> (Point, Point) {
        let line = try #require(svg.split(separator: "\n").first { $0.contains(#"id="wall-1""#) })
        let data = try #require(line.split(separator: "\"").last { $0.hasPrefix("M ") })
        let numbers = data.split { !"-.0123456789".contains($0) }.compactMap { Double($0) }
        try #require(numbers.count >= 4)
        return (
            Point(x: numbers[0], y: numbers[1]),
            Point(x: numbers[numbers.count - 2], y: numbers[numbers.count - 1])
        )
    }

    @Test(arguments: [HexCoord(q: 1, r: 1), HexCoord(q: 0, r: 0), HexCoord(q: -1, r: 1), HexCoord(q: 2, r: 0)])
    func aLonePipeIsDrawnBetweenItsOwnCellsPorts(coord: HexCoord) throws {
        // One pipe straight across one cell, in a square and in an octagon.
        // Its drawing has to start and stop as far apart as that cell's two
        // ports are, which is one unit in a square and far more in an
        // octagon.
        let tiling = Tiling.truncatedSquare
        let shape = tiling.shape(of: coord)
        let from = TubeKit.Port(edge: 0, slot: 1)
        let to = TubeKit.Port(edge: shape.edgeCount / 2, slot: 1)
        let tile = try Tile(portsPerEdge: 3, shape: shape, pipes: [Pipe(.bezier, a: from, b: to)])
        let maze = try #require(Maze(portsPerEdge: 3, radius: 2, tiling: tiling).placing(PlacedTile(tile), at: coord))

        let apart = shape.position(of: from, portsPerEdge: 3).distance(to: shape.position(of: to, portsPerEdge: 3))
        #expect(abs(apart - shape.inradius * 2) < 1e-9)
        let drawn = try ends(of: MazeSVG.render(maze))
        #expect(abs(drawn.0.distance(to: drawn.1) - apart * MazeSVG.Options().cellSize) < 0.05)
    }
}

/// Hexagons with a triangle on every edge.
@Suite struct TrihexagonalTests {
    private let tiling = Tiling.trihexagonal

    private func portSpots(of maze: Maze) -> [Point] {
        maze.cells.flatMap { coord, placed in
            placed.oriented.occupiedPorts.map {
                maze.frame(of: coord).place(maze.tiling.shape(of: coord).position(of: $0, portsPerEdge: maze.portsPerEdge))
            }
        }
    }

    @Test func hexagonsOnlyTouchTriangles() {
        #expect(TileShape.triangle.transforms.count == 6)
        #expect(tiling.shapes == [.hexagon, .triangle])
        #expect(tiling.cells(radius: 0) == [.origin])
        // Seven hexagons and the six triangles they close in.
        let cells = tiling.cells(radius: 1)
        #expect(cells.filter { tiling.shape(of: $0) == .hexagon }.count == 7)
        #expect(cells.filter { tiling.shape(of: $0) == .triangle }.count == 6)
        for cell in tiling.cells(radius: 2) {
            let shape = tiling.shape(of: cell)
            for edge in 0..<shape.edgeCount {
                let other = tiling.shape(of: tiling.neighbour(of: cell, across: edge).cell)
                #expect(other == (shape == .hexagon ? .triangle : .hexagon))
            }
        }
        let library = TileLibrary(name: "Both", portsPerEdge: 3, shapes: tiling.shapes)
        #expect(library.tilings == [.trihexagonal, .hexagonal, .triangular])
    }

    @Test(arguments: [2, 3, 4])
    func mazesSealWithTheRightShapeInEveryCell(ports: Int) throws {
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6))
        var sealed = 0
        let runs = 6
        for seed in 0..<runs {
            var maze = Maze(portsPerEdge: ports, radius: 2, tiling: tiling)
            #expect(maze.cellCount == 43)
            var random = SeededGenerator(seed: UInt64(seed))
            if generator.fill(&maze, symmetry: .none, using: &random) { sealed += 1 }
            for (coord, placed) in maze.cells {
                #expect(placed.source.shape == tiling.shape(of: coord))
                #expect(maze.fits(placed.code, at: coord))
                #expect(!CoverageMap(tile: placed.source).hasViolation)
            }
            guard maze.isSealed else { continue }
            #expect(Set(maze.cells.values.map(\.source.shape)) == [.hexagon, .triangle])
            let before = maze.paths.paths.count
            LoopMerger(generator: generator).mergeAll(&maze, using: &random)
            #expect(maze.isSealed)
            #expect(maze.paths.paths.count <= before)
            let loaded = try JSONDecoder().decode(Maze.self, from: JSONEncoder().encode(maze))
            #expect(loaded == maze)
            let sheet = BuildSheet(maze: maze)
            for (coord, placed) in maze.cells {
                let placement = try #require(sheet.placements[coord])
                let entry = sheet.entries[placement.entry].tile
                #expect(entry.shape == placed.source.shape)
                #expect(Set(entry.transformed(by: placement.transform).pipes) == Set(placed.oriented.pipes))
            }
            #expect(MazeSVG.render(maze).contains("<polygon"))
        }
        #expect(sealed >= runs - 1)
    }

    @Test(arguments: [Symmetry.mirror, .half, .third, .sixth])
    func mazesKeepTheirSymmetry(symmetry: Symmetry) {
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6))
        let moves = tiling.transforms(for: symmetry).dropFirst()
        #expect(tiling.stabilizer(of: .origin, symmetry: symmetry).count == moves.count)
        var sealed = 0
        let runs = 6
        for seed in 0..<runs {
            var maze = Maze(portsPerEdge: 3, radius: 2, tiling: tiling)
            var random = SeededGenerator(seed: UInt64(seed))
            if generator.fill(&maze, symmetry: symmetry, using: &random) { sealed += 1 }
            #expect(maze.cells.count > 8)
            let spots = portSpots(of: maze)
            for move in moves {
                for spot in spots {
                    let image = move.apply(to: spot)
                    #expect(spots.contains { $0.distance(to: image) < 1e-9 })
                }
                for (coord, placed) in maze.cells {
                    let target = tiling.transformed(coord, by: move)
                    #expect(maze.cells[target]?.source.shape == placed.source.shape)
                }
            }
        }
        #expect(sealed >= runs - 1)
    }

    @Test func aBoundedMazeStaysInsideAndGoalsWork() {
        let mask = Mask.rectangle(center: Point(x: 0.3, y: -0.2), width: 11, height: 8)
        let radius = Maze.radius(covering: mask, limit: 12, tiling: tiling)
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6))
        var sealed = 0
        for seed in 0..<4 {
            var maze = Maze(portsPerEdge: 3, radius: radius, mask: mask, tiling: tiling)
            #expect(maze.cellCount > 15)
            maze.setGoals([.origin, HexCoord(q: 1, r: 0)])
            var random = SeededGenerator(seed: UInt64(seed))
            if generator.fill(&maze, symmetry: .none, using: &random) {
                sealed += 1
                #expect(maze.paths.paths.filter { !$0.isClosed }.count == 1)
            }
            for spot in portSpots(of: maze) { #expect(mask.contains(spot, inset: 0)) }
        }
        #expect(sealed >= 3)
    }

    @Test(arguments: [2, 3, 4, 6])
    func whatFitsInATriangle(ports: Int) {
        // Not a pass or fail so much as a record: every pair of ports on
        // different edges should be joinable by at least a curve.
        var joined = 0
        var pairs = 0
        let shape = TileShape.triangle
        for a in shape.ports(portsPerEdge: ports) {
            for b in shape.ports(portsPerEdge: ports) where a < b && a.edge != b.edge {
                pairs += 1
                var tile = Tile(portsPerEdge: ports, shape: shape)
                if (try? tile.add(Pipe(.bezier, a: a, b: b))) != nil { joined += 1 }
            }
        }
        #expect(joined == pairs)
    }
}

/// The two ways of laying squares and triangles together.
@Suite struct SquareAndTriangleTests {
    private func portSpots(of maze: Maze) -> [Point] {
        maze.cells.flatMap { coord, placed in
            placed.oriented.occupiedPorts.map {
                maze.frame(of: coord).place(maze.tiling.shape(of: coord).position(of: $0, portsPerEdge: maze.portsPerEdge))
            }
        }
    }

    @Test func oneLibraryLaysBothAndPlainSquares() {
        let library = TileLibrary(name: "Both", portsPerEdge: 3, shapes: [.square, .triangle])
        #expect(library.tilings == [.elongatedTriangular, .snubSquare, .square, .triangular])
        #expect(Tiling.elongatedTriangular.shapes == Tiling.snubSquare.shapes)
    }

    @Test func rowsOfSquaresAndRowsOfTriangles() {
        let tiling = Tiling.elongatedTriangular
        #expect(tiling.cells(radius: 0) == [.origin])
        // Three rows of squares, three, two and three long, and two rows of
        // triangles between them.
        let cells = tiling.cells(radius: 1)
        #expect(cells.filter { tiling.shape(of: $0) == .square }.count == 7)
        for cell in tiling.cells(radius: 3) {
            let shape = tiling.shape(of: cell)
            let around = (0..<shape.edgeCount).map { tiling.shape(of: tiling.neighbour(of: cell, across: $0).cell) }
            // A square has squares either side and triangles above and
            // below. A triangle has one square and two triangles.
            #expect(around == (shape == .square ? [.triangle, .square, .triangle, .square] : [.square, .triangle, .triangle]))
        }
    }

    @Test func pinwheelSquaresMeetOnlyTriangles() {
        let tiling = Tiling.snubSquare
        #expect(tiling.cells(radius: 0) == [.origin])
        // Nine squares and a triangle between each two that touch.
        let cells = tiling.cells(radius: 1)
        #expect(cells.filter { tiling.shape(of: $0) == .square }.count == 9)
        #expect(cells.filter { tiling.shape(of: $0) == .triangle }.count == 12)
        #expect(!tiling.isCell(HexCoord(q: 1, r: 1)))
        for cell in tiling.cells(radius: 3) {
            let shape = tiling.shape(of: cell)
            let around = (0..<shape.edgeCount).map { tiling.shape(of: tiling.neighbour(of: cell, across: $0).cell) }
            // A square is ringed by triangles. A triangle has two squares
            // and the triangle it sits back to back with.
            #expect(around.filter { $0 == .square }.count == (shape == .square ? 0 : 2))
            // Squares that touch at a corner tilt opposite ways.
            if shape == .square {
                let tilt = tiling.turn(of: cell)
                let beside = tiling.turn(of: HexCoord(q: cell.q + 1, r: cell.r))
                #expect(abs(tilt + beside) < 1e-12 && abs(abs(tilt) - .pi / 6) < 1e-12)
            }
        }
    }

    @Test(arguments: [Tiling.elongatedTriangular, .snubSquare], [3, 4])
    func mazesSealWithTheRightShapeInEveryCell(tiling: Tiling, ports: Int) throws {
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6))
        var sealed = 0
        let runs = 6
        for seed in 0..<runs {
            var maze = Maze(portsPerEdge: ports, radius: 2, tiling: tiling)
            var random = SeededGenerator(seed: UInt64(seed))
            if generator.fill(&maze, symmetry: .none, using: &random) { sealed += 1 }
            for (coord, placed) in maze.cells {
                #expect(tiling.isCell(coord))
                #expect(placed.source.shape == tiling.shape(of: coord))
                #expect(maze.fits(placed.code, at: coord))
                #expect(!CoverageMap(tile: placed.source).hasViolation)
            }
            guard maze.isSealed else { continue }
            #expect(Set(maze.cells.values.map(\.source.shape)) == [.square, .triangle])
            let before = maze.paths.paths.count
            LoopMerger(generator: generator).mergeAll(&maze, using: &random)
            #expect(maze.isSealed)
            #expect(maze.paths.paths.count <= before)
            #expect(maze.weave().conflicts == 0)
            let loaded = try JSONDecoder().decode(Maze.self, from: JSONEncoder().encode(maze))
            #expect(loaded == maze)
            let sheet = BuildSheet(maze: maze)
            for (coord, placed) in maze.cells {
                let placement = try #require(sheet.placements[coord])
                let entry = sheet.entries[placement.entry].tile
                #expect(entry.shape == placed.source.shape)
                #expect(Set(entry.transformed(by: placement.transform).pipes) == Set(placed.oriented.pipes))
            }
            #expect(MazeSVG.render(maze).contains("<polygon"))
        }
        #expect(sealed >= runs - 1)
    }

    @Test(arguments: [Tiling.elongatedTriangular, .snubSquare])
    func mazesKeepTheirSymmetry(tiling: Tiling) {
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6))
        for symmetry in tiling.symmetries.dropFirst() {
            let moves = tiling.transforms(for: symmetry).dropFirst()
            #expect(!moves.isEmpty)
            #expect(tiling.stabilizer(of: .origin, symmetry: symmetry).count == moves.count)
            for seed in 0..<4 {
                var maze = Maze(portsPerEdge: 3, radius: 2, tiling: tiling)
                var random = SeededGenerator(seed: UInt64(seed))
                generator.fill(&maze, symmetry: symmetry, using: &random)
                // A maze can seal while still small; it is symmetric all
                // the same.
                #expect(maze.cells.count > 2)
                let spots = portSpots(of: maze)
                for move in moves {
                    for spot in spots {
                        let image = move.apply(to: spot)
                        #expect(spots.contains { $0.distance(to: image) < 1e-9 })
                    }
                    for (coord, placed) in maze.cells {
                        let target = tiling.transformed(coord, by: move)
                        #expect(maze.cells[target]?.source.shape == placed.source.shape)
                    }
                }
            }
        }
    }

    @Test(arguments: [Tiling.elongatedTriangular, .snubSquare])
    func aBoundedMazeStaysInsideAndGoalsWork(tiling: Tiling) {
        let mask = Mask.rectangle(center: Point(x: 0.3, y: -0.2), width: 8, height: 6)
        let radius = Maze.radius(covering: mask, limit: 12, tiling: tiling)
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6))
        var sealed = 0
        for seed in 0..<4 {
            var maze = Maze(portsPerEdge: 3, radius: radius, mask: mask, tiling: tiling)
            #expect(maze.cellCount > 15)
            // One goal in a square and one in a triangle.
            maze.setGoals([.origin, HexCoord(q: 0, r: 1)])
            var random = SeededGenerator(seed: UInt64(seed))
            if generator.fill(&maze, symmetry: .none, using: &random) {
                sealed += 1
                #expect(maze.paths.paths.filter { !$0.isClosed }.count == 1)
            }
            for spot in portSpots(of: maze) { #expect(mask.contains(spot, inset: 0)) }
        }
        #expect(sealed >= 3)
    }
}

/// Hexagons with a square on every edge and a triangle at every corner.
@Suite struct RhombitrihexagonalTests {
    private let tiling = Tiling.rhombitrihexagonal

    private func portSpots(of maze: Maze) -> [Point] {
        maze.cells.flatMap { coord, placed in
            placed.oriented.occupiedPorts.map {
                maze.frame(of: coord).place(maze.tiling.shape(of: coord).position(of: $0, portsPerEdge: maze.portsPerEdge))
            }
        }
    }

    @Test func squaresSeparateHexagonsFromEachOtherAndFromTriangles() {
        #expect(tiling.shapes == [.hexagon, .square, .triangle])
        #expect(tiling.cells(radius: 0) == [.origin])
        // Seven hexagons, a square for each two that are neighbours and a
        // triangle for each three.
        let cells = tiling.cells(radius: 1)
        #expect(cells.filter { tiling.shape(of: $0) == .hexagon }.count == 7)
        #expect(cells.filter { tiling.shape(of: $0) == .square }.count == 12)
        #expect(cells.filter { tiling.shape(of: $0) == .triangle }.count == 6)
        for cell in tiling.cells(radius: 2) {
            let shape = tiling.shape(of: cell)
            let around = (0..<shape.edgeCount).map { tiling.shape(of: tiling.neighbour(of: cell, across: $0).cell) }
            // Hexagons and triangles touch only squares. A square has a
            // hexagon at each end and a triangle on each side.
            switch shape {
            case .square: #expect(around == [.hexagon, .triangle, .hexagon, .triangle])
            default: #expect(around.allSatisfy { $0 == .square })
            }
        }
    }

    @Test func aLibraryOfAllThreeShapesLaysSevenTilings() {
        let library = TileLibrary(name: "Three", portsPerEdge: 3, shapes: [.hexagon, .square, .triangle])
        #expect(library.tilings.first == .rhombitrihexagonal)
        #expect(Set(library.tilings) == [
            .rhombitrihexagonal, .trihexagonal, .elongatedTriangular, .snubSquare, .hexagonal, .square,
            .triangular,
        ])
    }

    @Test(arguments: [3, 4])
    func mazesSealWithTheRightShapeInEveryCell(ports: Int) throws {
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6))
        var sealed = 0
        let runs = 6
        for seed in 0..<runs {
            var maze = Maze(portsPerEdge: ports, radius: 2, tiling: tiling)
            #expect(maze.cellCount == 85)
            var random = SeededGenerator(seed: UInt64(seed))
            if generator.fill(&maze, symmetry: .none, using: &random) { sealed += 1 }
            for (coord, placed) in maze.cells {
                #expect(placed.source.shape == tiling.shape(of: coord))
                #expect(maze.fits(placed.code, at: coord))
                #expect(!CoverageMap(tile: placed.source).hasViolation)
            }
            guard maze.isSealed else { continue }
            let before = maze.paths.paths.count
            LoopMerger(generator: generator).mergeAll(&maze, using: &random)
            #expect(maze.isSealed)
            #expect(maze.paths.paths.count <= before)
            #expect(maze.weave().conflicts == 0)
            let loaded = try JSONDecoder().decode(Maze.self, from: JSONEncoder().encode(maze))
            #expect(loaded == maze)
            let sheet = BuildSheet(maze: maze)
            for (coord, placed) in maze.cells {
                let placement = try #require(sheet.placements[coord])
                let entry = sheet.entries[placement.entry].tile
                #expect(entry.shape == placed.source.shape)
                #expect(Set(entry.transformed(by: placement.transform).pipes) == Set(placed.oriented.pipes))
            }
            #expect(MazeSVG.render(maze).contains("<polygon"))
        }
        #expect(sealed >= runs - 1)
    }

    @Test(arguments: [Symmetry.mirror, .half, .third, .sixth])
    func mazesKeepTheirSymmetry(symmetry: Symmetry) {
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6))
        let moves = tiling.transforms(for: symmetry).dropFirst()
        #expect(tiling.stabilizer(of: .origin, symmetry: symmetry).count == moves.count)
        for seed in 0..<4 {
            var maze = Maze(portsPerEdge: 3, radius: 2, tiling: tiling)
            var random = SeededGenerator(seed: UInt64(seed))
            generator.fill(&maze, symmetry: symmetry, using: &random)
            #expect(maze.cells.count > 2)
            let spots = portSpots(of: maze)
            for move in moves {
                for spot in spots {
                    let image = move.apply(to: spot)
                    #expect(spots.contains { $0.distance(to: image) < 1e-9 })
                }
                for (coord, placed) in maze.cells {
                    let target = tiling.transformed(coord, by: move)
                    #expect(maze.cells[target]?.source.shape == placed.source.shape)
                }
            }
        }
    }

    @Test func aBoundedMazeStaysInsideAndGoalsWork() {
        let mask = Mask.rectangle(center: Point(x: 0.3, y: -0.2), width: 11, height: 8)
        let radius = Maze.radius(covering: mask, limit: 12, tiling: tiling)
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6))
        var sealed = 0
        for seed in 0..<4 {
            var maze = Maze(portsPerEdge: 3, radius: radius, mask: mask, tiling: tiling)
            #expect(maze.cellCount > 15)
            // A goal in a hexagon, one in a square and one in a triangle
            // would be three ends; two of them make one path.
            maze.setGoals([.origin, HexCoord(q: 0, r: 4)])
            var random = SeededGenerator(seed: UInt64(seed))
            if generator.fill(&maze, symmetry: .none, using: &random) {
                sealed += 1
                #expect(maze.paths.paths.filter { !$0.isClosed }.count == 1)
            }
            for spot in portSpots(of: maze) { #expect(mask.contains(spot, inset: 0)) }
        }
        #expect(sealed >= 3)
    }
}

/// Triangles alone.
@Suite struct TriangularTests {
    private let tiling = Tiling.triangular

    private func portSpots(of maze: Maze) -> [Point] {
        maze.cells.flatMap { coord, placed in
            placed.oriented.occupiedPorts.map {
                maze.frame(of: coord).place(TileShape.triangle.position(of: $0, portsPerEdge: maze.portsPerEdge))
            }
        }
    }

    @Test func trianglesPointDownAndUpByTurns() {
        #expect(tiling.shapes == [.triangle])
        #expect(Tiling(shape: .triangle) == .triangular)
        #expect(tiling.cells(radius: 0) == [.origin])
        // The middle triangle, the three round it, and the six beyond.
        #expect(tiling.cells(radius: 1).count == 10)
        for cell in tiling.cells(radius: 3) {
            let turned = tiling.turn(of: cell)
            for edge in 0..<3 {
                let other = tiling.neighbour(of: cell, across: edge).cell
                #expect(abs(abs(tiling.turn(of: other) - turned) - .pi) < 1e-12)
            }
        }
        #expect(TileLibrary(name: "T", portsPerEdge: 3, shapes: [.triangle]).tilings == [.triangular])
    }

    @Test(arguments: [2, 3, 4])
    func mazesSeal(ports: Int) throws {
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6))
        var sealed = 0
        let runs = 6
        for seed in 0..<runs {
            var maze = Maze(portsPerEdge: ports, radius: 3, tiling: tiling)
            #expect(maze.cellCount == 64)
            var random = SeededGenerator(seed: UInt64(seed))
            if generator.fill(&maze, symmetry: .none, using: &random) { sealed += 1 }
            for (coord, placed) in maze.cells {
                #expect(placed.source.shape == .triangle)
                #expect(maze.fits(placed.code, at: coord))
                #expect(!CoverageMap(tile: placed.source).hasViolation)
            }
            guard maze.isSealed else { continue }
            LoopMerger(generator: generator).mergeAll(&maze, using: &random)
            #expect(maze.isSealed)
            #expect(maze.weave().conflicts == 0)
            let loaded = try JSONDecoder().decode(Maze.self, from: JSONEncoder().encode(maze))
            #expect(loaded == maze)
            #expect(MazeSVG.render(maze).contains("<polygon"))
        }
        #expect(sealed >= runs - 1)
    }

    @Test(arguments: [Symmetry.mirror, .third])
    func mazesKeepTheirSymmetry(symmetry: Symmetry) {
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6))
        let moves = tiling.transforms(for: symmetry).dropFirst()
        #expect(tiling.stabilizer(of: .origin, symmetry: symmetry).count == moves.count)
        for seed in 0..<4 {
            var maze = Maze(portsPerEdge: 3, radius: 3, tiling: tiling)
            var random = SeededGenerator(seed: UInt64(seed))
            generator.fill(&maze, symmetry: symmetry, using: &random)
            #expect(maze.cells.count > 2)
            let spots = portSpots(of: maze)
            for move in moves {
                for spot in spots {
                    let image = move.apply(to: spot)
                    #expect(spots.contains { $0.distance(to: image) < 1e-9 })
                }
            }
        }
    }

    @Test func aBoundedMazeStaysInsideAndGoalsWork() {
        let mask = Mask.rectangle(center: Point(x: 0.3, y: -0.2), width: 7, height: 5)
        let radius = Maze.radius(covering: mask, limit: 12, tiling: tiling)
        let generator = MazeGenerator(tiles: [], synthesis: .init(growth: 0.6))
        var sealed = 0
        for seed in 0..<4 {
            var maze = Maze(portsPerEdge: 3, radius: radius, mask: mask, tiling: tiling)
            #expect(maze.cellCount > 15)
            maze.setGoals([.origin, HexCoord(q: 1, r: 1)])
            var random = SeededGenerator(seed: UInt64(seed))
            if generator.fill(&maze, symmetry: .none, using: &random) {
                sealed += 1
                #expect(maze.paths.paths.filter { !$0.isClosed }.count == 1)
            }
            for spot in portSpots(of: maze) { #expect(mask.contains(spot, inset: 0)) }
        }
        #expect(sealed >= 3)
    }
}
