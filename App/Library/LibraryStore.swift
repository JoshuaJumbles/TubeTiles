import Foundation
import TubeKit

/// Reads and writes tile libraries as JSON files in the app's documents,
/// one file per port count.
struct LibraryStore {
    private var folder: URL {
        URL.documentsDirectory.appendingPathComponent("Libraries", isDirectory: true)
    }

    private func fileURL(portsPerEdge: Int) -> URL {
        folder.appendingPathComponent("ports-\(portsPerEdge).json")
    }

    /// Every library on disk. Files that cannot be read are skipped.
    func allLibraries() -> [TileLibrary] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil
        )) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(TileLibrary.self, from: data)
        }
    }

    func write(_ library: TileLibrary) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(library).write(to: fileURL(portsPerEdge: library.portsPerEdge), options: .atomic)
    }
}
