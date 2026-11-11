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
    static let portRange = 2...8

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

    init(library: LibraryModel, portsPerEdge: Int = 6) {
        self.library = library
        let tile = Tile(portsPerEdge: portsPerEdge)
        self.tile = tile
        coverage = CoverageMap(tile: tile)
    }

    /// Whether the tile on the canvas is already in the library, so saving
    /// updates it rather than adding a new one.
    var isSaved: Bool { library.contains(tile) }
    var savedTileCount: Int { library.library(portsPerEdge: tile.portsPerEdge).tiles.count }

    var style: TileStyle { TileStyle(portsPerEdge: tile.portsPerEdge) }
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
        guard let start, tile.pipe(at: start) == nil else { return }
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

    func setPortsPerEdge(_ count: Int) {
        guard count != tile.portsPerEdge, Self.portRange.contains(count) else { return }
        commit(Tile(portsPerEdge: count))
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
        if next.addRandomPipe(kinds: Self.randomKinds, using: &generator) != nil {
            commit(next)
        } else {
            message = "No room for another pipe."
        }
    }

    func fillRandomly() {
        var next = tile
        var generator = SystemRandomNumberGenerator()
        if next.fillRandomly(kinds: Self.randomKinds, using: &generator) > 0 {
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
            message = wasSaved ? "Updated in the library." : "Saved to the \(tile.portsPerEdge)-port library."
        } catch {
            message = "Could not save: \(error.localizedDescription)"
        }
    }

    // MARK: Internals

    /// Curves are the staple; big rooms are rare because nothing can cross them.
    private static let randomKinds: [PipeKind] =
        Array(repeating: .bezier, count: 10) + Array(repeating: .corner, count: 4)
        + Array(repeating: .roomSmall, count: 3) + Array(repeating: .roomMedium, count: 2)
        + [.roomLarge]

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
        }
    }
}
