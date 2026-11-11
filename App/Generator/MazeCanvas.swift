import SwiftUI
import TubeKit

/// Draws the maze being worked on, with its editing overlays, and reports
/// taps on cells and on the outline.
struct MazeCanvas: View {
    var model: GeneratorModel

    private static let open = Color(red: 0.85, green: 0.45, blue: 0.10)

    var body: some View {
        GeometryReader { proxy in
            let maze = model.maze
            let layout = MazeLayout(size: proxy.size, radius: maze.radius, padding: 28)
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
            // Touch and hold a cell to make it a goal, or to stop it being
            // one.
            .gesture(
                LongPressGesture(minimumDuration: 0.45)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onEnded { value in
                        guard case let .second(true, drag?) = value,
                              let cell = layout.cell(at: drag.startLocation, in: maze)
                        else { return }
                        model.toggleGoal(cell.coord)
                    }
            )
            .accessibilityLabel("Maze canvas")
        }
    }
}
