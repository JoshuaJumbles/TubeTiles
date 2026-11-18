import SwiftUI
import TubeKit

extension TileLibrary {
    /// What the library holds, in a line: "Hexagons · 6 ports · 38 tiles".
    var summary: String {
        let kind = shape.pluralTitle
        let count = tiles.count == 1 ? "1 tile" : "\(tiles.count) tiles"
        return "\(kind) · \(portsPerEdge) ports · \(count)"
    }
}

/// A row that names the library in use and opens the list of libraries to
/// pick another. The editor and the generator both choose a library this way.
struct LibraryChoice: View {
    var libraries: [TileLibrary]
    var selectedID: UUID
    var onChoose: (UUID) -> Void

    @State private var isChoosing = false

    var body: some View {
        let current = libraries.first { $0.id == selectedID }
        LabeledContent("Library") {
            Button { isChoosing = true } label: {
                HStack(spacing: 6) {
                    Text(current.map { "\($0.name) · \($0.portsPerEdge) ports" } ?? "Choose")
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .imageScale(.small)
                }
            }
            .accessibilityLabel("Library")
            .accessibilityValue(current?.name ?? "")
            .accessibilityHint("Shows every library")
        }
        .sheet(isPresented: $isChoosing) {
            LibraryPicker(libraries: libraries, selectedID: selectedID, onChoose: onChoose)
        }
    }
}

/// Every library, with a few of its tiles and what it holds, to pick one
/// from.
struct LibraryPicker: View {
    var libraries: [TileLibrary]
    var selectedID: UUID
    var onChoose: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(libraries) { library in
                        Button {
                            if library.id != selectedID { onChoose(library.id) }
                            dismiss()
                        } label: {
                            LibraryRow(library: library, isSelected: library.id == selectedID)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(library.id == selectedID ? .isSelected : [])
                    }
                }
                .padding(16)
            }
            .background(TilePalette.paper.ignoresSafeArea())
            .navigationTitle("Libraries")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// One library in the list: a few of its tiles, its name, and what it holds.
private struct LibraryRow: View {
    var library: TileLibrary
    var isSelected: Bool

    /// The tiles shown as a taste of the library: the first few, or a blank
    /// one of the right shape when it has none.
    private var samples: [Tile] {
        library.tiles.isEmpty
            ? [Tile(portsPerEdge: library.portsPerEdge, gauge: library.gauge, shape: library.shape)]
            : Array(library.tiles.prefix(3))
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(samples) { tile in
                    TileView(tile: tile)
                        .frame(width: 34, height: 34)
                }
            }
            .frame(width: 110, alignment: .leading)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(library.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(library.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if !library.note.isEmpty {
                    Text(library.note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(TilePalette.face)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
