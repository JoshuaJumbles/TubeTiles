import Foundation
import Observation
import TubeKit

/// A maze saved under a name, with the settings needed to carry on with it.
struct SavedMaze: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var created = Date()
    var modified = Date()
    var maze: Maze
    var symmetry: Symmetry = .none
    /// Pipe ends on loops that merging should leave alone.
    var kept: Set<PortRef> = []
}

/// Whatever was on the generator when the app was last used, so it comes
/// back as it was.
struct WorkingCopy: Codable {
    var maze: Maze
    var symmetry: Symmetry
    var kept: Set<PortRef>
    /// The saved maze this was opened from or saved to, if any.
    var documentID: UUID?
}

/// The saved mazes, kept as one JSON file each in the app's documents.
@MainActor
@Observable
final class MazeArchive {
    /// Most recently changed first.
    private(set) var mazes: [SavedMaze] = []
    /// Nil keeps everything in memory, for previews and sample data.
    private let folder: URL?

    init(persists: Bool = true) {
        folder = persists ? URL.documentsDirectory.appendingPathComponent("Mazes", isDirectory: true) : nil
        guard let folder else { return }
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        mazes = files
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != Self.workingCopyName }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? Self.decoder.decode(SavedMaze.self, from: data)
            }
            .sorted { $0.modified > $1.modified }
    }

    private static let workingCopyName = "working-copy.json"

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private func write(_ value: some Encodable, to name: String) throws {
        guard let folder else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Self.encoder.encode(value).write(to: folder.appendingPathComponent(name), options: .atomic)
    }

    func maze(id: UUID?) -> SavedMaze? {
        mazes.first { $0.id == id }
    }

    /// A name not yet in use: "Maze 1", "Maze 2", and so on.
    func unusedName() -> String {
        let taken = Set(mazes.map(\.name))
        var number = mazes.count + 1
        while taken.contains("Maze \(number)") { number += 1 }
        return "Maze \(number)"
    }

    /// Adds the maze, or replaces the saved maze with the same identity.
    func save(_ maze: SavedMaze) throws {
        try write(maze, to: "\(maze.id.uuidString).json")
        mazes.removeAll { $0.id == maze.id }
        mazes.insert(maze, at: 0)
    }

    func rename(id: UUID, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var maze = maze(id: id), !trimmed.isEmpty else { return }
        maze.name = trimmed
        try write(maze, to: "\(maze.id.uuidString).json")
        if let index = mazes.firstIndex(where: { $0.id == id }) {
            mazes[index] = maze
        }
    }

    func delete(id: UUID) throws {
        if let folder {
            let url = folder.appendingPathComponent("\(id.uuidString).json")
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
        mazes.removeAll { $0.id == id }
    }

    func loadWorkingCopy() -> WorkingCopy? {
        guard let folder,
              let data = try? Data(contentsOf: folder.appendingPathComponent(Self.workingCopyName))
        else { return nil }
        return try? Self.decoder.decode(WorkingCopy.self, from: data)
    }

    func saveWorkingCopy(_ copy: WorkingCopy) {
        try? write(copy, to: Self.workingCopyName)
    }
}
