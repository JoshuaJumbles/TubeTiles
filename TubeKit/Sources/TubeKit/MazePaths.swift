/// One end of a pipe somewhere in a maze: a port of the tile at a cell.
public struct PortRef: Hashable, Sendable, Codable {
    public var coord: HexCoord
    public var port: Port

    public init(coord: HexCoord, port: Port) {
        self.coord = coord
        self.port = port
    }
}

/// A run of pipes joined end to end across tiles.
public struct MazePath: Hashable, Sendable {
    public struct Step: Hashable, Sendable {
        public var coord: HexCoord
        public var pipe: Pipe
        /// The end of the pipe the path comes in through. For a dead end,
        /// its only port.
        public var entry: Port
        /// For a dead end only: true when the path sets off from the room
        /// and leaves by the port, false when it arrives and stops.
        public var startsInRoom = false

        public var exit: Port { pipe.otherEnd(from: entry) ?? entry }

        /// Whether the path travels the pipe's centre line from its far end
        /// back to its `a` end.
        public var runsBackwards: Bool {
            pipe.isDeadEnd ? startsInRoom : entry != pipe.a
        }
    }

    public var steps: [Step]
    /// True for a loop. False for a strand with two ends: a path running
    /// between openings or dead ends, or a loose piece of an unfinished maze.
    public var isClosed: Bool

    /// The pipe ends where an open path starts and finishes. Nil for a loop.
    public var ends: (start: PortRef, finish: PortRef)? {
        guard !isClosed, let first = steps.first, let last = steps.last else { return nil }
        return (PortRef(coord: first.coord, port: first.entry), PortRef(coord: last.coord, port: last.exit))
    }

    /// Both ends of every pipe on the path.
    public var portRefs: Set<PortRef> {
        Set(steps.flatMap { [PortRef(coord: $0.coord, port: $0.pipe.a), PortRef(coord: $0.coord, port: $0.pipe.b)] })
    }
}

/// Every path in a maze. Each pipe belongs to exactly one.
public struct MazePaths: Sendable {
    public let paths: [MazePath]
    private let indexByRef: [PortRef: Int]

    init(paths: [MazePath]) {
        self.paths = paths
        var index: [PortRef: Int] = [:]
        for (number, path) in paths.enumerated() {
            for ref in path.portRefs {
                index[ref] = number
            }
        }
        indexByRef = index
    }

    /// Which path the pipe ending at `ref` belongs to.
    public func index(of ref: PortRef) -> Int? {
        indexByRef[ref]
    }

    public func index(of pipe: Pipe, at coord: HexCoord) -> Int? {
        indexByRef[PortRef(coord: coord, port: pipe.a)]
    }

    public var loopCount: Int { paths.filter(\.isClosed).count }
}

extension Maze {
    /// The pipe reached by leaving the tile at `coord` through `port`, and
    /// the end of it the path arrives at.
    private func crossing(from coord: HexCoord, through port: Port) -> (coord: HexCoord, pipe: Pipe, entry: Port)? {
        let neighbour = coord.neighbour(across: port.edge)
        let entry = port.neighbourPort(portsPerEdge: portsPerEdge)
        guard let pipe = cells[neighbour]?.oriented.pipe(at: entry) else { return nil }
        return (neighbour, pipe, entry)
    }

    /// Follows every pipe across tile edges and groups them into paths.
    public var paths: MazePaths {
        var visited: Set<PortRef> = []
        var result: [MazePath] = []

        for coord in cells.keys.sorted() {
            for pipe in cells[coord]?.oriented.pipes ?? [] {
                guard visited.insert(PortRef(coord: coord, port: pipe.a)).inserted else { continue }

                // A dead end has only one way on, out through its port, so
                // it is always the first step of its path.
                var steps = [MazePath.Step(coord: coord, pipe: pipe, entry: pipe.a, startsInRoom: pipe.isDeadEnd)]
                var isClosed = false
                var position = (coord: coord, exit: pipe.isDeadEnd ? pipe.a : pipe.b)
                while let next = crossing(from: position.coord, through: position.exit) {
                    if next.coord == coord && next.pipe == pipe {
                        isClosed = true
                        break
                    }
                    visited.insert(PortRef(coord: next.coord, port: next.pipe.a))
                    let step = MazePath.Step(coord: next.coord, pipe: next.pipe, entry: next.entry)
                    steps.append(step)
                    // Arriving at a dead end finishes the path.
                    if next.pipe.isDeadEnd { break }
                    position = (next.coord, step.exit)
                }

                if !isClosed && !pipe.isDeadEnd {
                    // A strand with ends: also walk back from the start.
                    var earlier: [MazePath.Step] = []
                    position = (coord, pipe.a)
                    while let next = crossing(from: position.coord, through: position.exit) {
                        visited.insert(PortRef(coord: next.coord, port: next.pipe.a))
                        if next.pipe.isDeadEnd {
                            earlier.append(MazePath.Step(
                                coord: next.coord, pipe: next.pipe, entry: next.entry, startsInRoom: true
                            ))
                            break
                        }
                        let leaving = next.pipe.otherEnd(from: next.entry) ?? next.entry
                        earlier.append(MazePath.Step(coord: next.coord, pipe: next.pipe, entry: leaving))
                        position = (next.coord, leaving)
                    }
                    steps = earlier.reversed() + steps
                }
                result.append(MazePath(steps: steps, isClosed: isClosed))
            }
        }
        return MazePaths(paths: result)
    }

    /// The maze with the tile at `coord` (and at its images) swapped for
    /// `tile`, or nil if the new tile does not fit.
    public func replacing(at coord: HexCoord, with tile: PlacedTile, symmetry: Symmetry = .none) -> Maze? {
        var next = self
        next.remove(at: coord, symmetry: symmetry)
        return next.placing(tile, at: coord, symmetry: symmetry)
    }
}

extension PipeShape {
    /// Shortest distance from a point to the pipe's centre line.
    public func distance(to point: Point) -> Double {
        var best = Double.infinity
        for segment in segments {
            let points = segment.flattened()
            for (start, end) in zip(points, points.dropFirst()) {
                let span = end - start
                let lengthSquared = span.x * span.x + span.y * span.y
                var t = 0.0
                if lengthSquared > 0 {
                    t = ((point.x - start.x) * span.x + (point.y - start.y) * span.y) / lengthSquared
                    t = min(1, max(0, t))
                }
                best = min(best, point.distance(to: start + span * t))
            }
        }
        if let room {
            best = min(best, max(0, point.distance(to: room.center) - room.diameter / 2))
        }
        return best
    }
}
