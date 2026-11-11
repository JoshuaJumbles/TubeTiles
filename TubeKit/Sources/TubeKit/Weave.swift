import Foundation

/// A pipe's centre line as straight pieces, measured by distance along it
/// from the pipe's `a` end.
public struct Polyline: Hashable, Sendable {
    public let points: [Point]
    /// Distance from the start to each point.
    public let distances: [Double]

    public init(points: [Point]) {
        self.points = points
        var distances: [Double] = []
        var total = 0.0
        for (index, point) in points.enumerated() {
            if index > 0 { total += points[index - 1].distance(to: point) }
            distances.append(total)
        }
        self.distances = distances
    }

    public init(_ shape: PipeShape) {
        var points: [Point] = []
        for segment in shape.segments {
            for point in segment.flattened() where points.last != point {
                points.append(point)
            }
        }
        self.init(points: points)
    }

    public var length: Double { distances.last ?? 0 }

    public func point(at distance: Double) -> Point {
        guard let first = points.first else { return .zero }
        let target = min(max(distance, 0), length)
        for index in 1..<max(points.count, 1) where distances[index] >= target {
            let span = distances[index] - distances[index - 1]
            let t = span > 0 ? (target - distances[index - 1]) / span : 0
            return points[index - 1] + (points[index] - points[index - 1]) * t
        }
        return points.last ?? first
    }

    /// The stretch of the line between two distances, including any corners
    /// in between.
    public func slice(from start: Double, to end: Double) -> [Point] {
        let low = min(max(min(start, end), 0), length)
        let high = min(max(max(start, end), 0), length)
        var result = [point(at: low)]
        for (index, distance) in distances.enumerated() where distance > low && distance < high {
            result.append(points[index])
        }
        result.append(point(at: high))
        return result
    }
}

/// A place where two pipes of one tile cross, and which goes over.
public struct Crossing: Hashable, Sendable {
    public var coord: HexCoord
    public var first: Pipe
    public var second: Pipe
    /// Where they cross, from the tile's centre in tile units.
    public var point: Point
    /// How far along each pipe's centre line the crossing is.
    public var firstDistance: Double
    public var secondDistance: Double
    /// Sine of the angle between the pipes. Near 0 for a glancing crossing.
    public var sharpness: Double
    public var firstIsOver: Bool

    public var over: Pipe { firstIsOver ? first : second }
    public var under: Pipe { firstIsOver ? second : first }
    public var overDistance: Double { firstIsOver ? firstDistance : secondDistance }

    /// How much of the over pipe to redraw either side of the crossing so it
    /// covers the full width of the pipe underneath.
    public func bridgeHalfLength(style: TileStyle) -> Double {
        let needed = style.pipeWidth / 2 / max(sharpness, 0.25) + style.pipeWidth * 0.15
        return min(needed, style.pipeWidth * 2.5)
    }
}

/// Over and under for every crossing in a maze, chosen so that each path
/// goes over, under, over, under as it is followed.
public struct Weave: Sendable {
    public let crossings: [Crossing]
    /// Crossings where alternation could not be honoured. Zero for any maze
    /// whose pipes cross cleanly.
    public let conflicts: Int
    private let byCoord: [HexCoord: [Crossing]]

    init(crossings: [Crossing], conflicts: Int) {
        self.crossings = crossings
        self.conflicts = conflicts
        byCoord = Dictionary(grouping: crossings, by: \.coord)
    }

    public func crossings(at coord: HexCoord) -> [Crossing] {
        byCoord[coord] ?? []
    }
}

extension Tile {
    /// Every point where two of the tile's pipes cross. `firstIsOver` is set
    /// from stacking order: the pipe added later is on top.
    public func crossings(at coord: HexCoord = .origin) -> [Crossing] {
        let style = TileStyle(portsPerEdge: portsPerEdge)
        let lines = pipes.map { Polyline(PipeShape($0, style: style)) }
        var result: [Crossing] = []
        for i in pipes.indices {
            for j in pipes.indices where j > i {
                for hit in Self.intersections(lines[i], lines[j]) {
                    result.append(Crossing(
                        coord: coord, first: pipes[i], second: pipes[j], point: hit.point,
                        firstDistance: hit.firstDistance, secondDistance: hit.secondDistance,
                        sharpness: hit.sharpness, firstIsOver: false
                    ))
                }
            }
        }
        return result
    }

    private static func intersections(
        _ first: Polyline, _ second: Polyline
    ) -> [(point: Point, firstDistance: Double, secondDistance: Double, sharpness: Double)] {
        var hits: [(point: Point, firstDistance: Double, secondDistance: Double, sharpness: Double)] = []
        guard first.points.count > 1, second.points.count > 1 else { return hits }
        for i in 1..<first.points.count {
            let p = first.points[i - 1]
            let r = first.points[i] - p
            for j in 1..<second.points.count {
                let q = second.points[j - 1]
                let s = second.points[j] - q
                let cross = r.x * s.y - r.y * s.x
                guard abs(cross) > 1e-12 else { continue }
                let gap = q - p
                let t = (gap.x * s.y - gap.y * s.x) / cross
                let u = (gap.x * r.y - gap.y * r.x) / cross
                // Half-open ranges so a crossing exactly on a joint between
                // two pieces is counted once.
                guard t >= 0, t < 1, u >= 0, u < 1 else { continue }
                let lengths = (r.x * r.x + r.y * r.y).squareRoot() * (s.x * s.x + s.y * s.y).squareRoot()
                hits.append((
                    p + r * t,
                    first.distances[i - 1] + (first.distances[i] - first.distances[i - 1]) * t,
                    second.distances[j - 1] + (second.distances[j] - second.distances[j - 1]) * u,
                    lengths > 0 ? abs(cross) / lengths : 1
                ))
            }
        }
        return hits
    }
}

extension Maze {
    /// Works out an alternating weave for the whole maze.
    ///
    /// Following any path, consecutive crossings must differ: over then
    /// under. Each such pair is a constraint between two crossings, and the
    /// constraints are solved by fixing one crossing and letting the rest
    /// follow. For pipes that cross cleanly this always works out.
    public func weave() -> Weave {
        var crossings: [Crossing] = []
        var indexesByPipe: [PortRef: [Int]] = [:]
        for coord in cells.keys.sorted() {
            guard let placed = cells[coord] else { continue }
            for crossing in placed.oriented.crossings(at: coord) {
                indexesByPipe[PortRef(coord: coord, port: crossing.first.a), default: []].append(crossings.count)
                indexesByPipe[PortRef(coord: coord, port: crossing.second.a), default: []].append(crossings.count)
                crossings.append(crossing)
            }
        }

        // links[c] holds (other crossing, whether the two must differ in
        // "first is over").
        var links: [[(other: Int, differ: Bool)]] = Array(repeating: [], count: crossings.count)
        for path in paths.paths {
            // Every crossing the path meets, in order, with whether the path
            // is that crossing's first pipe.
            var visits: [(crossing: Int, isFirst: Bool)] = []
            for step in path.steps {
                let here = (indexesByPipe[PortRef(coord: step.coord, port: step.pipe.a)] ?? []).map { index in
                    let isFirst = crossings[index].first == step.pipe
                    return (index, isFirst, isFirst ? crossings[index].firstDistance : crossings[index].secondDistance)
                }
                let forwards = !step.runsBackwards
                for visit in here.sorted(by: { forwards ? $0.2 < $1.2 : $0.2 > $1.2 }) {
                    visits.append((visit.0, visit.1))
                }
            }
            guard visits.count > 1 else { continue }
            let pairs = path.isClosed ? visits.count : visits.count - 1
            for index in 0..<pairs {
                let a = visits[index]
                let b = visits[(index + 1) % visits.count]
                // The path is over at a crossing when "first is over" matches
                // "the path is the first pipe". Alternating means that flips.
                let differ = a.isFirst == b.isFirst
                links[a.crossing].append((b.crossing, differ))
                links[b.crossing].append((a.crossing, differ))
            }
        }

        var assigned: [Bool?] = Array(repeating: nil, count: crossings.count)
        var conflicts = 0
        for start in crossings.indices where assigned[start] == nil {
            assigned[start] = true
            var queue = [start]
            while let current = queue.popLast() {
                guard let value = assigned[current] else { continue }
                for link in links[current] {
                    let wanted = link.differ ? !value : value
                    if let existing = assigned[link.other] {
                        if existing != wanted { conflicts += 1 }
                    } else {
                        assigned[link.other] = wanted
                        queue.append(link.other)
                    }
                }
            }
        }
        for index in crossings.indices {
            crossings[index].firstIsOver = assigned[index] ?? false
        }
        // Each broken constraint is seen from both of its ends.
        return Weave(crossings: crossings, conflicts: conflicts / 2)
    }
}
