import Foundation
import Observation
import TubeKit

/// The tile libraries, shared by every screen, and which one is current.
///
/// The current library is the one the editor saves into and the generator
/// draws from. There is always at least one library.
@MainActor
@Observable
final class LibraryModel {
    /// Sorted by name.
    private(set) var libraries: [TileLibrary] = []
    private(set) var currentID: UUID
    /// Nil keeps everything in memory, for previews and sample data.
    private let store: LibraryStore?

    private static let currentKey = "currentLibraryID"

    init(store: LibraryStore? = LibraryStore()) {
        self.store = store
        var loaded = store?.allLibraries() ?? []
        if loaded.isEmpty {
            let first = TileLibrary(name: "My tiles", portsPerEdge: 6)
            try? store?.write(first)
            loaded = [first]
        }
        let remembered = store == nil ? nil : UserDefaults.standard.string(forKey: Self.currentKey).flatMap(UUID.init)
        // Otherwise start on the fullest library.
        let fullest = loaded.max { $0.tiles.count < $1.tiles.count }
        currentID = loaded.first { $0.id == remembered }?.id ?? fullest?.id ?? loaded[0].id
        libraries = Self.sorted(loaded)
    }

    private static func sorted(_ libraries: [TileLibrary]) -> [TileLibrary] {
        libraries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: Looking things up

    var current: TileLibrary {
        libraries.first { $0.id == currentID } ?? libraries[0]
    }

    func library(id: UUID?) -> TileLibrary? {
        libraries.first { $0.id == id }
    }

    /// The library a tile is saved in, if any.
    func home(of tile: Tile) -> TileLibrary? {
        libraries.first { $0.contains(id: tile.id) }
    }

    /// Whether the tile is saved in the current library.
    func contains(_ tile: Tile) -> Bool {
        current.contains(id: tile.id)
    }

    /// Other libraries a tile from `library` could go into: those with the
    /// same port count.
    func destinations(from library: TileLibrary) -> [TileLibrary] {
        libraries.filter { $0.id != library.id && $0.portsPerEdge == library.portsPerEdge }
    }

    /// A name not yet in use, starting from `base`.
    func unusedName(_ base: String) -> String {
        let taken = Set(libraries.map(\.name))
        guard taken.contains(base) else { return base }
        var number = 2
        while taken.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }

    // MARK: Libraries

    func select(_ id: UUID) {
        guard library(id: id) != nil, id != currentID else { return }
        currentID = id
        if store != nil {
            UserDefaults.standard.set(id.uuidString, forKey: Self.currentKey)
        }
    }

    /// Creates a library and makes it current.
    @discardableResult
    func create(
        name: String, note: String, portsPerEdge: Int, allowedKinds: Set<PipeKind>, deadSlots: Set<Int> = []
    ) throws -> TileLibrary {
        let library = TileLibrary(
            name: name, note: note, portsPerEdge: portsPerEdge, allowedKinds: allowedKinds, deadSlots: deadSlots
        )
        try commit(library)
        select(library.id)
        return library
    }

    func update(id: UUID, name: String, note: String, allowedKinds: Set<PipeKind>, deadSlots: Set<Int>) throws {
        guard var library = library(id: id) else { return }
        library.name = name
        library.note = note
        library.allowedKinds = allowedKinds
        library.setDeadSlots(deadSlots)
        try commit(library)
    }

    /// Makes a separate copy of a library, with its own tiles, and makes the
    /// copy current.
    @discardableResult
    func duplicate(id: UUID) throws -> TileLibrary? {
        guard let original = library(id: id) else { return nil }
        let copy = original.duplicated(named: unusedName("\(original.name) copy"))
        try commit(copy)
        select(copy.id)
        return copy
    }

    /// Deletes a library and all its tiles. If it was the last one, an empty
    /// library takes its place.
    func deleteLibrary(id: UUID) throws {
        guard let doomed = library(id: id) else { return }
        try store?.delete(id: id)
        libraries.removeAll { $0.id == id }
        if libraries.isEmpty {
            try commit(TileLibrary(name: "My tiles", portsPerEdge: doomed.portsPerEdge))
        }
        if currentID == id {
            let next = libraries.first { $0.portsPerEdge == doomed.portsPerEdge } ?? libraries[0]
            currentID = next.id
            if store != nil {
                UserDefaults.standard.set(next.id.uuidString, forKey: Self.currentKey)
            }
        }
    }

    // MARK: Tiles

    /// Adds the tile to a library (the current one unless told otherwise),
    /// or replaces the saved tile with the same identity.
    func save(_ tile: Tile, to id: UUID? = nil) throws {
        guard var library = library(id: id ?? currentID), library.portsPerEdge == tile.portsPerEdge else { return }
        library.save(tile)
        try commit(library)
    }

    func delete(_ tile: Tile, from id: UUID? = nil) throws {
        guard var library = library(id: id ?? currentID) else { return }
        library.remove(id: tile.id)
        try commit(library)
    }

    /// Puts a separate copy of the tile into another library.
    func copy(_ tile: Tile, to id: UUID) throws {
        var twin = tile
        twin.id = UUID()
        try save(twin, to: id)
    }

    /// Takes the tile out of one library and puts it into another.
    func move(_ tile: Tile, from source: UUID, to destination: UUID) throws {
        guard let target = library(id: destination), target.portsPerEdge == tile.portsPerEdge else { return }
        try save(tile, to: destination)
        try delete(tile, from: source)
    }

    private func commit(_ library: TileLibrary) throws {
        try store?.write(library)
        var next = libraries.filter { $0.id != library.id }
        next.append(library)
        libraries = Self.sorted(next)
    }
}
