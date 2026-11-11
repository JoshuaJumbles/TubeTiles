import SwiftUI
import TubeKit

/// The maze on its own, filling the screen: no controls, no grid and no path
/// colours, for judging the finished look. It can be zoomed and panned.
struct MazePreview: View {
    let maze: Maze
    private let weave: Weave

    @Environment(\.dismiss) private var dismiss
    @State private var viewport = Viewport()
    @State private var showsControls = true

    init(maze: Maze) {
        self.maze = maze
        // Worked out once, so zooming does not redo it on every frame.
        weave = maze.weave()
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = MazeLayout(size: proxy.size, radius: maze.radius, padding: 20, viewport: viewport)
            Canvas { context, _ in
                MazeRenderer.draw(maze, weave: weave, layout: layout, context: &context, showsCells: false)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) { showsControls.toggle() }
            }
            .viewportGestures($viewport, in: proxy.size)
        }
        // One flat colour, the same as a tile's face, so no tile edges show.
        .background(TilePalette.face.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            if showsControls {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(TilePalette.paper))
                        .foregroundStyle(Color.primary)
                }
                .accessibilityLabel("Close preview")
                .padding(16)
                .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if showsControls {
                Text(viewport.isDefault ? "Pinch to zoom. Tap to hide or show the close button." : "Drag to move around.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(TilePalette.paper))
                    .padding(.bottom, 24)
                    .transition(.opacity)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task {
            // Leave the controls up long enough to be noticed, then clear
            // the screen.
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeInOut(duration: 0.4)) { showsControls = false }
        }
    }
}
