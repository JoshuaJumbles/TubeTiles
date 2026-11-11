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
                    .foregroundStyle(Color(white: 0.15))
                    .accessibilityLabel("Edge code \(model.tile.edgeCode.description)")
                Text(model.message ?? hint)
                    .font(.footnote)
                    .foregroundStyle(Color(white: 0.35))
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
        return "Tap or drag between two ports to draw a pipe."
    }
}

/// Controls for the editor: pipe kind, edit actions, port count and saving.
private struct EditorPanel: View {
    var model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pipe").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(PipeKind.allCases, id: \.self) { kind in
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

            Stepper(
                "\(model.tile.portsPerEdge) ports per edge",
                value: Binding(
                    get: { model.tile.portsPerEdge },
                    set: { model.setPortsPerEdge($0) }
                ),
                in: EditorModel.portRange
            )

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

            Text("^[\(model.savedTileCount) tile](inflect: true) in the \(model.tile.portsPerEdge)-port library")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// A pipe kind shown as a miniature tile.
private struct KindButton: View {
    var kind: PipeKind
    var isSelected: Bool
    var action: () -> Void

    private var title: String {
        switch kind {
        case .bezier: "Curve"
        case .corner: "Corner"
        case .roomSmall: "Room S"
        case .roomMedium: "Room M"
        case .roomLarge: "Room L"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Canvas { context, size in
                    let frame = TileFrame(fitting: size, padding: 3)
                    let style = TileStyle(portsPerEdge: 3)
                    let hex = TileRenderer.hexPath(in: frame)
                    context.fill(hex, with: .color(.white))
                    var clipped = context
                    clipped.clip(to: hex)
                    let sample = Pipe(kind, a: Port(edge: 5, slot: 1), b: Port(edge: 1, slot: 1))
                    TileRenderer.draw(sample, style: style, in: frame, context: &clipped)
                    context.stroke(hex, with: .color(Color(white: 0.3)), lineWidth: 1)
                }
                .frame(height: 40)
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    EditorView(model: EditorModel(library: LibraryModel(store: nil)))
}
