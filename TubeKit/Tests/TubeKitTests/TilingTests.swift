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
            #expect(abs(middle.distance(to: .zero) - shape.inradius) < 1e-9)
        }
        #expect(shape.contains(.zero))
        #expect(shape.transforms.count == shape.edgeCount * 2)
        #expect(Set(shape.transforms).count == shape.edgeCount * 2)
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
        #expect(Tiling(shape: tiling.shape(of: .origin)) == tiling)
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
                        tiling.center(of: cell) + shape.position(of: port, portsPerEdge: 3),
                        tiling.center(of: twin.coord)
                            + tiling.shape(of: twin.coord).position(of: twin.port, portsPerEdge: 3)
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
                    let point = tiling.center(of: cell) + corner
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
                #expect(transform.sides == tiling.shape(of: .origin).edgeCount)
                for cell in tiling.cells(radius: 3) {
                    let moved = tiling.transformed(cell, by: transform)
                    #expect(close(tiling.center(of: moved), transform.apply(to: tiling.center(of: cell))))
                    #expect(tiling.ring(of: moved) == tiling.ring(of: cell))
                }
            }
            #expect(tiling.stabilizer(of: .origin, symmetry: symmetry).count == transforms.count - 1)
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
        var squares = TileLibrary(name: "Squares", portsPerEdge: 3, deadSlots: [0], shape: .square)
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
