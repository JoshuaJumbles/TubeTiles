import Observation
import SwiftUI
import TubeKit

/// State and actions for the maze generator.
@MainActor
@Observable
final class GeneratorModel {
    static let radiusRange = 1...6

    private(set) var maze: Maze {
        didSet {
            guard maze != oldValue else { return }
            // Worked out once per change, not on every redraw, so zooming
            // and panning stay smooth.
            paths = maze.paths
            weave = maze.weave()
            scheduleAutosave()
        }
    }
    /// Every path through the maze, kept up to date with it.
    private(set) var paths: MazePaths
    /// Over and under for every crossing, kept up to date with the maze.
    private(set) var weave: Weave
    /// How far the canvas is zoomed in and where it has been dragged to.
    var viewport = Viewport()
    var symmetry: Symmetry = .none {
        didSet { if symmetry != oldValue { scheduleAutosave() } }
    }
    /// Whether the generator may make up tiles the library does not have.
    var allowsGeneratedTiles = true
    /// How readily made-up tiles send out new pipes, 0 to 1.
    var growth = 0.5
    /// Colours each path so separate loops can be told apart. While on,
    /// tapping a pipe keeps or releases its loop instead of selecting a tile.
    var showsPaths = true
    /// Pipe ends on loops that merging must leave alone.
    private(set) var kept: Set<PortRef> = [] {
        didSet { if kept != oldValue { scheduleAutosave() } }
    }
    /// The saved maze this one was opened from or last saved to, if any.
    private(set) var documentID: UUID?
    private(set) var selected: HexCoord?
    private(set) var activity: Activity?
    private(set) var message: String?

    enum Activity {
        case growing, merging
    }

    var isRunning: Bool { activity != nil }

    private let library: LibraryModel
    private let archive: MazeArchive
    private var runner: Task<Void, Never>?
    private var autosave: Task<Void, Never>?
    private var random = SystemRandomNumberGenerator()

    init(library: LibraryModel, archive: MazeArchive) {
        self.library = library
        self.archive = archive
        let start: Maze
        if let working = archive.loadWorkingCopy() {
            // Pick up where the last session left off.
            start = working.maze
            symmetry = working.symmetry
            kept = working.kept
            documentID = archive.maze(id: working.documentID)?.id
        } else {
            start = Maze(portsPerEdge: library.current.portsPerEdge, radius: 3)
        }
        maze = start
        paths = start.paths
        weave = start.weave()
    }

    // MARK: Saving

    /// Whether the maze differs from its saved version, or has never been
    /// saved at all.
    var hasUnsavedChanges: Bool {
        guard let saved = archive.maze(id: documentID) else { return true }
        return saved.maze != maze || saved.symmetry != symmetry || saved.kept != kept
    }

    /// Saves over the maze this one came from, or as a new maze if it has
    /// never been saved.
    func save() {
        guard !maze.cells.isEmpty else { return }
        var saved = archive.maze(id: documentID) ?? SavedMaze(name: archive.unusedName(), maze: maze)
        saved.maze = maze
        saved.symmetry = symmetry
        saved.kept = kept
        saved.modified = Date()
        store(saved)
    }

    /// Saves a separate copy and carries on working on the copy.
    func saveAsNew() {
        guard !maze.cells.isEmpty else { return }
        store(SavedMaze(name: archive.unusedName(), maze: maze, symmetry: symmetry, kept: kept))
    }

    private func store(_ saved: SavedMaze) {
        do {
            try archive.save(saved)
            documentID = saved.id
            message = "Saved as \u{201C}\(saved.name)\u{201D}."
            writeWorkingCopy()
        } catch {
            message = "Could not save: \(error.localizedDescription)"
        }
    }

    func open(_ saved: SavedMaze) {
        stop()
        maze = saved.maze
        symmetry = saved.symmetry
        kept = saved.kept
        documentID = saved.id
        selected = nil
        message = nil
        viewport = Viewport()
        writeWorkingCopy()
    }

    /// Clears the generator and detaches it from any saved maze.
    func startNewMaze() {
        documentID = nil
        clear()
        writeWorkingCopy()
    }

    func delete(_ saved: SavedMaze) {
        try? archive.delete(id: saved.id)
        if documentID == saved.id {
            documentID = nil
            writeWorkingCopy()
        }
    }

    /// Writes the working copy shortly after the last change, so a burst of
    /// changes (a maze growing step by step) costs one write.
    private func scheduleAutosave() {
        autosave?.cancel()
        autosave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.writeWorkingCopy()
        }
    }

    /// Writes the working copy now. Called when the app is about to leave
    /// the foreground, as well as after changes settle.
    func writeWorkingCopy() {
        autosave?.cancel()
        archive.saveWorkingCopy(WorkingCopy(maze: maze, symmetry: symmetry, kept: kept, documentID: documentID))
    }

    // MARK: Derived state

    var portsPerEdge: Int { maze.portsPerEdge }
    var radius: Int { maze.radius }
    var openCells: [HexCoord] { maze.openCells }
    /// The library the generator draws from: the current one, provided its
    /// tiles have the same port count as the maze.
    var activeLibrary: TileLibrary? {
        library.current.portsPerEdge == portsPerEdge ? library.current : nil
    }

    var currentLibrary: TileLibrary { library.current }
    var libraries: [TileLibrary] { library.libraries }
    var libraryTileCount: Int { activeLibrary?.tiles.count ?? 0 }
    var generatedTileCount: Int { maze.cells.values.filter(\.isGenerated).count }

    /// The maze as a drawing to share. Path colours are included while they
    /// are shown on screen; otherwise the tubes are plain white.
    var drawing: MazeDrawing {
        var options = MazeSVG.Options()
        if showsPaths {
            let paths = paths
            let kept = keptPaths(in: paths)
            for (index, path) in paths.paths.enumerated() where !kept.contains(index) {
                options.pathColors[index] = PathTint.hex(for: path)
            }
        }
        return MazeDrawing(maze: maze, options: options)
    }

    /// Indexes of the paths that are being kept as they are.
    func keptPaths(in paths: MazePaths) -> Set<Int> {
        Set(kept.compactMap { paths.index(of: $0) })
    }

    var summary: String {
        if maze.cells.isEmpty { return "Empty. Tap a cell, or press Grow." }
        let open = openCells.count
        guard open == 0 else { return "\(maze.cells.count) of \(maze.cellCount) cells · \(open) open" }
        let count = paths.paths.count
        let isOpen = maze.endCount > 0
        let what = count == 1 ? "one path" : "\(count) \(isOpen ? "paths" : "loops")"
        return "Sealed · \(maze.cells.count) tiles · " + what
    }

    /// How tiles are made up: in the library's kinds when it applies to
    /// this maze, so they match its hand-made tiles.
    private var synthesis: MazeGenerator.Synthesis {
        if let activeLibrary {
            return .init(growth: growth, following: activeLibrary)
        }
        return .init(growth: growth)
    }

    private var generator: MazeGenerator {
        MazeGenerator(
            tiles: activeLibrary?.tiles ?? [],
            synthesis: allowsGeneratedTiles ? synthesis : nil
        )
    }

    // MARK: Setup

    func setRadius(_ radius: Int) {
        guard radius != maze.radius, Self.radiusRange.contains(radius) else { return }
        reset(portsPerEdge: portsPerEdge, radius: radius)
    }

    /// Switches the library the generator draws from. A maze keeps the port
    /// count it was started with, so a library with a different count only
    /// takes over an empty generator.
    func chooseLibrary(_ id: UUID) {
        library.select(id)
        libraryChanged()
    }

    /// Called when the current library changes, here or on another screen.
    func libraryChanged() {
        let current = library.current
        guard current.portsPerEdge != portsPerEdge else {
            message = nil
            return
        }
        if maze.cells.isEmpty {
            reset(portsPerEdge: current.portsPerEdge, radius: radius)
        } else {
            message = "This maze has \(portsPerEdge) ports per edge. Clear it to use \u{201C}\(current.name)\u{201D}, which has \(current.portsPerEdge)."
        }
    }

    /// Empties the generator. The next maze takes its port count from the
    /// current library.
    func clear() {
        reset(portsPerEdge: library.current.portsPerEdge, radius: radius)
    }

    private func reset(portsPerEdge: Int, radius: Int) {
        stop()
        let openings = maze.openings
        let sameShape = portsPerEdge == maze.portsPerEdge && radius == maze.radius
        maze = Maze(portsPerEdge: portsPerEdge, radius: radius)
        // Clearing the tiles keeps the entrance and exit; a different size
        // or port count has a different outline, so they are dropped.
        if sameShape {
            maze.setOpenings(openings)
        } else {
            viewport = Viewport()
        }
        selected = nil
        kept = []
        message = nil
    }

    // MARK: Entrance and exit

    /// Adds or removes an opening on the outline. A path needs two ends, so
    /// the maze is only patched up once there are none or two.
    func toggleOpening(_ ref: PortRef) {
        stop()
        selected = nil
        var openings = maze.openings
        if openings.contains(ref) {
            openings.remove(ref)
        } else if openings.count >= 2 {
            message = "There is already an entrance and an exit. Tap one to remove it first."
            return
        } else {
            openings.insert(ref)
        }
        applyOpenings(openings)
    }

    /// Puts an entrance at a random spot on the outline and an exit directly
    /// opposite it.
    func addOpposedOpenings() {
        guard let entrance = maze.outlinePorts.randomElement(using: &random) else { return }
        let halfTurn = TileTransform(turns: 3)
        let exit = PortRef(
            coord: entrance.coord.transformed(by: halfTurn),
            port: halfTurn.apply(to: entrance.port, portsPerEdge: portsPerEdge)
        )
        applyOpenings([entrance, exit])
    }

    func removeOpenings() {
        applyOpenings([])
    }

    private func applyOpenings(_ openings: Set<PortRef>) {
        stop()
        let hadTiles = !maze.cells.isEmpty
        maze.setOpenings(openings)
        settleEnds(hadTiles: hadTiles)
    }

    // MARK: Goals

    /// Makes a cell a goal, or stops it being one. A goal's tile ends a path
    /// in a room.
    func toggleGoal(_ coord: HexCoord) {
        stop()
        selected = nil
        var goals = maze.goals
        if goals.contains(coord) {
            goals.remove(coord)
        } else if goals.count >= 2 {
            message = "There are already two goals. Touch and hold one to remove it first."
            return
        } else {
            goals.insert(coord)
        }
        applyGoals(goals)
    }

    func addCentreGoal() {
        applyGoals(maze.goals.union([.origin]))
    }

    func removeGoals() {
        applyGoals([])
    }

    private func applyGoals(_ goals: Set<HexCoord>) {
        stop()
        let hadTiles = !maze.cells.isEmpty
        maze.setGoals(goals)
        settleEnds(hadTiles: hadTiles)
    }

    /// Every path has two ends, so openings and goals must come to an even
    /// number before the maze can be grown.
    private var hasPairedEnds: Bool {
        guard maze.endCount % 2 != 0 else { return true }
        message = "A path needs two ends. Add an entrance on the outline, or a second goal."
        return false
    }

    /// After openings or goals change: regrow what was taken out, or say
    /// what is still missing.
    private func settleEnds(hadTiles: Bool) {
        pruneKept()
        if !hasPairedEnds { return }
        if hadTiles {
            fill()
        } else {
            message = nil
        }
    }

    /// Forgets kept loops whose pipes are no longer in the maze.
    private func pruneKept() {
        let paths = paths
        kept = kept.filter { paths.index(of: $0) != nil }
    }

    // MARK: Growing

    /// Makes one move. Returns false when there is nothing more to do.
    @discardableResult
    func step() -> Bool {
        selected = nil
        guard hasPairedEnds else { return false }
        defer { pruneKept() }
        switch generator.step(&maze, symmetry: symmetry, using: &random) {
        case .placed, .cleared:
            message = nil
            return true
        case .sealed:
            message = nil
            return false
        case .stuck:
            message = allowsGeneratedTiles
                ? "Nothing fits here. Try clearing, or a different symmetry."
                : "No library tile fits. Add tiles, or allow generated tiles."
            return false
        }
    }

    /// Grows step by step so the maze can be watched forming.
    func toggleRunning() {
        if activity == .growing {
            stop()
            return
        }
        stop()
        activity = .growing
        runner = Task { [weak self] in
            var steps = 0
            while let self, !Task.isCancelled {
                let limit = self.maze.cellCount * 30
                guard self.step() else { break }
                steps += 1
                if steps >= limit {
                    self.message = "Stopped after \(limit) moves without sealing."
                    break
                }
                try? await Task.sleep(for: .milliseconds(45))
            }
            if !Task.isCancelled { self?.activity = nil }
        }
    }

    // MARK: Paths

    /// Joins two loops by rewiring a tile they share. Returns false when
    /// nothing more can be joined.
    @discardableResult
    func mergeOnce() -> Bool {
        selected = nil
        guard maze.isSealed else {
            message = "Finish the maze first: some cells are still open."
            return false
        }
        let merger = LoopMerger(generator: generator)
        if merger.mergeStep(&maze, keeping: kept, symmetry: symmetry, using: &random) {
            message = nil
            return true
        }
        let paths = paths
        let free = paths.paths.count - keptPaths(in: paths).count
        if paths.paths.count == 1 {
            message = switch (maze.openings.count, maze.goals.count) {
            case (2, 0): "One path from entrance to exit."
            case (1, 1): "One path from the entrance to the goal."
            case (0, 2): "One path from room to room."
            default: "One continuous path."
            }
        } else if free <= 1 {
            message = "Only kept loops are left."
        } else if symmetry == .mirror {
            message = "No more joins keep the mirror symmetry."
        } else {
            message = "The remaining loops share no tile that can be rewired."
        }
        return false
    }

    /// Joins loops one at a time so the paths can be watched combining.
    func toggleMerging() {
        if activity == .merging {
            stop()
            return
        }
        stop()
        activity = .merging
        runner = Task { [weak self] in
            while let self, !Task.isCancelled {
                guard self.mergeOnce() else { break }
                try? await Task.sleep(for: .milliseconds(350))
            }
            if !Task.isCancelled { self?.activity = nil }
        }
    }

    /// Keeps or releases the loop whose pipe is nearest a point in a tile.
    /// `local` is measured from the tile's centre, in tile units.
    private func toggleKept(at coord: HexCoord, local: Point) {
        guard let placed = maze.cells[coord] else { return }
        let style = TileStyle(portsPerEdge: portsPerEdge)
        let nearest = placed.oriented.pipes.min {
            PipeShape($0, style: style).distance(to: local) < PipeShape($1, style: style).distance(to: local)
        }
        let paths = paths
        guard let nearest, let index = paths.index(of: nearest, at: coord) else { return }
        let refs = paths.paths[index].portRefs
        if kept.isDisjoint(with: refs) {
            kept.insert(PortRef(coord: coord, port: nearest.a))
            message = "Loop kept. Merging will leave it alone."
        } else {
            kept.subtract(refs)
            message = "Loop released."
        }
    }

    /// Grows to completion in one go.
    func fill() {
        stop()
        selected = nil
        guard hasPairedEnds else { return }
        defer { pruneKept() }
        if generator.fill(&maze, symmetry: symmetry, using: &random) {
            message = nil
        } else if !maze.cells.isEmpty {
            message = "Could not seal every opening. Press Fill again to keep trying."
        } else {
            message = "Nothing fits. Add tiles, or allow generated tiles."
        }
    }

    func stop() {
        runner?.cancel()
        runner = nil
        activity = nil
    }

    // MARK: Hand editing

    /// A tap on an empty cell grows a tile there. A tap on a tile selects it,
    /// or, while paths are shown, keeps or releases the loop under the finger.
    func tap(_ coord: HexCoord?, local: Point = .zero) {
        stop()
        guard let coord, maze.contains(coord) else {
            selected = nil
            return
        }
        if maze.cells[coord] != nil {
            if showsPaths {
                selected = nil
                toggleKept(at: coord, local: local)
            } else {
                selected = selected == coord ? nil : coord
            }
            return
        }
        selected = nil
        if let next = generator.placingRandomTile(in: maze, at: coord, symmetry: symmetry, using: &random) {
            maze = next
            message = nil
            pruneKept()
        } else {
            message = "Nothing fits in that cell."
        }
    }

    /// Removes the selected tile and its images under the current symmetry.
    func deleteSelected() {
        guard let selected else { return }
        maze.remove(at: selected, symmetry: symmetry)
        self.selected = nil
        message = nil
        pruneKept()
    }

    /// Swaps the selected tile for a different one that fits the same spot.
    func rerollSelected() {
        guard let selected else { return }
        var trial = maze
        trial.remove(at: selected, symmetry: symmetry)
        if let next = generator.placingRandomTile(in: trial, at: selected, symmetry: symmetry, using: &random) {
            maze = next
            message = nil
            pruneKept()
        } else {
            message = "No other tile fits there."
        }
    }
}
