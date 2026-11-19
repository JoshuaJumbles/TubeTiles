import SwiftUI
import TubeKit

/// Creates a library, or edits one's name, note and rules.
struct LibraryEditorView: View {
    /// The library being edited, or nil to create one.
    var existing: TileLibrary?
    var onSave: (
        _ name: String, _ note: String, _ portsPerEdge: Int, _ allowedKinds: Set<PipeKind>, _ deadSlots: Set<Int>,
        _ gauge: PipeGauge, _ shapes: [TileShape]
    ) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var note: String
    @State private var portsPerEdge: Int
    /// The tiling a new library is made for, which decides its shapes.
    @State private var tiling: Tiling
    private var shapes: [TileShape] { existing?.shapes ?? tiling.shapes }
    /// The shape the sample is drawn on.
    private var shape: TileShape { shapes[0] }
    @State private var allowedKinds: Set<PipeKind>
    /// Slots switched off on every edge.
    @State private var deadSlots: Set<Int>
    /// Pipe width, as a share of the space between ports.
    @State private var pipeWidth: Double
    /// Each wall, as a share of the pipe's width.
    @State private var wall: Double
    /// Tiles already in the library whose pipes would be too close at the
    /// chosen thickness. Counted when a slider is let go, not as it moves.
    @State private var crowdedTiles = 0

    static let portRange = 2...8

    init(
        existing: TileLibrary?,
        suggestedName: String = "",
        suggestedPorts: Int = 6,
        onSave: @escaping (String, String, Int, Set<PipeKind>, Set<Int>, PipeGauge, [TileShape]) -> Void
    ) {
        self.existing = existing
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? suggestedName)
        _note = State(initialValue: existing?.note ?? "")
        _portsPerEdge = State(initialValue: existing?.portsPerEdge ?? suggestedPorts)
        _tiling = State(initialValue: .hexagonal)
        _allowedKinds = State(initialValue: existing?.allowedKinds ?? Set(PipeKind.allCases))
        _deadSlots = State(initialValue: existing?.deadSlots ?? [])
        let gauge = existing?.gauge ?? .standard
        _pipeWidth = State(initialValue: gauge.width)
        _wall = State(initialValue: gauge.wall)
    }

    private var gauge: PipeGauge { PipeGauge(width: pipeWidth, wall: wall) }

    /// A few pipes at the chosen thickness, to judge the look by.
    private var sampleTile: Tile {
        let last = portsPerEdge - 1
        var tile = Tile(portsPerEdge: portsPerEdge, gauge: gauge, shape: shape)
        let middle = last / 2
        // One straight down with a curve crossing it, so both the look and
        // the crossings can be judged. A hexagon has room for two.
        let pipes: [Pipe]
        switch shape {
        case .hexagon:
            pipes = [
                Pipe(.bezier, a: Port(edge: 0, slot: middle), b: Port(edge: 3, slot: last - middle)),
                Pipe(.bezier, a: Port(edge: 5, slot: middle), b: Port(edge: 1, slot: last - middle)),
                Pipe(.bezier, a: Port(edge: 4, slot: middle), b: Port(edge: 2, slot: last - middle)),
            ]
        case .square:
            pipes = [
                Pipe(.bezier, a: Port(edge: 0, slot: middle), b: Port(edge: 2, slot: last - middle)),
                Pipe(.bezier, a: Port(edge: 3, slot: 0), b: Port(edge: 1, slot: 0)),
            ]
        case .cairo:
            pipes = [
                Pipe(.bezier, a: Port(edge: 0, slot: middle), b: Port(edge: 2, slot: last - middle)),
                Pipe(.bezier, a: Port(edge: 4, slot: middle), b: Port(edge: 1, slot: last - middle)),
            ]
        case .triangle:
            pipes = [
                Pipe(.bezier, a: Port(edge: 0, slot: middle), b: Port(edge: 1, slot: last - middle)),
                Pipe(.bezier, a: Port(edge: 2, slot: 0), b: Port(edge: 1, slot: 0)),
            ]
        case .octagon:
            pipes = [
                Pipe(.bezier, a: Port(edge: 0, slot: middle), b: Port(edge: 4, slot: last - middle)),
                Pipe(.bezier, a: Port(edge: 7, slot: middle), b: Port(edge: 2, slot: last - middle)),
                Pipe(.bezier, a: Port(edge: 5, slot: middle), b: Port(edge: 3, slot: last - middle)),
            ]
        }
        for pipe in pipes { try? tile.add(pipe) }
        return tile
    }

    private func countCrowdedTiles() {
        crowdedTiles = existing?.crowdedTileCount(at: gauge) ?? 0
    }

    /// Dead slots that still exist at the current port count.
    private var validDeadSlots: Set<Int> {
        deadSlots.filter { $0 < portsPerEdge }
    }

    /// At least one port per edge has to stay in use.
    private var hasLivePort: Bool {
        validDeadSlots.count < portsPerEdge
    }

    /// Switches a slot, and its mirror image, on or off.
    private func toggle(slot: Int) {
        let pair: Set<Int> = [slot, portsPerEdge - 1 - slot]
        if deadSlots.contains(slot) {
            deadSlots.subtract(pair)
        } else {
            deadSlots.formUnion(pair)
        }
    }

    /// Tiles already in the library with a pipe on a port now switched off.
    private var deadPortTiles: Int {
        let dead = validDeadSlots
        return existing?.tiles.filter { tile in
            tile.occupiedPorts.contains { dead.contains($0.slot) }
        }.count ?? 0
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A library needs at least one kind that joins two ports, or no tile
    /// could ever connect to its neighbours.
    private var hasThroughKind: Bool {
        allowedKinds.contains { !$0.isDeadEnd }
    }

    /// Tiles already in the library that use a kind now switched off.
    private var strandedTiles: Int {
        existing?.tiles.filter { tile in
            tile.pipes.contains { !allowedKinds.contains($0.kind) }
        }.count ?? 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("What is it for? (optional)", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    if existing == nil {
                        Picker("Tiles", selection: $tiling) {
                            ForEach(Tiling.librarySets, id: \.self) { Text($0.shapesTitle).tag($0) }
                        }
                        Stepper("\(portsPerEdge) ports per edge", value: $portsPerEdge, in: Self.portRange)
                    } else {
                        LabeledContent("Tiles", value: ListFormatter.localizedString(byJoining: shapes.map(\.pluralTitle)))
                        LabeledContent("Ports per edge", value: "\(portsPerEdge)")
                    }
                } footer: {
                    Text(existing == nil
                        ? "Every tile in a library has the same number of ports, and the library holds one shape or a set that fit together. Neither can be changed later. A library of two shapes can be laid every way those shapes fit together, and as a plain grid of one of them where that shape tiles alone. The generator offers the choice under Options. A Cairo tile is a pentagon with five equal edges; it can be flipped but not turned, so a library of them needs more tiles."
                        : "The shapes and port count are fixed once a library exists.")
                }

                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(PipeKind.allCases, id: \.self) { kind in
                            KindButton(kind: kind, isSelected: allowedKinds.contains(kind)) {
                                if allowedKinds.contains(kind) {
                                    allowedKinds.remove(kind)
                                } else {
                                    allowedKinds.insert(kind)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Pipe kinds")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("The editor offers only these kinds, and tiles the generator makes up use only these, so mazes grown from this library keep its look.")
                        if !hasThroughKind {
                            Text("Choose at least one kind that joins two ports.")
                                .foregroundStyle(TilePalette.negative)
                        }
                        if strandedTiles > 0 {
                            Text("^[\(strandedTiles) tile](inflect: true) already here use a kind you have switched off. They stay in the library and are still used.")
                        }
                    }
                }

                Section {
                    HStack(alignment: .center, spacing: 16) {
                        TileView(tile: sampleTile)
                            .frame(width: 104)
                            // Redrawn for every change of thickness or ports.
                            .id("\(shape)-\(portsPerEdge)-\(pipeWidth)-\(wall)")
                        VStack(alignment: .leading, spacing: 10) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Width").font(.subheadline)
                                Slider(value: $pipeWidth, in: PipeGauge.widthRange) { editing in
                                    if !editing { countCrowdedTiles() }
                                }
                                .accessibilityLabel("Pipe width")
                            }
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Walls").font(.subheadline)
                                Slider(value: $wall, in: PipeGauge.wallRange)
                                    .accessibilityLabel("Wall thickness")
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    if gauge != .standard {
                        Button("Back to the usual thickness") {
                            pipeWidth = PipeGauge.standard.width
                            wall = PipeGauge.standard.wall
                            countCrowdedTiles()
                        }
                    }
                } header: {
                    Text("Pipe thickness")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Every tile in the library is drawn at this thickness, and so are mazes grown from it. Wider pipes leave less room: fewer fit side by side, and some turns that clear each other when thin no longer do.")
                        if crowdedTiles > 0 {
                            Text("^[\(crowdedTiles) tile](inflect: true) already here have pipes too close together at this width. They stay in the library and are still used.")
                        }
                    }
                }

                Section {
                    // One edge, standing for all six.
                    HStack(spacing: 0) {
                        ForEach(0..<portsPerEdge, id: \.self) { slot in
                            let isDead = validDeadSlots.contains(slot)
                            Button { toggle(slot: slot) } label: {
                                ZStack {
                                    Circle()
                                        .fill(isDead ? Color.clear : Color.accentColor)
                                    Circle()
                                        .stroke(isDead ? Color.secondary.opacity(0.5) : Color.accentColor, lineWidth: 2)
                                }
                                .frame(width: 22, height: 22)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Port \(slot + 1)")
                            .accessibilityValue(isDead ? "Off" : "On")
                        }
                    }
                    .background(alignment: .center) {
                        Rectangle().fill(Color.secondary.opacity(0.35)).frame(height: 2)
                    }
                } header: {
                    Text("Ports in use")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tap a port to switch it off on every edge. Its mirror image goes with it, so tiles can still be turned and flipped. The editor ignores ports that are off, and tiles the generator makes up never use them.")
                        if !hasLivePort {
                            Text("Leave at least one port in use.")
                                .foregroundStyle(TilePalette.negative)
                        }
                        if deadPortTiles > 0 {
                            Text("^[\(deadPortTiles) tile](inflect: true) already here use a port you have switched off. They stay in the library and are still used.")
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "New library" : "Edit library")
            .onChange(of: portsPerEdge) { _, _ in deadSlots = validDeadSlots }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Create" : "Save") {
                        onSave(
                            trimmedName, note.trimmingCharacters(in: .whitespacesAndNewlines),
                            portsPerEdge, allowedKinds, validDeadSlots, gauge, shapes
                        )
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty || !hasThroughKind || !hasLivePort)
                }
            }
        }
    }
}
