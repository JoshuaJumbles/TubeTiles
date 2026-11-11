import SwiftUI
import TubeKit

/// Draws the maze region and its tiles, and reports taps on cells.
struct MazeCanvas: View {
    var model: GeneratorModel

    private static let emptyCell = Color(red: 0.90, green: 0.88, blue: 0.82)
    private static let grid = Color(white: 0.25).opacity(0.12)
    private static let open = Color(red: 0.85, green: 0.45, blue: 0.10)

    /// The colours for one path. A loop keeps its colour as long as its
    /// first pipe stays put, so merging elsewhere does not reshuffle the rest.
    /// Kept loops are drawn plain, and loose strands grey.
    private static func palette(for path: MazePath?, isKept: Bool) -> TilePalette {
        guard let path, let first = path.steps.first, !isKept else { return .standard }
        guard path.isClosed else {
            return TilePalette(tube: Color(white: 0.86))
        }
        let seed = first.coord.q * 73 + first.coord.r * 151 + first.pipe.a.edge * 31 + first.pipe.a.slot * 17
        let hue = (Double(seed) * 0.618034).truncatingRemainder(dividingBy: 1)
        return TilePalette(tube: Color(hue: hue < 0 ? hue + 1 : hue, saturation: 0.45, brightness: 0.97))
    }

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
            let layout = Layout(size: proxy.size, radius: maze.radius, padding: 16)
            let openCells = Set(model.openCells)
            let selected = model.selected
            let selectedImages = selected.map { Set(maze.images(of: $0, symmetry: model.symmetry)) } ?? []
            let showsPaths = model.showsPaths
            let paths = model.paths
            let keptPaths = model.keptPaths(in: paths)

            Canvas { context, _ in
                for coord in maze.coords {
                    let frame = layout.frame(for: coord)
                    let hex = TileRenderer.hexPath(in: frame)
                    if let placed = maze.cells[coord] {
                        context.fill(hex, with: .color(TilePalette.face))
                        if showsPaths {
                            var clipped = context
                            clipped.clip(to: hex)
                            let style = TileStyle(portsPerEdge: maze.portsPerEdge)
                            for pipe in placed.oriented.pipes {
                                let index = paths.index(of: pipe, at: coord)
                                TileRenderer.draw(
                                    pipe, style: style, in: frame, context: &clipped,
                                    palette: Self.palette(
                                        for: index.map { paths.paths[$0] },
                                        isKept: index.map(keptPaths.contains) ?? false
                                    )
                                )
                            }
                        } else {
                            TileRenderer.draw(placed.oriented, in: frame, context: &context)
                        }
                    } else {
                        context.fill(hex, with: .color(Self.emptyCell))
                    }
                    context.stroke(hex, with: .color(Self.grid), lineWidth: 1)
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
                let cell = layout.cell(at: location, in: maze)
                model.tap(cell?.coord, local: cell?.local ?? .zero)
            }
            .accessibilityLabel("Maze canvas")
        }
    }
}
