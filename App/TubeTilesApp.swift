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

/// The app's top level: the editor and the library, sharing one set of
/// saved tiles.
struct RootView: View {
    enum Screen: Hashable {
        case editor, library
    }

    @State private var screen: Screen = .editor
    @State private var library: LibraryModel
    @State private var editor: EditorModel

    init() {
        let library = SampleData.isRequested ? SampleData.library() : LibraryModel()
        _library = State(initialValue: library)
        _editor = State(initialValue: EditorModel(library: library))
    }

    var body: some View {
        TabView(selection: $screen) {
            EditorView(model: editor)
                .tabItem { Label("Editor", systemImage: "pencil.and.outline") }
                .tag(Screen.editor)

            LibraryView(library: library) { tile, asCopy in
                editor.open(tile, asCopy: asCopy)
                screen = .editor
            }
            .tabItem { Label("Library", systemImage: "square.grid.2x2") }
            .tag(Screen.library)
        }
    }
}
