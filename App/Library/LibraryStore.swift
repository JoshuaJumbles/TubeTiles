import Foundation
import TubeKit

/// Reads and writes tile libraries as JSON files in the app's documents,
/// one file per library, named by the library's identity.
struct LibraryStore {
    private var folder: URL {
        URL.documentsDirectory.appendingPathComponent("Libraries", isDirectory: true)
    }

    private func fileURL(for id: UUID) -> URL {
        folder.appendingPathComponent("\(id.uuidString).json")
    }

    /// Every library on disk. Files that cannot be read are skipped.
    ///
    /// Libraries used to be stored one per port count, in files named after
    /// the count. Any such file is rewritten under its library's identity the
    /// first time it is loaded, so the identity stays the same from then on.
    func allLibraries() -> [TileLibrary] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil
        )) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let library = try? JSONDecoder().decode(TileLibrary.self, from: data)
            else { return nil }
            if url.lastPathComponent != fileURL(for: library.id).lastPathComponent,
               (try? write(library)) != nil {
                try? FileManager.default.removeItem(at: url)
            }
            return library
        }
    }

    func write(_ library: TileLibrary) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(library).write(to: fileURL(for: library.id), options: .atomic)
    }

    func delete(id: UUID) throws {
        let url = fileURL(for: id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
