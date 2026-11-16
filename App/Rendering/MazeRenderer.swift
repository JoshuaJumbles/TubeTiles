import SwiftUI
import TubeKit

/// How a maze's grid maps into a view: where the origin cell sits and how
/// many points one tile unit is.
struct MazeLayout {
    var origin: CGPoint
    var scale: CGFloat

    /// The layout that fits the whole maze inside `size`, then zoomed and
    /// moved by `viewport`. A masked maze is fitted to its mask, which may
    /// sit off to one side of the origin cell.
    init(size: CGSize, maze: Maze, padding: CGFloat, viewport: Viewport = Viewport()) {
        // An unmasked region spans 3r + 2 units across and sqrt(3)(2r + 1)
        // tall, centred on the origin cell.
        let bounds = maze.mask?.bounds
        let across = bounds.map { $0.max.x - $0.min.x } ?? 3 * Double(maze.radius) + 2
        let tall = bounds.map { $0.max.y - $0.min.y } ?? HexGeometry.inradius * 2 * Double(2 * maze.radius + 1)
        let middle = bounds.map { ($0.min + $0.max) * 0.5 } ?? .zero
        let fit = max(1, min((size.width - padding * 2) / across, (size.height - padding * 2) / tall))
        scale = fit * viewport.zoom
        origin = CGPoint(
            x: size.width / 2 + viewport.offset.width - middle.x * scale,
            y: size.height / 2 + viewport.offset.height - middle.y * scale
        )
    }

    /// Where a point of the maze's plane falls in the view.
    func point(_ point: Point) -> CGPoint {
        CGPoint(x: origin.x + point.x * scale, y: origin.y + point.y * scale)
    }

    /// The outline of a mask in the view. `offset` moves it, in tile units,
    /// to show where it is being dragged to.
    func path(for mask: Mask, offset: Point = .zero) -> Path {
        var result = Path()
        for shape in mask.shapes {
            let corner = point(Point(
                x: shape.center.x + offset.x - shape.width / 2, y: shape.center.y + offset.y - shape.height / 2
            ))
            let rect = Path(CGRect(x: corner.x, y: corner.y, width: shape.width * scale, height: shape.height * scale))
            result = shape.subtracts ? result.subtracting(rect) : result.union(rect)
        }
        return result
    }

    func frame(for coord: HexCoord) -> TileFrame {
        let center = coord.center
        return TileFrame(
            center: CGPoint(x: origin.x + center.x * scale, y: origin.y + center.y * scale),
            scale: scale
        )
    }

    func gridPoint(_ point: CGPoint) -> Point {
        Point(x: (point.x - origin.x) / scale, y: (point.y - origin.y) / scale)
    }

    /// The outline port nearest a point outside the region, if the point is
    /// close enough to the outline to mean it. Ports that fail `allowed` are
    /// passed over, so a tap beside one reaches the nearest usable port.
    func outlinePort(at point: CGPoint, in maze: Maze, allowed: (PortRef) -> Bool = { _ in true }) -> PortRef? {
        let target = gridPoint(point)
        func position(_ ref: PortRef) -> Point {
            ref.coord.center + HexGeometry.position(of: ref.port, portsPerEdge: maze.portsPerEdge)
        }
        let nearest = maze.outlinePorts.filter(allowed).min { position($0).distance(to: target) < position($1).distance(to: target) }
        guard let nearest, position(nearest).distance(to: target) <= 0.6 else { return nil }
        return nearest
    }

    /// The cell under a point, and where in that cell the point falls,
    /// measured from the cell's centre in tile units.
    func cell(at point: CGPoint, in maze: Maze) -> (coord: HexCoord, local: Point)? {
        let target = gridPoint(point)
        let nearest = maze.coords.min { $0.center.distance(to: target) < $1.center.distance(to: target) }
        guard let nearest, nearest.center.distance(to: target) <= 1 else { return nil }
        return (nearest, target - nearest.center)
    }
}

/// Draws whole mazes. The generator and the saved-maze thumbnails both go
/// through here, so a maze looks the same wherever it appears.
enum MazeRenderer {
    /// Draws the region, its tiles woven together, and any openings.
    ///
    /// - Parameters:
    ///   - showsCells: Whether to draw the tiles' faces, the empty cells and
    ///     the grid. Off leaves only the pipes, for a view of the finished
    ///     maze.
    ///   - palette: The colours for the pipe ending at a given port. Defaults
    ///     to plain walls and tubes.
    static func draw(
        _ maze: Maze,
        weave: Weave,
        layout: MazeLayout,
        context: inout GraphicsContext,
        showsGrid: Bool = true,
        showsCells: Bool = true,
        palette: (PortRef) -> TilePalette = { _ in .standard }
    ) {
        let style = TileStyle(portsPerEdge: maze.portsPerEdge)
        let grid = TilePalette.outline.opacity(0.14)

        // Tile faces and the grid stop at the mask. Pipes need no clipping:
        // they are only ever placed inside it.
        let bounds = maze.mask.map { layout.path(for: $0) }
        var cellContext = context
        if let bounds {
            if showsCells { context.fill(bounds, with: .color(TilePalette.emptyCell)) }
            cellContext.clip(to: bounds)
        }

        for coord in maze.coords {
            let frame = layout.frame(for: coord)
            let hex = TileRenderer.hexPath(in: frame)
            if let placed = maze.cells[coord] {
                if showsCells {
                    cellContext.fill(hex, with: .color(TilePalette.face))
                }
                var clipped = context
                clipped.clip(to: hex)
                for pipe in placed.oriented.pipes {
                    TileRenderer.draw(
                        pipe, style: style, in: frame, context: &clipped,
                        palette: palette(PortRef(coord: coord, port: pipe.a))
                    )
                }
                // Stacking order alone cannot weave, so each crossing gets
                // the upper pipe redrawn across it.
                for crossing in weave.crossings(at: coord) {
                    TileRenderer.drawBridge(
                        crossing, style: style, in: frame, context: &clipped,
                        palette: palette(PortRef(coord: coord, port: crossing.over.a))
                    )
                }
            } else if showsCells {
                cellContext.fill(hex, with: .color(TilePalette.emptyCell))
            }
            if showsGrid && showsCells {
                cellContext.stroke(hex, with: .color(grid), lineWidth: 1)
            }
        }

        if let bounds {
            context.stroke(bounds, with: .color(TilePalette.outline), style: StrokeStyle(lineWidth: 1.5, lineJoin: .miter))
        }

        // The entrance and exit: a short length of open pipe leading out of
        // the region.
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
            let colors = palette(opening)
            context.stroke(
                line(length: MazeSVG.openingLength), with: .color(colors.ink),
                style: StrokeStyle(lineWidth: style.pipeWidth * frame.scale, lineCap: .butt)
            )
            context.stroke(
                line(length: MazeSVG.openingLength + style.wallThickness), with: .color(colors.tube),
                style: StrokeStyle(lineWidth: (style.pipeWidth - style.wallThickness * 2) * frame.scale, lineCap: .butt)
            )
        }
    }
}

/// A small, read-only picture of a maze.
struct MazeThumbnail: View {
    var maze: Maze

    var body: some View {
        Canvas { context, size in
            let layout = MazeLayout(size: size, maze: maze, padding: 6)
            MazeRenderer.draw(maze, weave: maze.weave(), layout: layout, context: &context, showsGrid: false)
        }
        .aspectRatio(1, contentMode: .fit)
        // Tiles are the same colour as the cards they sit on, so give the
        // picture its own backdrop.
        .background(RoundedRectangle(cornerRadius: 10).fill(TilePalette.paper))
        .accessibilityHidden(true)
    }
}
