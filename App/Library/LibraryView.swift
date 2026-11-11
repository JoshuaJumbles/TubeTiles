import SwiftUI
import TubeKit

/// Browses the current library's tiles, grouped into sets of interchangeable
/// variants, and manages the libraries themselves.
struct LibraryView: View {
    var library: LibraryModel
    /// Sends a tile to the editor; `asCopy` asks for a fresh duplicate.
    var onOpen: (_ tile: Tile, _ asCopy: Bool) -> Void

    enum Sort: String, CaseIterable, Identifiable {
        case profile = "Edge code"
        case mostVariants = "Most variants"
        case fewestPipes = "Fewest pipes"
        var id: Self { self }
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case withVariants = "With variants"
        case singles = "Singles"
        var id: Self { self }
    }

    struct ProfileGroup: Identifiable {
        var profile: EdgeCode
        var tiles: [Tile]
        var id: EdgeCode { profile }
        var pipeCount: Int { tiles.first?.pipes.count ?? 0 }
    }

    private enum Editing: Identifiable {
        case new
        case existing(TileLibrary)
        var id: String {
            switch self {
            case .new: "new"
            case let .existing(library): library.id.uuidString
            }
        }
    }

    @State private var sort: Sort = .profile
    @State private var filter: Filter = .all
    @State private var selectedTile: Tile?
    @State private var editing: Editing?
    @State private var isConfirmingDelete = false

    private func groups(in tiles: TileLibrary) -> [ProfileGroup] {
        var groups = tiles.tilesByProfile.map { ProfileGroup(profile: $0.key, tiles: $0.value) }
        switch filter {
        case .all: break
        case .withVariants: groups.removeAll { $0.tiles.count < 2 }
        case .singles: groups.removeAll { $0.tiles.count != 1 }
        }
        func byCode(_ a: ProfileGroup, _ b: ProfileGroup) -> Bool {
            a.profile.values.lexicographicallyPrecedes(b.profile.values)
        }
        switch sort {
        case .profile:
            groups.sort(by: byCode)
        case .mostVariants:
            groups.sort { $0.tiles.count != $1.tiles.count ? $0.tiles.count > $1.tiles.count : byCode($0, $1) }
        case .fewestPipes:
            groups.sort { $0.pipeCount != $1.pipeCount ? $0.pipeCount < $1.pipeCount : byCode($0, $1) }
        }
        return groups
    }

    var body: some View {
        let current = library.current
        NavigationStack {
            content(for: current)
                .background(TilePalette.paper.ignoresSafeArea())
                // The title is drawn in the page so it scrolls with the tiles.
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar(for: current) }
                .confirmationDialog(
                    "Delete \u{201C}\(current.name)\u{201D}?",
                    isPresented: $isConfirmingDelete,
                    titleVisibility: .visible
                ) {
                    Button("Delete library", role: .destructive) {
                        try? library.deleteLibrary(id: current.id)
                    }
                } message: {
                    Text(current.tiles.isEmpty
                        ? "The library will be removed."
                        : "The library and its ^[\(current.tiles.count) tile](inflect: true) will be removed. This cannot be undone. Saved mazes keep their own copies.")
                }
        }
        .sheet(item: $selectedTile) { tile in
            TileDetailView(
                tile: tile,
                variantCount: current.tilesByProfile[tile.edgeCode.canonical]?.count ?? 1,
                destinations: library.destinations(from: current),
                onOpen: { asCopy in
                    selectedTile = nil
                    onOpen(tile, asCopy)
                },
                onCopy: { destination in
                    selectedTile = nil
                    try? library.copy(tile, to: destination)
                },
                onMove: { destination in
                    selectedTile = nil
                    try? library.move(tile, from: current.id, to: destination)
                },
                onDelete: {
                    selectedTile = nil
                    try? library.delete(tile, from: current.id)
                }
            )
        }
        .sheet(item: $editing) { editing in
            switch editing {
            case .new:
                LibraryEditorView(
                    existing: nil,
                    suggestedName: library.unusedName("New library"),
                    suggestedPorts: current.portsPerEdge
                ) { name, note, ports, kinds, dead in
                    _ = try? library.create(
                        name: name, note: note, portsPerEdge: ports, allowedKinds: kinds, deadSlots: dead
                    )
                }
            case let .existing(target):
                LibraryEditorView(existing: target) { name, note, _, kinds, dead in
                    try? library.update(id: target.id, name: name, note: note, allowedKinds: kinds, deadSlots: dead)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private func toolbar(for current: TileLibrary) -> some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                Picker("Library", selection: Binding(
                    get: { library.currentID }, set: { library.select($0) }
                )) {
                    ForEach(library.libraries) { item in
                        Text("\(item.name) · \(item.portsPerEdge) ports").tag(item.id)
                    }
                }
                Divider()
                Button { editing = .new } label: {
                    Label("New library", systemImage: "plus")
                }
                Button { editing = .existing(current) } label: {
                    Label("Edit this library", systemImage: "slider.horizontal.3")
                }
                Button { _ = try? library.duplicate(id: current.id) } label: {
                    Label("Duplicate this library", systemImage: "plus.square.on.square")
                }
                Button(role: .destructive) { isConfirmingDelete = true } label: {
                    Label("Delete this library", systemImage: "trash")
                }
            } label: {
                Label("Libraries", systemImage: "books.vertical")
            }

            Menu {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Sort by", selection: $sort) {
                    ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                Label("Filter and sort", systemImage: "line.3.horizontal.decrease.circle")
            }
        }
    }

    private func content(for tiles: TileLibrary) -> some View {
        let groups = groups(in: tiles)
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summary(for: tiles, shownGroups: groups.count)

                if tiles.tiles.isEmpty {
                    ContentUnavailableView(
                        "No tiles yet",
                        systemImage: "hexagon",
                        description: Text("Tiles you save in the editor go into this library.")
                    )
                    .padding(.top, 24)
                } else {
                    EdgeCoverageView(library: tiles)

                    if groups.isEmpty {
                        Text("No tiles match this filter.")
                            .foregroundStyle(Color.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                    // Profiles with several tiles each get their own headed
                    // section; profiles with one tile share a section, so a
                    // library of one-offs stays a compact grid.
                    let variantGroups = groups.filter { $0.tiles.count > 1 }
                    let singles = groups.filter { $0.tiles.count == 1 }.flatMap(\.tiles)
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 12)],
                        alignment: .leading, spacing: 14
                    ) {
                        ForEach(variantGroups) { group in
                            Section {
                                ForEach(group.tiles) { tile in cell(tile) }
                            } header: {
                                groupHeader(group.profile.description, badge: "\(group.tiles.count) variants")
                            }
                        }
                        if !singles.isEmpty {
                            Section {
                                ForEach(singles) { tile in cell(tile) }
                            } header: {
                                groupHeader(variantGroups.isEmpty ? "Tiles" : "One of a kind", badge: nil)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func cell(_ tile: Tile) -> some View {
        Button { selectedTile = tile } label: {
            VStack(spacing: 4) {
                TileView(tile: tile)
                Text(tile.edgeCode.description)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .buttonStyle(.plain)
    }

    /// The library's name, note, size and rules.
    private func summary(for tiles: TileLibrary, shownGroups: Int) -> some View {
        let total = tiles.tilesByProfile.count
        let off = tiles.offPaletteTiles.count
        let onDeadPorts = tiles.deadPortTiles.count
        let kinds = PipeKind.allCases.filter(tiles.allowedKinds.contains)
        return VStack(alignment: .leading, spacing: 4) {
            Text(tiles.name)
                .font(.largeTitle.bold())
                .foregroundStyle(Color.primary)
                .accessibilityAddTraits(.isHeader)
            if !tiles.note.isEmpty {
                Text(tiles.note)
                    .font(.body)
                    .foregroundStyle(Color.secondary)
                    .padding(.bottom, 4)
            }
            Text("^[\(tiles.tiles.count) tile](inflect: true) in ^[\(total) profile](inflect: true)")
                .font(.headline)
                .foregroundStyle(Color.primary)
            Text(portSummary(for: tiles) + (filter == .all ? "" : " · showing \(shownGroups)"))
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
            Text(kinds.count == PipeKind.allCases.count
                ? "All pipe kinds"
                : "Kinds: " + kinds.map(\.shortTitle).joined(separator: ", "))
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
            if off > 0 {
                Text("^[\(off) tile](inflect: true) use kinds outside this list.")
                    .font(.subheadline)
                    .foregroundStyle(TilePalette.negative)
            }
            if onDeadPorts > 0 {
                Text("^[\(onDeadPorts) tile](inflect: true) use ports that are switched off.")
                    .font(.subheadline)
                    .foregroundStyle(TilePalette.negative)
            }
        }
    }

    private func portSummary(for tiles: TileLibrary) -> String {
        guard !tiles.deadPorts.isEmpty else { return "\(tiles.portsPerEdge) ports per edge" }
        guard let live = tiles.liveSlotCount else { return "\(tiles.portsPerEdge) ports per edge, some switched off" }
        return "\(live) of \(tiles.portsPerEdge) ports per edge in use"
    }

    private func groupHeader(_ title: String, badge: String?) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(.subheadline, design: badge == nil ? .default : .monospaced).weight(.semibold))
                .foregroundStyle(Color.primary)
            if let badge {
                Text(badge)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                    .foregroundStyle(Color(light: Color(red: 0.08, green: 0.30, blue: 0.55), dark: Color(red: 0.62, green: 0.80, blue: 1.0)))
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    LibraryView(library: SampleData.library(), onOpen: { _, _ in })
}
