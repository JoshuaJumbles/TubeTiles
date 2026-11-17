import CoreTransferable
import Foundation
import TubeKit
import UniformTypeIdentifiers

/// A library as a file that can be sent to another device and imported
/// there. It is the same JSON the app stores libraries in.
struct LibraryFile: Transferable {
    var library: TileLibrary

    /// The library's name, made safe for a file name.
    var fileName: String {
        let unsafe = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines)
        let name = library.name.components(separatedBy: unsafe).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return (name.isEmpty ? "Library" : name) + ".tubetiles.json"
    }

    static func encode(_ library: TileLibrary) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(library)
    }

    /// Reads a library from a file's contents.
    static func decode(_ data: Data) throws -> TileLibrary {
        try JSONDecoder().decode(TileLibrary.self, from: data)
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { try encode($0.library) }
            .suggestedFileName { $0.fileName }
    }
}
