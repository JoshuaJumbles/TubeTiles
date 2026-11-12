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

/// A cell of the maze that a tile is being drawn for.
struct GapBrief: Equatable {
    var brief: TileBrief
    var coord: HexCoord
}

/// State and actions for the tile editor.
@MainActor
@Observable
final class EditorModel {
    private(set) var tile: Tile
    private(set) var kind: PipeKind = .bezier
    /// True while the eraser is the tool in use: touching a pipe removes it.
    private(set) var isErasing = false
    /// The free port a new pipe will start from.
    private(set) var selectedPort: Port?
    private(set) var selectedPipe: Pipe?
    /// Free ports a pipe of the current kind could reach from `selectedPort`.
    private(set) var validTargets: Set<Port> = []
    private(set) var ghost: GhostPipe?
    private(set) var message: String?
    /// Set while a tile is being drawn to fill a cell of the maze. The
    /// canvas marks the ports the cell needs.
    private(set) var gap: GapBrief?
    /// Hands a finished tile back to the generator, for the cell it was
    /// drawn for.
    var onPlace: ((Tile, HexCoord) -> Void)?

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
    /// Set when another tile in the library already draws these pipes, as
    /// they are or turned or flipped. Saving is still allowed.
    var duplicateNote: String? {
        guard let twin = library.current.twin(of: tile) else { return nil }
        if twin.transform == .identity { return "Already in library" }
        return twin.transform.mirrored
            ? "Already in library, flipped"
            : "Already in library, turned"
    }
    /// Whether the tile on the canvas would fill the gap it is drawn for.
    var fitsGap: Bool { gap?.brief.isMet(by: tile) ?? false }

    /// How far the tile is from filling the gap, in a few words.
    var gapStatus: String? {
        guard let brief = gap?.brief else { return nil }
        if brief.isMet(by: tile) { return "Fits the gap" }
        var needs: [String] = []
        let missing = brief.missing(in: tile).count
        let unwanted = brief.unwanted(in: tile).count
        if missing > 0 { needs.append("\(missing) to connect") }
        if unwanted > 0 { needs.append("\(unwanted) to clear") }
        if !brief.hasRightDeadEnds(tile) { needs.append(brief.needsDeadEnd ? "one dead end" : "no dead ends") }
        return needs.isEmpty ? "Gap: add a pipe" : "Gap: " + needs.joined(separator: ", ")
    }

    var savedTileCount: Int { library.current.tiles.count }
    var libraryName: String { library.current.name }
    var libraryID: UUID { library.currentID }
    var libraries: [TileLibrary] { library.libraries }

    /// Ports the current library leaves unused. They are shown faded and
    /// cannot start or finish a new pipe.
    var deadPorts: Set<Port> { library.current.deadPorts }

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
            gap = nil
        }
        if !current.allowedKinds.contains(kind), let first = allowedKinds.first {
            choose(first)
        }
    }

    var style: TileStyle { TileStyle(portsPerEdge: tile.portsPerEdge) }
    /// Whether the canvas should mark which free ports are usable: the far
    /// ends for a pipe being drawn, or every spot a dead end would fit.
    var highlightsTargets: Bool { !isErasing && (selectedPort != nil || kind.isDeadEnd) }
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
        if isErasing {
            // Tapping a pipe's end erases it, like tapping along its length.
            if let pipe = tile.pipe(at: port) { remove(pipe) }
            return
        }
        if let pipe = tile.pipe(at: port) {
            select(port: nil)
            selectedPipe = selectedPipe == pipe ? nil : pipe
            message = nil
            return
        }
        selectedPipe = nil
        guard !deadPorts.contains(port) else {
            message = "That port is switched off in this library."
            return
        }
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
        guard !isErasing, !kind.isDeadEnd, let start, tile.pipe(at: start) == nil, !deadPorts.contains(start)
        else { return }
        if selectedPort != start {
            selectedPipe = nil
            select(port: start)
        }
        guard let hover, hover != start, tile.pipe(at: hover) == nil, !deadPorts.contains(hover) else {
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
        isErasing = false
        if kind.isDeadEnd { selectedPort = nil }
        refreshTargets()
    }

    /// Switches to the eraser. It stays on until a pipe kind is chosen.
    func chooseEraser() {
        isErasing = true
        selectedPort = nil
        selectedPipe = nil
        ghost = nil
        message = nil
        refreshTargets()
    }

    /// Erases the pipe under a touch, if there is one. `point` is measured
    /// from the tile's centre in tile units. Called for taps and as a finger
    /// drags across the tile, so several pipes can go in one stroke; each is
    /// its own step for undo.
    func erase(at point: Point) {
        guard isErasing else { return }
        let style = style
        let reach = style.pipeWidth * 0.75
        let nearest = tile.pipes
            .map { (pipe: $0, distance: PipeShape($0, style: style).distance(to: point)) }
            .filter { $0.distance <= reach }
            .min { $0.distance < $1.distance }
        if let nearest { remove(nearest.pipe) }
    }

    func deleteSelectedPipe() {
        guard let pipe = selectedPipe else { return }
        remove(pipe)
    }

    private func remove(_ pipe: Pipe) {
        var next = tile
        next.removePipe(at: pipe.a)
        commit(next)
    }

    /// Carries on with a copy of the tile on the canvas. The copy has a new
    /// identity, so saving it adds a tile and leaves the original as it was
    /// last saved.
    func makeVariant() {
        guard !tile.pipes.isEmpty else { return }
        var next = tile
        next.id = UUID()
        commit(next)
        message = "This is a copy. Saving adds it as a new tile."
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

    // MARK: Drawing for a gap in the maze

    /// Starts a fresh tile for a cell of the maze and marks what it needs.
    func design(for gap: GapBrief) {
        guard gap.brief.portsPerEdge == library.current.portsPerEdge else { return }
        if !tile.pipes.isEmpty { commit(Tile(portsPerEdge: tile.portsPerEdge)) }
        self.gap = gap
        message = nil
    }

    func dismissGap() {
        gap = nil
    }

    /// Saves the tile and puts it in the cell it was drawn for.
    func saveAndPlace() {
        guard let gap, fitsGap else { return }
        save()
        guard isSaved else { return }
        self.gap = nil
        onPlace?(tile, gap.coord)
    }

    func addRandomPipe() {
        var next = tile
        var generator = SystemRandomNumberGenerator()
        if next.addRandomPipe(kinds: randomKinds, avoiding: deadPorts, using: &generator) != nil {
            commit(next)
        } else {
            message = "No room for another pipe."
        }
    }

    func fillRandomly() {
        var next = tile
        var generator = SystemRandomNumberGenerator()
        if next.fillRandomly(kinds: randomKinds, avoiding: deadPorts, using: &generator) > 0 {
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
        guard !isErasing else {
            validTargets = []
            return
        }
        let dead = deadPorts
        if kind.isDeadEnd {
            validTargets = Set(tile.freePorts.filter {
                !dead.contains($0)
                    && PlacementRules.error(adding: Pipe(kind, at: $0), to: tile, coverage: coverage) == nil
            })
            return
        }
        guard let start = selectedPort else {
            validTargets = []
            return
        }
        validTargets = Set(tile.freePorts.filter { candidate in
            candidate != start && !dead.contains(candidate)
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
