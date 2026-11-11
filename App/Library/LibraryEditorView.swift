import SwiftUI
import TubeKit

/// Creates a library, or edits one's name, note and rules.
struct LibraryEditorView: View {
    /// The library being edited, or nil to create one.
    var existing: TileLibrary?
    var onSave: (
        _ name: String, _ note: String, _ portsPerEdge: Int, _ allowedKinds: Set<PipeKind>, _ deadSlots: Set<Int>
    ) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var note: String
    @State private var portsPerEdge: Int
    @State private var allowedKinds: Set<PipeKind>
    /// Slots switched off on every edge.
    @State private var deadSlots: Set<Int>

    static let portRange = 2...8

    init(
        existing: TileLibrary?,
        suggestedName: String = "",
        suggestedPorts: Int = 6,
        onSave: @escaping (String, String, Int, Set<PipeKind>, Set<Int>) -> Void
    ) {
        self.existing = existing
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? suggestedName)
        _note = State(initialValue: existing?.note ?? "")
        _portsPerEdge = State(initialValue: existing?.portsPerEdge ?? suggestedPorts)
        _allowedKinds = State(initialValue: existing?.allowedKinds ?? Set(PipeKind.allCases))
        _deadSlots = State(initialValue: existing?.deadSlots ?? [])
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
                        Stepper("\(portsPerEdge) ports per edge", value: $portsPerEdge, in: Self.portRange)
                    } else {
                        LabeledContent("Ports per edge", value: "\(portsPerEdge)")
                    }
                } footer: {
                    Text(existing == nil
                        ? "Every tile in a library has the same number of ports. This cannot be changed later."
                        : "The port count is fixed once a library exists.")
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
                            portsPerEdge, allowedKinds, validDeadSlots
                        )
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty || !hasThroughKind || !hasLivePort)
                }
            }
        }
    }
}
