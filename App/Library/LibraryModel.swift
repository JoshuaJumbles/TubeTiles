import Observation
import TubeKit

/// The saved tiles, shared by every screen. One library per port count.
@MainActor
@Observable
final class LibraryModel {
    private(set) var libraries: [Int: TileLibrary] = [:]
    /// Nil keeps everything in memory, for previews and sample data.
    private let store: LibraryStore?

    init(store: LibraryStore? = LibraryStore()) {
        self.store = store
        for library in store?.allLibraries() ?? [] {
            libraries[library.portsPerEdge] = library
        }
    }

    /// Port counts that have at least one saved tile, smallest first.
    var portCounts: [Int] {
        libraries.values.filter { !$0.tiles.isEmpty }.map(\.portsPerEdge).sorted()
    }

    func library(portsPerEdge: Int) -> TileLibrary {
        libraries[portsPerEdge] ?? TileLibrary(name: "\(portsPerEdge) ports", portsPerEdge: portsPerEdge)
    }

    func contains(_ tile: Tile) -> Bool {
        libraries[tile.portsPerEdge]?.contains(id: tile.id) ?? false
    }

    /// Adds the tile, or replaces the saved tile with the same identity.
    func save(_ tile: Tile) throws {
        var library = library(portsPerEdge: tile.portsPerEdge)
        library.save(tile)
        try commit(library)
    }

    func delete(_ tile: Tile) throws {
        var library = library(portsPerEdge: tile.portsPerEdge)
        library.remove(id: tile.id)
        try commit(library)
    }

    private func commit(_ library: TileLibrary) throws {
        try store?.write(library)
        libraries[library.portsPerEdge] = library
    }
}
