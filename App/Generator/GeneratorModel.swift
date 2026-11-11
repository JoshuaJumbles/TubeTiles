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
    private(set) var selected: HexCoord?
    private(set) var isRunning = false
    private(set) var message: String?

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

    var summary: String {
        if maze.cells.isEmpty { return "Empty. Tap a cell, or press Grow." }
        let open = openCells.count
        let tiles = "\(maze.cells.count) of \(maze.cellCount) cells"
        return open == 0 ? "Sealed · \(tiles)" : "\(tiles) · \(open) open"
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
        message = nil
    }

    // MARK: Growing

    /// Makes one move. Returns false when there is nothing more to do.
    @discardableResult
    func step() -> Bool {
        selected = nil
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
        if isRunning {
            stop()
            return
        }
        isRunning = true
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
            self?.isRunning = false
        }
    }

    /// Grows to completion in one go.
    func fill() {
        stop()
        selected = nil
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
        isRunning = false
    }

    // MARK: Hand editing

    /// A tap on a tile selects it. A tap on an empty cell grows a tile there.
    func tap(_ coord: HexCoord?) {
        stop()
        guard let coord, maze.contains(coord) else {
            selected = nil
            return
        }
        if maze.cells[coord] != nil {
            selected = selected == coord ? nil : coord
            return
        }
        selected = nil
        if let next = generator.placingRandomTile(in: maze, at: coord, symmetry: symmetry, using: &random) {
            maze = next
            message = nil
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
    }

    /// Swaps the selected tile for a different one that fits the same spot.
    func rerollSelected() {
        guard let selected else { return }
        var trial = maze
        trial.remove(at: selected, symmetry: symmetry)
        if let next = generator.placingRandomTile(in: trial, at: selected, symmetry: symmetry, using: &random) {
            maze = next
            message = nil
        } else {
            message = "No other tile fits there."
        }
    }
}
