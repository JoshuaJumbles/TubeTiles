import Observation
import SwiftUI
import TubeKit

/// State and actions for the maze generator.
@MainActor
@Observable
final class GeneratorModel {
    static let radiusRange = 1...6

    private(set) var maze: Maze
    var symmetry: Symmetry = .none
    /// Whether the generator may make up tiles the library does not have.
    var allowsGeneratedTiles = true
    /// How readily made-up tiles send out new pipes, 0 to 1.
    var growth = 0.5
    /// Colours each path so separate loops can be told apart. While on,
    /// tapping a pipe keeps or releases its loop instead of selecting a tile.
    var showsPaths = true
    /// Pipe ends on loops that merging must leave alone.
    private(set) var kept: Set<PortRef> = []
    private(set) var selected: HexCoord?
    private(set) var activity: Activity?
    private(set) var message: String?

    enum Activity {
        case growing, merging
    }

    var isRunning: Bool { activity != nil }

    private let library: LibraryModel
    private var runner: Task<Void, Never>?
    private var random = SystemRandomNumberGenerator()

    init(library: LibraryModel) {
        self.library = library
        let counts = library.portCounts
        let fullest = counts.max {
            library.library(portsPerEdge: $0).tiles.count < library.library(portsPerEdge: $1).tiles.count
        }
        maze = Maze(portsPerEdge: fullest ?? 6, radius: 3)
    }

    // MARK: Derived state

    var portsPerEdge: Int { maze.portsPerEdge }
    var radius: Int { maze.radius }
    var openCells: [HexCoord] { maze.openCells }
    var libraryTileCount: Int { library.library(portsPerEdge: portsPerEdge).tiles.count }
    var generatedTileCount: Int { maze.cells.values.filter(\.isGenerated).count }

    /// Port counts worth offering: any with saved tiles, plus the current one.
    var portChoices: [Int] {
        Array(Set(library.portCounts + [portsPerEdge])).sorted()
    }

    var paths: MazePaths { maze.paths }

    /// Indexes of the paths that are being kept as they are.
    func keptPaths(in paths: MazePaths) -> Set<Int> {
        Set(kept.compactMap { paths.index(of: $0) })
    }

    var summary: String {
        if maze.cells.isEmpty { return "Empty. Tap a cell, or press Grow." }
        let open = openCells.count
        guard open == 0 else { return "\(maze.cells.count) of \(maze.cellCount) cells · \(open) open" }
        let loops = paths.loopCount
        return "Sealed · \(maze.cells.count) tiles · " + (loops == 1 ? "one path" : "\(loops) loops")
    }

    private var generator: MazeGenerator {
        MazeGenerator(
            tiles: library.library(portsPerEdge: portsPerEdge).tiles,
            synthesis: allowsGeneratedTiles ? .init(growth: growth) : nil
        )
    }

    // MARK: Setup

    func setRadius(_ radius: Int) {
        guard radius != maze.radius, Self.radiusRange.contains(radius) else { return }
        reset(portsPerEdge: portsPerEdge, radius: radius)
    }

    func setPortsPerEdge(_ count: Int) {
        guard count != portsPerEdge else { return }
        reset(portsPerEdge: count, radius: radius)
    }

    func clear() {
        reset(portsPerEdge: portsPerEdge, radius: radius)
    }

    private func reset(portsPerEdge: Int, radius: Int) {
        stop()
        maze = Maze(portsPerEdge: portsPerEdge, radius: radius)
        selected = nil
        kept = []
        message = nil
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
            message = "One continuous path."
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
