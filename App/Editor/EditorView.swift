import SwiftUI
import TubeKit

/// The tile editor: canvas beside its controls on wide screens, stacked on
/// narrow ones.
struct EditorView: View {
    var model: EditorModel

    @State private var showsTools = false

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
                // A hex never reaches the corners of its area, so the tool
                // button sits there without covering any of the tile: bottom
                // right, where a thumb reaches it.
                .overlay(alignment: .bottomTrailing) {
                    toolButton.padding(10)
                }
                // Another free corner: a warning that stays up, whatever the
                // line under the title is saying.
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let status = model.gapStatus {
                            gapBadge(status)
                        }
                        if let note = model.duplicateNote {
                            badge(note, symbol: "square.on.square", tint: TilePalette.caution)
                        }
                    }
                    .padding(10)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func badge(_ text: String, symbol: String, tint: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(TilePalette.face))
            .overlay(Capsule().stroke(tint, lineWidth: 1.5))
    }

    /// How the tile stands against the gap it is drawn for, with a way to
    /// stop drawing for the gap.
    private func gapBadge(_ status: String) -> some View {
        let tint = model.fitsGap ? TilePalette.positive : Color.accentColor
        return HStack(spacing: 6) {
            Label(status, systemImage: model.fitsGap ? "checkmark.circle.fill" : "puzzlepiece.extension")
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Button { model.dismissGap() } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop drawing for the gap")
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 2)
        .background(Capsule().fill(TilePalette.face))
        .overlay(Capsule().stroke(tint, lineWidth: 1.5))
    }

    /// Shows the tool in use, and opens the choice of tools.
    private var toolButton: some View {
        Button { showsTools = true } label: {
            ToolBadge(
                title: model.isErasing ? "Erase" : model.kind.shortTitle,
                tint: model.isErasing ? TilePalette.negative : .accentColor
            ) {
                if model.isErasing {
                    Image(systemName: "eraser")
                        .font(.title2)
                        .foregroundStyle(TilePalette.negative)
                } else {
                    KindIcon(kind: model.kind)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tool: \(model.isErasing ? "Eraser" : model.kind.shortTitle)")
        .popover(isPresented: $showsTools) {
            toolPicker
                .presentationCompactAdaptation(.popover)
        }
    }

    /// The pipe kinds the library allows, and the eraser.
    private var toolPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(64), spacing: 8), count: 4), spacing: 8) {
            ForEach(model.allowedKinds, id: \.self) { kind in
                KindButton(kind: kind, isSelected: !model.isErasing && model.kind == kind) {
                    model.choose(kind)
                    showsTools = false
                }
            }
            ToolCell(title: "Erase", isSelected: model.isErasing) {
                model.chooseEraser()
                showsTools = false
            } icon: {
                Image(systemName: "eraser")
                    .font(.title3)
                    .foregroundStyle(TilePalette.negative)
            }
        }
        .padding(14)
    }

    private var hint: String {
        if model.isErasing { return "Tap a pipe, or drag across several, to erase." }
        if model.fitsGap, model.selectedPort == nil, model.selectedPipe == nil {
            return "It fits. Save & place puts it in the maze."
        }
        if model.gap != nil, model.selectedPort == nil, model.selectedPipe == nil, !model.kind.isDeadEnd {
            return "Ringed ports need a pipe. Crossed ports must stay empty."
        }
        if model.selectedPipe != nil { return "Pipe selected. Delete it, or tap elsewhere." }
        if model.selectedPort != nil { return "Tap a green port to finish the pipe." }
        if model.kind.isDeadEnd { return "Tap a green port to end a pipe there in a room." }
        return "Tap or drag between two ports to draw a pipe."
    }
}

/// Controls for the editor: edit actions, library and saving. The tool in
/// use is chosen from the button on the canvas.
private struct EditorPanel: View {
    var model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
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
                    Label("New", systemImage: "plus.square").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.tile.pipes.isEmpty)
                .accessibilityLabel("New tile")

                // Carry on from this tile as a separate one.
                Button { model.makeVariant() } label: {
                    Label("Variant", systemImage: "plus.square.on.square").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.tile.pipes.isEmpty)
                .accessibilityLabel("New variant of this tile")

                if model.fitsGap {
                    // Drawn for a gap in the maze and it fits: save it and
                    // go back to see it in place.
                    Button { model.saveAndPlace() } label: {
                        Text("Save & place")
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(TilePalette.positive)
                } else {
                    Button { model.save() } label: {
                        Label(model.isSaved ? "Update" : "Save", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.tile.pipes.isEmpty)
                }
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
