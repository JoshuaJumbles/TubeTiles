import SwiftUI
import TubeKit

/// The tile editor: canvas beside its controls on wide screens, stacked on
/// narrow ones.
struct EditorView: View {
    var model: EditorModel

    private static let paper = TilePalette.paper

    var body: some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width > proxy.size.height
            let layout = isWide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            layout {
                canvasArea
                if isWide {
                    // Beside the canvas: a fixed column that scrolls if the
                    // screen is short, as on a phone held sideways.
                    ScrollView {
                        EditorPanel(model: model).padding(16)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(width: 340)
                    .frame(maxHeight: .infinity)
                    .background(.background)
                } else {
                    // Below the canvas: only as tall as its controls.
                    EditorPanel(model: model)
                        .frame(maxWidth: 560)
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background(.background)
                }
            }
        }
        .background(Self.paper.ignoresSafeArea())
    }

    private var canvasArea: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text(model.tile.edgeCode.description)
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .accessibilityLabel("Edge code \(model.tile.edgeCode.description)")
                Text(model.message ?? hint)
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 10)
            .padding(.horizontal, 16)

            TileCanvas(model: model)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hint: String {
        if model.selectedPipe != nil { return "Pipe selected. Delete it, or tap elsewhere." }
        if model.selectedPort != nil { return "Tap a green port to finish the pipe." }
        if model.kind.isDeadEnd { return "Tap a green port to end a pipe there in a room." }
        return "Tap or drag between two ports to draw a pipe."
    }
}

/// Controls for the editor: pipe kind, edit actions, library and saving.
private struct EditorPanel: View {
    var model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pipe").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(model.allowedKinds, id: \.self) { kind in
                        KindButton(kind: kind, isSelected: model.kind == kind) {
                            model.choose(kind)
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Button { model.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                    .disabled(!model.canUndo)
                Button { model.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                    .disabled(!model.canRedo)
                Spacer()
                Button(role: .destructive) { model.deleteSelectedPipe() } label: {
                    Label("Delete pipe", systemImage: "trash")
                }
                .disabled(model.selectedPipe == nil)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)

            HStack(spacing: 10) {
                Button { model.addRandomPipe() } label: {
                    Label("Add random", systemImage: "die.face.5").frame(maxWidth: .infinity)
                }
                Button { model.fillRandomly() } label: {
                    Label("Fill", systemImage: "sparkles").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)

            LabeledContent("Library") {
                Picker("Library", selection: Binding(
                    get: { model.libraryID }, set: { model.chooseLibrary($0) }
                )) {
                    ForEach(model.libraries) { library in
                        Text("\(library.name) · \(library.portsPerEdge) ports").tag(library.id)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack(spacing: 10) {
                Button { model.newTile() } label: {
                    Label("New tile", systemImage: "plus.square").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.tile.pipes.isEmpty)

                Button { model.save() } label: {
                    Label(model.isSaved ? "Update" : "Save", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.tile.pipes.isEmpty)
            }

            Text("^[\(model.savedTileCount) tile](inflect: true) in \u{201C}\(model.libraryName)\u{201D}. New libraries are made on the Library tab.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    EditorView(model: EditorModel(library: LibraryModel(store: nil)))
}
