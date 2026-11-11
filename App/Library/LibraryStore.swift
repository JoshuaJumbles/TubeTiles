import Foundation
import TubeKit

/// Reads and writes tile libraries as JSON files in the app's documents.
///
/// For now there is one library per port count. Browsing and managing
/// libraries arrives with the library screen.
struct LibraryStore {
    private var folder: URL {
        URL.documentsDirectory.appendingPathComponent("Libraries", isDirectory: true)
    }

    private func fileURL(portsPerEdge: Int) -> URL {
        folder.appendingPathComponent("ports-\(portsPerEdge).json")
    }

    func library(portsPerEdge: Int) -> TileLibrary {
        let url = fileURL(portsPerEdge: portsPerEdge)
        if let data = try? Data(contentsOf: url),
           let library = try? JSONDecoder().decode(TileLibrary.self, from: data) {
            return library
        }
        return TileLibrary(name: "\(portsPerEdge) ports", portsPerEdge: portsPerEdge)
    }

    func write(_ library: TileLibrary) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(library).write(to: fileURL(portsPerEdge: library.portsPerEdge), options: .atomic)
    }
}
