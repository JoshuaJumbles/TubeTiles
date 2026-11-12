import SwiftUI
import TubeKit

@main
struct TubeTilesApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// The app's top level: the editor, the library and the generator, sharing
/// one set of saved tiles.
struct RootView: View {
    enum Screen: Hashable {
        case editor, library, generator
    }

    @State private var screen: Screen = .editor
    @State private var library: LibraryModel
    @State private var editor: EditorModel
    @State private var generator: GeneratorModel
    @State private var archive: MazeArchive
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let library = SampleData.isRequested ? SampleData.library() : LibraryModel()
        _library = State(initialValue: library)
        _editor = State(initialValue: EditorModel(library: library))
        // Sample mode keeps its mazes in memory, like its tiles.
        let archive = MazeArchive(persists: !SampleData.isRequested)
        _archive = State(initialValue: archive)
        _generator = State(initialValue: GeneratorModel(library: library, archive: archive))
    }

    var body: some View {
        TabView(selection: $screen) {
            EditorView(model: editor)
                .tabItem { Label("Editor", systemImage: "pencil.and.outline") }
                .tag(Screen.editor)

            LibraryView(library: library) { tile, asCopy in
                // Edit the tile in its own library, so saving puts it back
                // where it came from.
                if let home = library.home(of: tile) {
                    library.select(home.id)
                }
                editor.libraryChanged()
                editor.open(tile, asCopy: asCopy)
                screen = .editor
            }
            .tabItem { Label("Library", systemImage: "square.grid.2x2") }
            .tag(Screen.library)

            GeneratorView(model: generator, archive: archive)
                .tabItem { Label("Generator", systemImage: "circle.hexagongrid") }
                .tag(Screen.generator)
        }
        // Switching library, or editing its rules, on one screen has to
        // reach the others.
        .onChange(of: library.current) { _, _ in
            editor.libraryChanged()
            generator.libraryChanged()
        }
        .onAppear {
            // A cell goes from the generator to the editor to have a tile
            // drawn for it, and the finished tile comes back.
            generator.onDesign = { gap in
                editor.design(for: gap)
                screen = .editor
            }
            editor.onPlace = { tile, coord in
                generator.place(tile, at: coord)
                screen = .generator
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Do not wait for the autosave delay when the app is leaving.
            if phase != .active { generator.writeWorkingCopy() }
        }
    }
}
