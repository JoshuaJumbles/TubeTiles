import Foundation

/// Counts how many pipes cover each point of a tile, to enforce the overlap
/// rule: two pipes may cross, three may not.
///
/// The tile is sampled on a grid. Each pipe adds 1 where its stroke lies and
/// 2 over its room or corner bend, so nothing can cross those. Outside the
/// hex every cell starts at 1, so pipes cannot cross out there either. A cell
/// reaching 3 is a violation.
///
/// Because the grid is square, a tile packed right up to the limit can gain
/// or lose a few cells when rotated by 60 degrees. Tiles are only checked in
/// the orientation they were drawn in.
public struct CoverageMap: Sendable {
    public static let resolution = 192
    /// Half the side of the sampled square, a little larger than the hex.
    public static let extent = 1.15
    public static let limit: UInt8 = 3

    /// Side length of one sampled cell, in tile units.
    public static let sampleSize = extent * 2 / Double(resolution)

    public let style: TileStyle
    private var counts: [UInt8]

    private static func coordinate(_ index: Int) -> Double {
        -extent + (Double(index) + 0.5) * sampleSize
    }

    public init(style: TileStyle) {
        self.style = style
        let size = Self.resolution
        let root3 = (3.0).squareRoot()
        var counts = [UInt8](repeating: 0, count: size * size)
        for row in 0..<size {
            let y = abs(Self.coordinate(row))
            for column in 0..<size {
                let x = abs(Self.coordinate(column))
                let inside = y <= root3 / 2 && root3 * x + y <= root3
                if !inside { counts[row * size + column] = 1 }
            }
        }
        self.counts = counts
    }

    public init(tile: Tile) {
        self.init(style: TileStyle(portsPerEdge: tile.portsPerEdge))
        for pipe in tile.pipes {
            add(pipe)
        }
    }

    /// The cells one pipe covers, and the block of the grid they fall in.
    ///
    /// A pipe never counts against itself, so its cells are gathered here
    /// first (taking the larger weight where its parts overlap) and applied
    /// to the totals once.
    private struct Footprint {
        var weights: [UInt8]
        var rows: ClosedRange<Int>?
        var columns: ClosedRange<Int>?
    }

    private func footprint(of pipe: Pipe) -> Footprint {
        let size = Self.resolution
        let cell = Self.sampleSize
        let extent = Self.extent
        let shape = PipeShape(pipe, style: style)

        var stamps: [(start: Point, end: Point, radius: Double, weight: UInt8)] = []
        for segment in shape.segments {
            let points = segment.flattened()
            for (start, end) in zip(points, points.dropFirst()) {
                stamps.append((start, end, style.clearanceWidth / 2, 1))
            }
        }
        if let elbow = shape.elbow {
            stamps.append((elbow, elbow, style.elbowDiameter / 2, 2))
        }
        if let room = shape.room {
            stamps.append((room.center, room.center, room.diameter / 2, 2))
        }

        var weights = [UInt8](repeating: 0, count: size * size)
        var minRow = size, maxRow = -1, minColumn = size, maxColumn = -1

        weights.withUnsafeMutableBufferPointer { buffer in
            for stamp in stamps {
                let start = stamp.start, end = stamp.end, radius = stamp.radius
                func index(_ value: Double) -> Int {
                    Int(((value + extent) / cell).rounded(.down))
                }
                let firstColumn = max(0, index(min(start.x, end.x) - radius))
                let lastColumn = min(size - 1, index(max(start.x, end.x) + radius))
                let firstRow = max(0, index(min(start.y, end.y) - radius))
                let lastRow = min(size - 1, index(max(start.y, end.y) + radius))
                guard firstColumn <= lastColumn, firstRow <= lastRow else { continue }
                minRow = min(minRow, firstRow)
                maxRow = max(maxRow, lastRow)
                minColumn = min(minColumn, firstColumn)
                maxColumn = max(maxColumn, lastColumn)

                let spanX = end.x - start.x, spanY = end.y - start.y
                let lengthSquared = spanX * spanX + spanY * spanY
                let radiusSquared = radius * radius
                var row = firstRow
                while row <= lastRow {
                    let y = -extent + (Double(row) + 0.5) * cell
                    var column = firstColumn
                    while column <= lastColumn {
                        let x = -extent + (Double(column) + 0.5) * cell
                        var t = 0.0
                        if lengthSquared > 0 {
                            t = ((x - start.x) * spanX + (y - start.y) * spanY) / lengthSquared
                            t = min(1, max(0, t))
                        }
                        let dx = x - (start.x + spanX * t)
                        let dy = y - (start.y + spanY * t)
                        if dx * dx + dy * dy <= radiusSquared {
                            let cellIndex = row &* size &+ column
                            if buffer[cellIndex] < stamp.weight { buffer[cellIndex] = stamp.weight }
                        }
                        column &+= 1
                    }
                    row &+= 1
                }
            }
        }

        guard maxRow >= minRow, maxColumn >= minColumn else {
            return Footprint(weights: weights, rows: nil, columns: nil)
        }
        return Footprint(weights: weights, rows: minRow...maxRow, columns: minColumn...maxColumn)
    }

    /// Visits every cell of a footprint's block with the current count and
    /// the footprint's weight. Stops early if `body` returns false.
    private func scan(_ footprint: Footprint, _ body: (_ index: Int, _ count: UInt8, _ weight: UInt8) -> Bool) {
        guard let rows = footprint.rows, let columns = footprint.columns else { return }
        let size = Self.resolution
        counts.withUnsafeBufferPointer { counts in
            footprint.weights.withUnsafeBufferPointer { weights in
                var row = rows.lowerBound
                while row <= rows.upperBound {
                    var index = row &* size &+ columns.lowerBound
                    let last = row &* size &+ columns.upperBound
                    while index <= last {
                        let weight = weights[index]
                        if weight != 0, !body(index, counts[index], weight) { return }
                        index &+= 1
                    }
                    row &+= 1
                }
            }
        }
    }

    public mutating func add(_ pipe: Pipe) {
        let footprint = footprint(of: pipe)
        var updates: [(Int, UInt8)] = []
        scan(footprint) { index, count, weight in
            updates.append((index, count &+ weight))
            return true
        }
        for (index, value) in updates {
            counts[index] = value
        }
    }

    public func adding(_ pipe: Pipe) -> CoverageMap {
        var copy = self
        copy.add(pipe)
        return copy
    }

    /// Whether `pipe` can be added without breaking the overlap rule.
    public func fits(_ pipe: Pipe) -> Bool {
        var fits = true
        scan(footprint(of: pipe)) { _, count, weight in
            fits = count &+ weight < Self.limit
            return fits
        }
        return fits
    }

    /// Centres of the cells where adding `pipe` would break the rule, for
    /// showing where it does not fit.
    public func conflicts(adding pipe: Pipe) -> [Point] {
        let size = Self.resolution
        var points: [Point] = []
        scan(footprint(of: pipe)) { index, count, weight in
            if count &+ weight >= Self.limit {
                points.append(Point(x: Self.coordinate(index % size), y: Self.coordinate(index / size)))
            }
            return true
        }
        return points
    }

    /// Number of cells over the limit. Zero for any tile built through the
    /// placement rules.
    public var violationCount: Int {
        counts.reduce(0) { $0 + ($1 >= Self.limit ? 1 : 0) }
    }

    public var hasViolation: Bool { violationCount > 0 }
}
