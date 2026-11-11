import SwiftUI
import TubeKit

/// The maze generator: the growing maze beside its controls on wide screens,
/// stacked on narrow ones.
struct GeneratorView: View {
    var model: GeneratorModel

    var body: some View {
        GeometryReader { proxy in
            let isWide = proxy.size.width > proxy.size.height
            let layout = isWide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            layout {
                canvasArea
                if isWide {
                    ScrollView {
                        GeneratorPanel(model: model).padding(16)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(width: 340)
                    .frame(maxHeight: .infinity)
                    .background(.background)
                } else {
                    GeneratorPanel(model: model)
                        .frame(maxWidth: 560)
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background(.background)
                }
            }
        }
        .background(TilePalette.paper.ignoresSafeArea())
    }

    private var canvasArea: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text(model.summary)
                    .font(.headline)
                    .foregroundStyle(Color(white: 0.15))
                Text(model.message ?? hint)
                    .font(.footnote)
                    .foregroundStyle(Color(white: 0.35))
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 10)
            .padding(.horizontal, 16)

            MazeCanvas(model: model)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hint: String {
        if model.selected != nil { return "Tile selected. Swap or delete it, or tap elsewhere." }
        if model.maze.cells.isEmpty { return "Mazes grow from the middle and seal at the outline." }
        if !model.openCells.isEmpty { return "Dashed cells still need a tile." }
        if model.showsPaths { return "Each colour is one loop. Tap a loop to keep it out of merging." }
        return "Tap a tile to change it, or an empty cell to add one."
    }
}

/// Controls for the generator: growing, symmetry, size and hand edits.
private struct GeneratorPanel: View {
    @Bindable var model: GeneratorModel
    @State private var showsOptions = false

    private func name(_ symmetry: Symmetry) -> String {
        switch symmetry {
        case .none: "None"
        case .mirror: "Mirror"
        case .half: "Half turn"
        case .third: "Third turn"
        case .sixth: "Sixth turn"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Button { model.step() } label: {
                    Label("Step", systemImage: "forward.frame").frame(maxWidth: .infinity)
                }
                .disabled(model.isRunning)
                Button { model.toggleRunning() } label: {
                    Label(
                        model.activity == .growing ? "Pause" : "Grow",
                        systemImage: model.activity == .growing ? "pause.fill" : "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button { model.fill() } label: {
                    Label("Fill", systemImage: "sparkles").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)

            HStack(spacing: 10) {
                Button { model.rerollSelected() } label: {
                    Label("Swap tile", systemImage: "arrow.triangle.2.circlepath").frame(maxWidth: .infinity)
                }
                .disabled(model.selected == nil)
                Button(role: .destructive) { model.deleteSelected() } label: {
                    Label("Delete tile", systemImage: "trash").frame(maxWidth: .infinity)
                }
                .disabled(model.selected == nil)
                Button { model.clear() } label: {
                    Label("Clear", systemImage: "xmark.square").frame(maxWidth: .infinity)
                }
                .disabled(model.maze.cells.isEmpty)
            }
            .buttonStyle(.bordered)
            .labelStyle(.titleOnly)

            HStack(spacing: 10) {
                Button { model.toggleMerging() } label: {
                    Label(
                        model.activity == .merging ? "Pause" : "Merge loops",
                        systemImage: model.activity == .merging ? "pause.fill" : "arrow.triangle.merge"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!model.maze.isSealed)

                Toggle(isOn: $model.showsPaths) {
                    Label("Paths", systemImage: "paintpalette")
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
            }

            LabeledContent("Symmetry") {
                Picker("Symmetry", selection: $model.symmetry) {
                    ForEach(Symmetry.allCases, id: \.self) { Text(name($0)).tag($0) }
                }
                .pickerStyle(.menu)
            }

            Stepper(
                "Radius \(model.radius) · \(model.maze.cellCount) cells",
                value: Binding(get: { model.radius }, set: { model.setRadius($0) }),
                in: GeneratorModel.radiusRange
            )

            DisclosureGroup("Options", isExpanded: $showsOptions) {
                VStack(alignment: .leading, spacing: 14) {
                    if model.portChoices.count > 1 {
                        LabeledContent("Tiles") {
                            Picker("Tiles", selection: Binding(
                                get: { model.portsPerEdge }, set: { model.setPortsPerEdge($0) }
                            )) {
                                ForEach(model.portChoices, id: \.self) { Text("\($0) ports per edge").tag($0) }
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    Toggle("Make up tiles the library lacks", isOn: $model.allowsGeneratedTiles)

                    if model.allowsGeneratedTiles {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Spread").font(.subheadline)
                            Slider(value: $model.growth, in: 0...1) {
                                Text("Spread")
                            } minimumValueLabel: {
                                Image(systemName: "circle.dotted")
                            } maximumValueLabel: {
                                Image(systemName: "circle.hexagongrid.fill")
                            }
                        }
                    }
                }
                .padding(.top, 10)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("^[\(model.libraryTileCount) tile](inflect: true) in the \(model.portsPerEdge)-port library")
                if !model.maze.cells.isEmpty {
                    Text("\(model.maze.cells.count - model.generatedTileCount) from the library, \(model.generatedTileCount) made up")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    GeneratorView(model: GeneratorModel(library: SampleData.library()))
}
