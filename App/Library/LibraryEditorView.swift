import SwiftUI
import TubeKit

/// Creates a library, or edits one's name, note and rules.
struct LibraryEditorView: View {
    /// The library being edited, or nil to create one.
    var existing: TileLibrary?
    var onSave: (_ name: String, _ note: String, _ portsPerEdge: Int, _ allowedKinds: Set<PipeKind>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var note: String
    @State private var portsPerEdge: Int
    @State private var allowedKinds: Set<PipeKind>

    static let portRange = 2...8

    init(
        existing: TileLibrary?,
        suggestedName: String = "",
        suggestedPorts: Int = 6,
        onSave: @escaping (String, String, Int, Set<PipeKind>) -> Void
    ) {
        self.existing = existing
        self.onSave = onSave
        _name = State(initialValue: existing?.name ?? suggestedName)
        _note = State(initialValue: existing?.note ?? "")
        _portsPerEdge = State(initialValue: existing?.portsPerEdge ?? suggestedPorts)
        _allowedKinds = State(initialValue: existing?.allowedKinds ?? Set(PipeKind.allCases))
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
            }
            .navigationTitle(existing == nil ? "New library" : "Edit library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Create" : "Save") {
                        onSave(trimmedName, note.trimmingCharacters(in: .whitespacesAndNewlines), portsPerEdge, allowedKinds)
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty || !hasThroughKind)
                }
            }
        }
    }
}
