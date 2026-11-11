import SwiftUI
import TubeKit

/// Draws the maze region and its tiles, and reports taps on cells.
struct MazeCanvas: View {
    var model: GeneratorModel

    private static let emptyCell = TilePalette.emptyCell
    private static let grid = TilePalette.outline.opacity(0.14)
    private static let open = Color(red: 0.85, green: 0.45, blue: 0.10)

    /// How the grid maps into the view: where the origin cell sits and how
    /// many points one tile unit is.
    private struct Layout {
        var origin: CGPoint
        var scale: CGFloat

        init(size: CGSize, radius: Int, padding: CGFloat) {
            // The region spans 3r + 2 units across and sqrt(3)(2r + 1) tall.
            let across = 3 * Double(radius) + 2
            let tall = HexGeometry.inradius * 2 * Double(2 * radius + 1)
            scale = max(1, min((size.width - padding * 2) / across, (size.height - padding * 2) / tall))
            origin = CGPoint(x: size.width / 2, y: size.height / 2)
        }

        func frame(for coord: HexCoord) -> TileFrame {
            let center = coord.center
            return TileFrame(
                center: CGPoint(x: origin.x + center.x * scale, y: origin.y + center.y * scale),
                scale: scale
            )
        }

        /// The outline port nearest a point outside the region, if the point
        /// is close enough to the outline to mean it.
        func outlinePort(at point: CGPoint, in maze: Maze) -> PortRef? {
            let target = Point(x: (point.x - origin.x) / scale, y: (point.y - origin.y) / scale)
            func position(_ ref: PortRef) -> Point {
                ref.coord.center + HexGeometry.position(of: ref.port, portsPerEdge: maze.portsPerEdge)
            }
            let nearest = maze.outlinePorts.min { position($0).distance(to: target) < position($1).distance(to: target) }
            guard let nearest, position(nearest).distance(to: target) <= 0.6 else { return nil }
            return nearest
        }

        /// The cell under a point, and where in that cell the point falls,
        /// measured from the cell's centre in tile units.
        func cell(at point: CGPoint, in maze: Maze) -> (coord: HexCoord, local: Point)? {
            let target = Point(x: (point.x - origin.x) / scale, y: (point.y - origin.y) / scale)
            let nearest = maze.coords.min { $0.center.distance(to: target) < $1.center.distance(to: target) }
            guard let nearest, nearest.center.distance(to: target) <= 1 else { return nil }
            return (nearest, target - nearest.center)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let maze = model.maze
            let layout = Layout(size: proxy.size, radius: maze.radius, padding: 28)
            let openCells = Set(model.openCells)
            let selected = model.selected
            let selectedImages = selected.map { Set(maze.images(of: $0, symmetry: model.symmetry)) } ?? []
            let showsPaths = model.showsPaths
            let paths = model.paths
            let keptPaths = model.keptPaths(in: paths)
            let weave = model.weave

            Canvas { context, _ in
                for coord in maze.coords {
                    let frame = layout.frame(for: coord)
                    let hex = TileRenderer.hexPath(in: frame)
                    if let placed = maze.cells[coord] {
                        context.fill(hex, with: .color(TilePalette.face))
                        var clipped = context
                        clipped.clip(to: hex)
                        let style = TileStyle(portsPerEdge: maze.portsPerEdge)
                        func palette(_ pipe: Pipe) -> TilePalette {
                            guard showsPaths, let index = paths.index(of: pipe, at: coord) else { return .standard }
                            return PathTint.palette(for: paths.paths[index], isKept: keptPaths.contains(index))
                        }
                        for pipe in placed.oriented.pipes {
                            TileRenderer.draw(pipe, style: style, in: frame, context: &clipped, palette: palette(pipe))
                        }
                        // Stacking order alone cannot weave, so each crossing
                        // gets the upper pipe redrawn across it.
                        for crossing in weave.crossings(at: coord) {
                            TileRenderer.drawBridge(
                                crossing, style: style, in: frame, context: &clipped, palette: palette(crossing.over)
                            )
                        }
                    } else {
                        context.fill(hex, with: .color(Self.emptyCell))
                    }
                    context.stroke(hex, with: .color(Self.grid), lineWidth: 1)
                }

                // The entrance and exit: a short length of open pipe leading
                // out of the region.
                let style = TileStyle(portsPerEdge: maze.portsPerEdge)
                for opening in maze.openings {
                    let frame = layout.frame(for: opening.coord)
                    let start = HexGeometry.position(of: opening.port, portsPerEdge: maze.portsPerEdge)
                    let outward = HexGeometry.inwardDirection(edge: opening.port.edge) * -1
                    func line(length: Double) -> Path {
                        var path = Path()
                        path.move(to: frame.point(start))
                        path.addLine(to: frame.point(start + outward * length))
                        return path
                    }
                    let palette: TilePalette = {
                        guard showsPaths, let index = paths.index(of: opening) else { return .standard }
                        return PathTint.palette(for: paths.paths[index], isKept: keptPaths.contains(index))
                    }()
                    context.stroke(
                        line(length: MazeSVG.openingLength), with: .color(palette.ink),
                        style: StrokeStyle(lineWidth: style.pipeWidth * frame.scale, lineCap: .butt)
                    )
                    context.stroke(
                        line(length: MazeSVG.openingLength + style.wallThickness), with: .color(palette.tube),
                        style: StrokeStyle(lineWidth: (style.pipeWidth - style.wallThickness * 2) * frame.scale, lineCap: .butt)
                    )
                }

                // Cells a pipe points into but that have no tile yet.
                for coord in openCells {
                    let hex = TileRenderer.hexPath(in: layout.frame(for: coord))
                    context.fill(hex, with: .color(Self.open.opacity(0.16)))
                    context.stroke(hex, with: .color(Self.open), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                }

                for coord in selectedImages {
                    let hex = TileRenderer.hexPath(in: layout.frame(for: coord))
                    context.stroke(
                        hex, with: .color(.accentColor.opacity(coord == selected ? 1 : 0.5)),
                        style: StrokeStyle(lineWidth: coord == selected ? 4 : 2.5, lineJoin: .round)
                    )
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                if let cell = layout.cell(at: location, in: maze) {
                    model.tap(cell.coord, local: cell.local)
                } else if let port = layout.outlinePort(at: location, in: maze) {
                    // Just outside the outline: an entrance or exit.
                    model.toggleOpening(port)
                } else {
                    model.tap(nil)
                }
            }
            .accessibilityLabel("Maze canvas")
        }
    }
}
