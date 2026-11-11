import SwiftUI
import TubeKit

/// One saved tile, with what it is made of and what can be done with it.
struct TileDetailView: View {
    var tile: Tile
    /// How many tiles share this tile's profile, itself included.
    var variantCount: Int
    var onOpen: (_ asCopy: Bool) -> Void
    var onDelete: () -> Void

    @State private var isConfirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    private var pipeSummary: String {
        let names: [(PipeKind, String)] = [
            (.bezier, "curve"), (.corner, "corner"), (.roomSmall, "small room"),
            (.roomMedium, "medium room"), (.roomLarge, "large room"),
            (.endSmall, "small dead end"), (.endMedium, "medium dead end"), (.endLarge, "large dead end"),
        ]
        let parts = names.compactMap { kind, name -> String? in
            let count = tile.pipes.filter { $0.kind == kind }.count
            return count == 0 ? nil : "\(count) \(name)\(count == 1 ? "" : "s")"
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    TileView(tile: tile, outlineWidth: 2)
                        .frame(maxWidth: 360)
                        .padding(.horizontal, 24)

                    VStack(spacing: 0) {
                        row("Edge code", tile.edgeCode.description, monospaced: true)
                        Divider()
                        row("Profile", tile.edgeCode.canonical.description, monospaced: true)
                        Divider()
                        row("Variants", variantCount == 1 ? "Only tile with this profile" : "\(variantCount) tiles share this profile")
                        Divider()
                        row("Pipes", pipeSummary)
                    }
                    .background(RoundedRectangle(cornerRadius: 12).fill(.background))

                    VStack(spacing: 10) {
                        Button { onOpen(false) } label: {
                            Label("Edit", systemImage: "pencil").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button { onOpen(true) } label: {
                            Label("Duplicate as new variant", systemImage: "plus.square.on.square")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) { isConfirmingDelete = true } label: {
                            Label("Delete", systemImage: "trash").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        // Attached to the button so the prompt appears beside it.
                        .confirmationDialog("Delete this tile?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                            Button("Delete", role: .destructive, action: onDelete)
                        } message: {
                            Text("It will be removed from the library. This cannot be undone.")
                        }
                    }
                    .controlSize(.large)
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Tile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func row(_ title: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}
