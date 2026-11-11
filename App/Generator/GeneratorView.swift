import SwiftUI
import TubeKit

/// The maze generator: the growing maze beside its controls on wide screens,
/// stacked on narrow ones.
struct GeneratorView: View {
    var model: GeneratorModel
    var archive: MazeArchive

    @State private var showsMazes = false
    @State private var showsPreview = false

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
                    .foregroundStyle(Color.primary)
                Text(model.message ?? hint)
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 10)
            .padding(.horizontal, 56)

            MazeCanvas(model: model)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            Button { showsMazes = true } label: {
                Image(systemName: "folder")
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(TilePalette.face))
                    .foregroundStyle(Color.primary)
            }
            .accessibilityLabel("Saved mazes")
            .padding(.top, 6)
            .padding(.leading, 10)
        }
        .sheet(isPresented: $showsMazes) {
            MazesView(model: model, archive: archive)
        }
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 8) {
                ShareLink(item: model.drawing, preview: SharePreview("TubeTiles maze.svg")) {
                    cornerButton("square.and.arrow.up")
                }
                .accessibilityLabel("Export SVG")

                Button { showsPreview = true } label: {
                    cornerButton("eye")
                }
                .accessibilityLabel("Preview")
            }
            .disabled(model.maze.cells.isEmpty)
            .opacity(model.maze.cells.isEmpty ? 0.4 : 1)
            .padding(.top, 6)
            .padding(.trailing, 10)
        }
        .fullScreenCover(isPresented: $showsPreview) {
            MazePreview(maze: model.maze)
        }
    }

    private func cornerButton(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .frame(width: 40, height: 40)
            .background(Circle().fill(TilePalette.face))
            .foregroundStyle(Color.primary)
    }

    private var hint: String {
        if model.selected != nil { return "Tile selected. Swap or delete it, or tap elsewhere." }
        if model.maze.cells.isEmpty { return "Mazes grow from the middle and seal at the outline." }
        if !model.openCells.isEmpty { return "Dashed cells still need a tile." }
        if model.showsPaths { return "Each colour is one path. Tap one to keep it out of merging." }
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

                    VStack(alignment: .leading, spacing: 6) {
                        if model.maze.openings.isEmpty {
                            Button { model.addOpposedOpenings() } label: {
                                Label("Add entrance and exit", systemImage: "arrow.left.and.right")
                                    .frame(maxWidth: .infinity)
                            }
                        } else {
                            Button(role: .destructive) { model.removeOpenings() } label: {
                                Label("Remove entrance and exit", systemImage: "xmark")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        Text("Or tap just outside the outline to place each end yourself.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.bordered)

                    VStack(alignment: .leading, spacing: 6) {
                        if model.maze.goals.isEmpty {
                            Button { model.addCentreGoal() } label: {
                                Label("Add a goal in the middle", systemImage: "scope")
                                    .frame(maxWidth: .infinity)
                            }
                        } else {
                            Button(role: .destructive) { model.removeGoals() } label: {
                                Label(model.maze.goals.count == 1 ? "Remove the goal" : "Remove goals", systemImage: "xmark")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        Text("A goal ends a path in a room. Touch and hold any cell to make it one.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.bordered)

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
    let archive = MazeArchive(persists: false)
    GeneratorView(model: GeneratorModel(library: SampleData.library(), archive: archive), archive: archive)
}
