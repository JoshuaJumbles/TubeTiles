import SwiftUI
import TubeKit

/// The maze generator: the growing maze beside its controls on wide screens,
/// stacked on narrow ones.
struct GeneratorView: View {
    var model: GeneratorModel
    var archive: MazeArchive

    @State private var showsMazes = false
    @State private var showsPreview = false
    @State private var showsTools = false

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
                // Always two lines tall, so the maze does not shift under
                // the finger when the wording changes.
                Text(model.message ?? hint)
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
            }
            .padding(.top, 10)
            .padding(.horizontal, 56)

            MazeCanvas(model: model)
                .overlay(alignment: .bottomTrailing) {
                    toolButton.padding(10)
                }
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

    /// Shows the tool in use, and opens the choice of tools.
    private var toolButton: some View {
        Button { showsTools = true } label: {
            ToolBadge(title: model.tool.title, tint: model.tool.tint) {
                Image(systemName: model.tool.symbol)
                    .font(.title2)
                    .foregroundStyle(model.tool.tint)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tool: \(model.tool.title)")
        .popover(isPresented: $showsTools) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(72), spacing: 8), count: 3), spacing: 8) {
                ForEach(GeneratorModel.Tool.allCases, id: \.self) { tool in
                    ToolCell(title: tool.title, isSelected: model.tool == tool) {
                        model.tool = tool
                        showsTools = false
                    } icon: {
                        Image(systemName: tool.symbol)
                            .font(.title3)
                            .foregroundStyle(tool.tint)
                    }
                }
            }
            .padding(14)
            .presentationCompactAdaptation(.popover)
        }
    }

    private var hint: String {
        switch model.tool {
        case .place:
            if model.maze.cells.isEmpty { return "Mazes grow from the middle and seal at the outline." }
            if !model.openCells.isEmpty { return "Dashed cells still need a tile. Tap one to fill it." }
            return "Tap a tile to swap it, or an empty cell to add one."
        case .delete:
            return "Tap a tile to remove it."
        case .endpoint:
            return "Tap a cell for a goal, or just outside the outline for an entrance or exit."
        case .lock:
            return "Each colour is one path. Tap one to lock it out of merging, or to release it."
        case .design:
            return "Tap a cell to draw a tile for it in the editor."
        }
    }
}

extension GeneratorModel.Tool {
    var title: String {
        switch self {
        case .place: "Place"
        case .delete: "Delete"
        case .endpoint: "Endpoint"
        case .lock: "Lock loop"
        case .design: "Design"
        }
    }

    var symbol: String {
        switch self {
        case .place: "hexagon"
        case .delete: "trash"
        case .endpoint: "scope"
        case .lock: "lock"
        case .design: "pencil.and.outline"
        }
    }

    var tint: Color {
        self == .delete ? TilePalette.negative : .accentColor
    }
}

/// Controls for the generator: growing, symmetry and size. Hand edits are
/// made with the tool chosen on the canvas.
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

                Button(role: .destructive) { model.clear() } label: {
                    Label("Clear", systemImage: "xmark.square")
                }
                .buttonStyle(.bordered)
                .labelStyle(.titleOnly)
                .disabled(model.maze.cells.isEmpty)
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
                    LabeledContent("Library") {
                        Picker("Library", selection: Binding(
                            get: { model.currentLibrary.id }, set: { model.chooseLibrary($0) }
                        )) {
                            ForEach(model.libraries) { library in
                                Text("\(library.name) · \(library.portsPerEdge) ports").tag(library.id)
                            }
                        }
                        .pickerStyle(.menu)
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
                        Text("Or place each end yourself with the Endpoint tool.")
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
                        Text("A goal ends a path in a room. The Endpoint tool makes any cell one.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.bordered)

                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Make up tiles the library lacks", isOn: $model.allowsGeneratedTiles)
                        if model.allowsGeneratedTiles, let library = model.activeLibrary {
                            if library.allowedKinds.count < PipeKind.allCases.count {
                                Text("Made-up tiles use only this library's kinds: "
                                    + PipeKind.allCases.filter(library.allowedKinds.contains).map(\.shortTitle).joined(separator: ", ") + ".")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            if !library.deadPorts.isEmpty {
                                Text("They also keep off the ports this library has switched off.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

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
                if model.activeLibrary != nil {
                    Text("^[\(model.libraryTileCount) tile](inflect: true) in \u{201C}\(model.currentLibrary.name)\u{201D}")
                } else {
                    Text("\u{201C}\(model.currentLibrary.name)\u{201D} has \(model.currentLibrary.portsPerEdge) ports per edge and this maze has \(model.portsPerEdge), so its tiles are not used here.")
                }
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
