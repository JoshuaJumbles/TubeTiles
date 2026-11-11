import Foundation

/// Writes a maze as an SVG drawing built for editing in a vector tool.
///
/// The drawing is in named groups, back to front:
///
/// - `cells`: the outline of each tile.
/// - `walls`: every path as one continuous line, at full pipe width.
/// - `tubes`: the same lines again, narrower, forming the pipe interiors.
/// - `rooms`: the circular rooms.
/// - `openings`: the open pipe ends at the entrance and exit, if any.
/// - `crossings`: a short piece of the upper pipe at each crossing, drawn
///   last so it bridges the pipe beneath.
///
/// Each path is a single outline that runs through every tile it visits, so
/// restyling the `walls` or `tubes` group restyles whole paths at once.
public enum MazeSVG {
    public struct Options: Sendable {
        /// Size of one tile's circumradius, in SVG units.
        public var cellSize = 100.0
        public var padding = 40.0
        public var ink = "#141414"
        public var tube = "#ffffff"
        /// Fill for the page, or nil for a transparent background.
        public var background: String? = nil
        public var includesCells = true
        /// A tube colour per path, in the order of `Maze.paths`. Paths
        /// without an entry use `tube`.
        public var pathColors: [Int: String] = [:]

        public init() {}
    }

    /// How far the pipe at an opening sticks out past the outline, in tile
    /// units.
    public static let openingLength = 0.3

    public static func render(_ maze: Maze, options: Options = Options()) -> String {
        let style = TileStyle(portsPerEdge: maze.portsPerEdge)
        let scale = options.cellSize
        let width = (3 * Double(maze.radius) + 2) * scale + options.padding * 2
        let height = HexGeometry.inradius * 2 * Double(2 * maze.radius + 1) * scale + options.padding * 2

        func place(_ local: Point, in coord: HexCoord) -> Point {
            let center = coord.center
            return Point(x: width / 2 + (center.x + local.x) * scale, y: height / 2 + (center.y + local.y) * scale)
        }
        func number(_ value: Double) -> String {
            String(format: "%.2f", value)
        }
        func text(_ point: Point) -> String {
            "\(number(point.x)) \(number(point.y))"
        }

        let paths = maze.paths
        let weave = maze.weave()
        let outer = number(style.pipeWidth * scale)
        let inner = number((style.pipeWidth - style.wallThickness * 2) * scale)

        /// One path as SVG path data, running through each tile in turn.
        func data(for path: MazePath) -> String {
            var commands: [String] = []
            for step in path.steps {
                var segments = PipeShape(step.pipe, style: style).segments
                if step.runsBackwards {
                    segments = segments.reversed().map { segment in
                        switch segment {
                        case let .line(start, end): .line(end, start)
                        case let .cubic(start, c1, c2, end): .cubic(end, control1: c2, control2: c1, start)
                        }
                    }
                }
                for segment in segments {
                    switch segment {
                    case let .line(start, end):
                        if commands.isEmpty { commands.append("M \(text(place(start, in: step.coord)))") }
                        commands.append("L \(text(place(end, in: step.coord)))")
                    case let .cubic(start, c1, c2, end):
                        if commands.isEmpty { commands.append("M \(text(place(start, in: step.coord)))") }
                        commands.append(
                            "C \(text(place(c1, in: step.coord))) \(text(place(c2, in: step.coord))) \(text(place(end, in: step.coord)))"
                        )
                    }
                }
            }
            if path.isClosed { commands.append("Z") }
            return commands.joined(separator: " ")
        }

        func tubeColor(_ index: Int?) -> String {
            index.flatMap { options.pathColors[$0] } ?? options.tube
        }

        var lines: [String] = []
        lines.append(#"<?xml version="1.0" encoding="UTF-8"?>"#)
        lines.append(
            #"<svg xmlns="http://www.w3.org/2000/svg" width="\#(number(width))" height="\#(number(height))" viewBox="0 0 \#(number(width)) \#(number(height))">"#
        )
        if let background = options.background {
            lines.append(#"  <rect id="background" width="100%" height="100%" fill="\#(background)"/>"#)
        }

        if options.includesCells {
            lines.append(#"  <g id="cells" fill="none" stroke="\#(options.ink)" stroke-opacity="0.15" stroke-width="1">"#)
            for coord in maze.coords where maze.cells[coord] != nil {
                let corners = (0..<HexGeometry.edgeCount).map { text(place(HexGeometry.corner($0), in: coord)) }
                lines.append(#"    <polygon points="\#(corners.joined(separator: " "))"/>"#)
            }
            lines.append("  </g>")
        }

        let allData = paths.paths.map(data)
        lines.append(
            #"  <g id="walls" fill="none" stroke="\#(options.ink)" stroke-width="\#(outer)" stroke-linecap="round" stroke-linejoin="round">"#
        )
        for (index, data) in allData.enumerated() {
            lines.append(#"    <path id="wall-\#(index + 1)" d="\#(data)"/>"#)
        }
        lines.append("  </g>")

        lines.append(#"  <g id="tubes" fill="none" stroke-width="\#(inner)" stroke-linecap="round" stroke-linejoin="round">"#)
        for (index, data) in allData.enumerated() {
            lines.append(#"    <path id="tube-\#(index + 1)" stroke="\#(tubeColor(index))" d="\#(data)"/>"#)
        }
        lines.append("  </g>")

        lines.append(#"  <g id="rooms">"#)
        for coord in maze.cells.keys.sorted() {
            for pipe in maze.cells[coord]?.oriented.pipes ?? [] {
                guard let room = PipeShape(pipe, style: style).room else { continue }
                let center = place(room.center, in: coord)
                let position = #"cx="\#(number(center.x))" cy="\#(number(center.y))""#
                lines.append(#"    <circle \#(position) r="\#(number(room.diameter / 2 * scale))" fill="\#(options.ink)"/>"#)
                lines.append(
                    #"    <circle \#(position) r="\#(number((room.diameter / 2 - style.wallThickness) * scale))" fill="\#(tubeColor(paths.index(of: pipe, at: coord)))"/>"#
                )
            }
        }
        lines.append("  </g>")

        // A short length of open pipe outside the outline at each opening.
        if !maze.openings.isEmpty {
            lines.append(#"  <g id="openings" fill="none" stroke-linecap="butt">"#)
            for opening in maze.openings.sorted(by: { ($0.coord, $0.port) < ($1.coord, $1.port) }) {
                let start = HexGeometry.position(of: opening.port, portsPerEdge: maze.portsPerEdge)
                let outward = HexGeometry.inwardDirection(edge: opening.port.edge) * -1
                let end = start + outward * MazeSVG.openingLength
                let mouth = start + outward * (MazeSVG.openingLength + style.wallThickness)
                let index = paths.index(of: opening)
                lines.append(
                    #"    <path stroke="\#(options.ink)" stroke-width="\#(outer)" d="M \#(text(place(start, in: opening.coord))) L \#(text(place(end, in: opening.coord)))"/>"#
                )
                lines.append(
                    #"    <path stroke="\#(tubeColor(index))" stroke-width="\#(inner)" d="M \#(text(place(start, in: opening.coord))) L \#(text(place(mouth, in: opening.coord)))"/>"#
                )
            }
            lines.append("  </g>")
        }

        lines.append(#"  <g id="crossings" fill="none" stroke-linecap="butt" stroke-linejoin="round">"#)
        for crossing in weave.crossings {
            let line = Polyline(PipeShape(crossing.over, style: style))
            let half = crossing.bridgeHalfLength(style: style)
            let points = line.slice(from: crossing.overDistance - half, to: crossing.overDistance + half)
                .map { text(place($0, in: crossing.coord)) }
            let data = "M " + points.joined(separator: " L ")
            lines.append("    <g>")
            lines.append(#"      <path stroke="\#(options.ink)" stroke-width="\#(outer)" d="\#(data)"/>"#)
            lines.append(
                #"      <path stroke="\#(tubeColor(paths.index(of: crossing.over, at: crossing.coord)))" stroke-width="\#(inner)" d="\#(data)"/>"#
            )
            lines.append("    </g>")
        }
        lines.append("  </g>")
        lines.append("</svg>")
        return lines.joined(separator: "\n") + "\n"
    }
}
