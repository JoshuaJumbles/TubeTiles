import Observation
import SwiftUI
import TubeKit

/// A pipe being previewed while the user drags towards a port.
struct GhostPipe {
    var pipe: Pipe
    var error: PlacementError?
    /// Where it would break the overlap rule, in tile units.
    var conflicts: [Point]
}

/// State and actions for the tile editor.
@MainActor
@Observable
final class EditorModel {
    private(set) var tile: Tile
    private(set) var kind: PipeKind = .bezier
    /// The free port a new pipe will start from.
    private(set) var selectedPort: Port?
    private(set) var selectedPipe: Pipe?
    /// Free ports a pipe of the current kind could reach from `selectedPort`.
    private(set) var validTargets: Set<Port> = []
    private(set) var ghost: GhostPipe?
    private(set) var message: String?

    private var coverage: CoverageMap
    private var undoStack: [Tile] = []
    private var redoStack: [Tile] = []
    private let library: LibraryModel

    init(library: LibraryModel) {
        self.library = library
        let tile = Tile(portsPerEdge: library.current.portsPerEdge)
        self.tile = tile
        coverage = CoverageMap(tile: tile)
        kind = PipeKind.allCases.first(where: library.current.allowedKinds.contains) ?? .bezier
    }

    /// Whether the tile on the canvas is already in the library, so saving
    /// updates it rather than adding a new one.
    var isSaved: Bool { library.contains(tile) }
    var savedTileCount: Int { library.current.tiles.count }
    var libraryName: String { library.current.name }
    var libraryID: UUID { library.currentID }
    var libraries: [TileLibrary] { library.libraries }

    /// The pipe kinds the current library allows, in palette order.
    var allowedKinds: [PipeKind] {
        PipeKind.allCases.filter(library.current.allowedKinds.contains)
    }

    func chooseLibrary(_ id: UUID) {
        library.select(id)
        libraryChanged()
    }

    /// Brings the editor in line with the current library after it has been
    /// switched or its rules edited: the right port count, and a pipe kind
    /// the library allows.
    func libraryChanged() {
        let current = library.current
        if tile.portsPerEdge != current.portsPerEdge {
            // A tile cannot change port count, so start a fresh one.
            undoStack.removeAll()
            redoStack.removeAll()
            apply(Tile(portsPerEdge: current.portsPerEdge))
        }
        if !current.allowedKinds.contains(kind), let first = allowedKinds.first {
            choose(first)
        }
    }

    var style: TileStyle { TileStyle(portsPerEdge: tile.portsPerEdge) }
    /// Whether the canvas should mark which free ports are usable: the far
    /// ends for a pipe being drawn, or every spot a dead end would fit.
    var highlightsTargets: Bool { selectedPort != nil || kind.isDeadEnd }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: Touch handling

    func tap(_ port: Port?) {
        ghost = nil
        guard let port else {
            select(port: nil)
            selectedPipe = nil
            return
        }
        if let pipe = tile.pipe(at: port) {
            select(port: nil)
            selectedPipe = selectedPipe == pipe ? nil : pipe
            message = nil
            return
        }
        selectedPipe = nil
        if kind.isDeadEnd {
            // A dead end needs only the one port, so a single tap places it.
            _ = place(from: port, to: port)
            return
        }
        guard let start = selectedPort, start != port else {
            select(port: selectedPort == port ? nil : port)
            message = nil
            return
        }
        if place(from: start, to: port) {
            select(port: nil)
        }
    }

    /// Called as a drag that began on `start` moves; `hover` is the port
    /// nearest the finger, if any.
    func drag(from start: Port?, to hover: Port?) {
        guard !kind.isDeadEnd, let start, tile.pipe(at: start) == nil else { return }
        if selectedPort != start {
            selectedPipe = nil
            select(port: start)
        }
        guard let hover, hover != start, tile.pipe(at: hover) == nil else {
            ghost = nil
            return
        }
        let pipe = Pipe(kind, a: start, b: hover)
        guard ghost?.pipe != pipe else { return }
        let error = PlacementRules.error(adding: pipe, to: tile, coverage: coverage)
        ghost = GhostPipe(
            pipe: pipe,
            error: error,
            conflicts: error == .overlap ? coverage.conflicts(adding: pipe) : []
        )
        message = error.map(Self.describe)
    }

    func endDrag() {
        defer { ghost = nil }
        guard let ghost else { return }
        if place(from: ghost.pipe.a, to: ghost.pipe.b) {
            select(port: nil)
        }
    }

    // MARK: Actions

    func choose(_ kind: PipeKind) {
        self.kind = kind
        if kind.isDeadEnd { selectedPort = nil }
        refreshTargets()
    }

    func deleteSelectedPipe() {
        guard let pipe = selectedPipe else { return }
        var next = tile
        next.removePipe(at: pipe.a)
        commit(next)
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(tile)
        apply(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(tile)
        apply(next)
    }

    func newTile() {
        commit(Tile(portsPerEdge: tile.portsPerEdge))
    }

    /// Puts a library tile on the canvas. A copy gets a new identity, so
    /// saving it adds a tile instead of replacing the original.
    func open(_ saved: Tile, asCopy: Bool) {
        var next = saved
        if asCopy { next.id = UUID() }
        commit(next)
    }

    func addRandomPipe() {
        var next = tile
        var generator = SystemRandomNumberGenerator()
        if next.addRandomPipe(kinds: randomKinds, using: &generator) != nil {
            commit(next)
        } else {
            message = "No room for another pipe."
        }
    }

    func fillRandomly() {
        var next = tile
        var generator = SystemRandomNumberGenerator()
        if next.fillRandomly(kinds: randomKinds, using: &generator) > 0 {
            commit(next)
        } else {
            message = "No room for another pipe."
        }
    }

    func save() {
        guard !tile.pipes.isEmpty else {
            message = "Add a pipe before saving."
            return
        }
        let wasSaved = isSaved
        do {
            try library.save(tile)
            message = wasSaved ? "Updated in the library." : "Saved to \u{201C}\(library.current.name)\u{201D}."
        } catch {
            message = "Could not save: \(error.localizedDescription)"
        }
    }

    // MARK: Internals

    /// The kinds random pipes are drawn from: whatever the library allows
    /// that joins two ports. Curves are the staple, and big rooms are rare
    /// because nothing can cross them.
    private var randomKinds: [PipeKind] {
        let weighted: [PipeKind] =
            Array(repeating: .bezier, count: 10) + Array(repeating: .corner, count: 4)
            + Array(repeating: .roomSmall, count: 3) + Array(repeating: .roomMedium, count: 2)
            + [.roomLarge]
        return weighted.filter(library.current.allowedKinds.contains)
    }

    private func place(from start: Port, to end: Port) -> Bool {
        var next = tile
        do {
            try next.add(Pipe(kind, a: start, b: end))
        } catch {
            message = Self.describe(error)
            return false
        }
        commit(next)
        return true
    }

    private func commit(_ next: Tile) {
        undoStack.append(tile)
        redoStack.removeAll()
        apply(next)
    }

    private func apply(_ next: Tile) {
        tile = next
        coverage = CoverageMap(tile: next)
        selectedPipe = nil
        ghost = nil
        message = nil
        select(port: nil)
    }

    private func select(port: Port?) {
        selectedPort = port
        refreshTargets()
    }

    private func refreshTargets() {
        if kind.isDeadEnd {
            validTargets = Set(tile.freePorts.filter {
                PlacementRules.error(adding: Pipe(kind, at: $0), to: tile, coverage: coverage) == nil
            })
            return
        }
        guard let start = selectedPort else {
            validTargets = []
            return
        }
        validTargets = Set(tile.freePorts.filter { candidate in
            candidate != start
                && PlacementRules.error(adding: Pipe(kind, a: start, b: candidate), to: tile, coverage: coverage) == nil
        })
    }

    private static func describe(_ error: PlacementError) -> String {
        switch error {
        case .portOutOfRange, .samePort: "Pick two different ports."
        case .portOccupied: "That port already has a pipe."
        case .tightUTurn: "Too tight a U-turn for a curve."
        case .needsTwoEdges: "Corners and rooms need two different edges."
        case .mustRunStraightAcross: "Across the tile, this kind only runs straight."
        case .overlap: "Too many pipes would overlap there."
        case .deadEndNeedsOnePort: "A dead end uses a single port."
        }
    }
}
