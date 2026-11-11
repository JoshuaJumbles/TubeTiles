import SwiftUI
import TubeKit

/// Browses saved tiles, grouped into sets of interchangeable variants.
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

    @State private var chosenPortCount: Int?
    @State private var sort: Sort = .profile
    @State private var filter: Filter = .all
    @State private var selectedTile: Tile?

    private var portsPerEdge: Int? {
        let counts = library.portCounts
        if let chosenPortCount, counts.contains(chosenPortCount) { return chosenPortCount }
        // Start on the fullest library.
        return counts.max { library.library(portsPerEdge: $0).tiles.count < library.library(portsPerEdge: $1).tiles.count }
    }

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
        NavigationStack {
            Group {
                if let portsPerEdge {
                    content(for: library.library(portsPerEdge: portsPerEdge))
                } else {
                    ContentUnavailableView(
                        "No tiles yet",
                        systemImage: "hexagon",
                        description: Text("Tiles you save in the editor appear here.")
                    )
                }
            }
            .background(TilePalette.paper.ignoresSafeArea())
            // The paper backdrop is light in both appearances, so the screen
            // draws its own dark title instead of the system one, which
            // would turn white in dark mode.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
        .sheet(item: $selectedTile) { tile in
            TileDetailView(
                tile: tile,
                variantCount: library.library(portsPerEdge: tile.portsPerEdge)
                    .tilesByProfile[tile.edgeCode.canonical]?.count ?? 1,
                onOpen: { asCopy in
                    selectedTile = nil
                    onOpen(tile, asCopy)
                },
                onDelete: {
                    selectedTile = nil
                    try? library.delete(tile)
                }
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if library.portCounts.count > 1, let portsPerEdge {
                Picker("Ports per edge", selection: Binding(
                    get: { portsPerEdge },
                    set: { chosenPortCount = $0 }
                )) {
                    ForEach(library.portCounts, id: \.self) { count in
                        Text("\(count) ports").tag(count)
                    }
                }
                .pickerStyle(.menu)
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
                EdgeCoverageView(library: tiles)

                if groups.isEmpty {
                    Text("No tiles match this filter.")
                        .foregroundStyle(Color(white: 0.35))
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
            .padding(16)
        }
    }

    private func cell(_ tile: Tile) -> some View {
        Button { selectedTile = tile } label: {
            VStack(spacing: 4) {
                TileView(tile: tile)
                Text(tile.edgeCode.description)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color(white: 0.35))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .buttonStyle(.plain)
    }

    private func summary(for tiles: TileLibrary, shownGroups: Int) -> some View {
        let total = tiles.tilesByProfile.count
        return VStack(alignment: .leading, spacing: 2) {
            Text("Library")
                .font(.largeTitle.bold())
                .foregroundStyle(Color(white: 0.1))
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)
            Text("^[\(tiles.tiles.count) tile](inflect: true) in ^[\(total) profile](inflect: true)")
                .font(.headline)
                .foregroundStyle(Color(white: 0.15))
            Text("\(tiles.portsPerEdge) ports per edge" + (filter == .all ? "" : " · showing \(shownGroups)"))
                .font(.subheadline)
                .foregroundStyle(Color(white: 0.35))
        }
    }

    private func groupHeader(_ title: String, badge: String?) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(.subheadline, design: badge == nil ? .default : .monospaced).weight(.semibold))
                .foregroundStyle(Color(white: 0.15))
            if let badge {
                Text(badge)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                    .foregroundStyle(Color(red: 0.08, green: 0.30, blue: 0.55))
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
