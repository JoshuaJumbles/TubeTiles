import SwiftUI
import TubeKit

/// Draws the maze being worked on, with its editing overlays, and reports
/// taps on cells and on the outline. Pinch to zoom, drag to pan. Every touch
/// is a plain tap; what it does is up to the tool in use.
struct MazeCanvas: View {
    @Bindable var model: GeneratorModel

    /// How far the bounds have been dragged, in points, while a drag with
    /// the Bounds tool is under way.
    @State private var boundsDrag: CGSize?

    private static let open = Color(red: 0.85, green: 0.45, blue: 0.10)

    var body: some View {
        GeometryReader { proxy in
            let maze = model.maze
            let layout = MazeLayout(size: proxy.size, maze: maze, padding: 28, viewport: model.viewport)
            let movesBounds = model.tool == .bounds
            let dragged = boundsDrag
            let openCells = Set(model.openCells)
            let selected = model.selected
            let selectedImages = selected.map { Set(maze.images(of: $0, symmetry: model.symmetry)) } ?? []
            let showsPaths = model.showsPaths
            let paths = model.paths
            let keptPaths = model.keptPaths(in: paths)
            let weave = model.weave

            Canvas { context, _ in
                MazeRenderer.draw(maze, weave: weave, layout: layout, context: &context) { ref in
                    guard showsPaths, let index = paths.index(of: ref) else { return .standard }
                    return PathTint.palette(for: paths.paths[index], isKept: keptPaths.contains(index))
                }

                // Marks on cells stop at the bounds, like the cells themselves.
                let whole = context
                var context = context
                if let mask = maze.mask {
                    context.clip(to: layout.path(for: mask))
                }

                // Goals waiting for their tile.
                for coord in maze.goals where maze.cells[coord] == nil {
                    let frame = layout.frame(for: coord)
                    for radius in [0.55, 0.25] {
                        let size = radius * 2 * frame.scale
                        context.stroke(
                            Path(ellipseIn: CGRect(
                                x: frame.center.x - size / 2, y: frame.center.y - size / 2, width: size, height: size
                            )),
                            with: .color(.accentColor), lineWidth: 2
                        )
                    }
                }

                // Cells a pipe points into but that have no tile yet.
                for coord in openCells where !maze.goals.contains(coord) {
                    let hex = TileRenderer.hexPath(in: layout.frame(for: coord))
                    context.fill(hex, with: .color(Self.open.opacity(0.16)))
                    context.stroke(hex, with: .color(Self.open), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                }

                if movesBounds, let mask = maze.mask {
                    // The centre of the grid, which symmetry turns about.
                    let centre = layout.point(.zero)
                    var cross = Path()
                    cross.move(to: CGPoint(x: centre.x - 9, y: centre.y))
                    cross.addLine(to: CGPoint(x: centre.x + 9, y: centre.y))
                    cross.move(to: CGPoint(x: centre.x, y: centre.y - 9))
                    cross.addLine(to: CGPoint(x: centre.x, y: centre.y + 9))
                    whole.stroke(cross, with: .color(.accentColor), lineWidth: 2)
                    whole.stroke(
                        Path(ellipseIn: CGRect(x: centre.x - 5, y: centre.y - 5, width: 10, height: 10)),
                        with: .color(.accentColor), lineWidth: 2
                    )

                    // Where the bounds will be when the finger lifts.
                    let offset = dragged.map {
                        Point(x: $0.width / layout.scale, y: $0.height / layout.scale)
                    } ?? .zero
                    whole.stroke(
                        layout.path(for: mask, offset: offset), with: .color(.accentColor),
                        style: StrokeStyle(lineWidth: 2.5, dash: dragged == nil ? [] : [7, 5])
                    )
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
                } else if model.tool == .endpoint, let port = layout.outlinePort(
                    at: location, in: maze,
                    // An existing opening can always be tapped to remove it.
                    allowed: { maze.openings.contains($0) || model.allowsOpening(at: $0) }
                ) {
                    // Just outside the outline: an entrance or exit.
                    model.tapOutline(port)
                } else {
                    model.tap(nil)
                }
            }
            // With the Bounds tool a drag moves the bounds. They only take
            // their new place when the finger lifts, because tiles that no
            // longer fit are taken out.
            .gesture(movesBounds ? DragGesture(minimumDistance: 6)
                .onChanged { boundsDrag = $0.translation }
                .onEnded { value in
                    boundsDrag = nil
                    model.moveBounds(by: Point(
                        x: value.translation.width / layout.scale, y: value.translation.height / layout.scale
                    ))
                } : nil)
            .viewportGestures($model.viewport, in: proxy.size, pans: !movesBounds)
            // Zoomed in, the maze is larger than its area of the screen.
            .clipped()
            // The tool button has the bottom right corner.
            .overlay(alignment: .bottomLeading) {
                if !model.viewport.isDefault {
                    Button {
                        withAnimation(.snappy) { model.viewport = Viewport() }
                    } label: {
                        Label("Fit", systemImage: "arrow.down.right.and.arrow.up.left")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(TilePalette.face))
                            .foregroundStyle(Color.primary)
                    }
                    .accessibilityLabel("Fit the whole maze")
                    .padding(10)
                    .transition(.opacity)
                }
            }
            .accessibilityLabel("Maze canvas")
        }
    }
}
