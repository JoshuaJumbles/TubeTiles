import Foundation

/// Reads tiles exported by the original Processing tile editor.
///
/// A set is a folder laid out as
/// `<set>/Pipes_<edge code>/pipe<N>_<types>/<set>_<N>.txt`, where the text
/// file has one pipe per line such as `BZR_23_26` (kind, then two flat port
/// indices). The number of ports per edge is not recorded anywhere, so it is
/// worked out from the edge code in the folder name.
public enum LegacyFormat {
    public struct PipeLine: Hashable, Sendable {
        public var kind: PipeKind
        public var index0: Int
        public var index1: Int

        public init(kind: PipeKind, index0: Int, index1: Int) {
            self.kind = kind
            self.index0 = index0
            self.index1 = index1
        }
    }

    public enum ImportError: Error, Equatable {
        case malformedPipeLine(String)
        case malformedFolderName(String)
        /// No port count makes every tile agree with its folder's edge code.
        case cannotInferPortsPerEdge
    }

    public static func code(for kind: PipeKind) -> String {
        switch kind {
        case .corner: "CNR"
        case .bezier: "BZR"
        case .roomSmall: "CR0"
        case .roomMedium: "CR1"
        case .roomLarge: "CR2"
        // Dead ends did not exist in the original editor; these codes are
        // only so every kind has one.
        case .endSmall: "DE0"
        case .endMedium: "DE1"
        case .endLarge: "DE2"
        }
    }

    public static func kind(forCode code: String) -> PipeKind? {
        PipeKind.allCases.first { self.code(for: $0) == code }
    }

    public static func parsePipeLine(_ line: String) throws(ImportError) -> PipeLine {
        let parts = line.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "_")
        guard parts.count == 3,
              let kind = kind(forCode: String(parts[0])),
              let index0 = Int(parts[1]), let index1 = Int(parts[2]),
              index0 >= 0, index1 >= 0
        else { throw .malformedPipeLine(line) }
        return PipeLine(kind: kind, index0: index0, index1: index1)
    }

    public static func parsePipeFile(_ contents: String) throws(ImportError) -> [PipeLine] {
        var lines: [PipeLine] = []
        for line in contents.split(whereSeparator: \.isNewline)
        where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append(try parsePipeLine(String(line)))
        }
        return lines
    }

    /// Extracts the six edge values from a name such as `Pipes_0-0-0-0-2-8`.
    public static func parseFolderName(_ name: String) throws(ImportError) -> [Int] {
        guard let underscore = name.firstIndex(of: "_") else { throw .malformedFolderName(name) }
        let values = name[name.index(after: underscore)...].split(separator: "-").map { Int($0) }
        guard values.count == HexGeometry.edgeCount, !values.contains(nil) else {
            throw .malformedFolderName(name)
        }
        return values.compactMap { $0 }
    }

    /// Every port count for which the pipes produce exactly `folderValues`.
    public static func compatiblePortCounts(
        for lines: [PipeLine],
        folderValues: [Int],
        candidates: ClosedRange<Int> = 1...16
    ) -> Set<Int> {
        Set(candidates.filter { count in
            let indices = lines.flatMap { [$0.index0, $0.index1] }
            guard indices.allSatisfy({ $0 < count * HexGeometry.edgeCount }) else { return false }
            let ports = indices.map { Port(index: $0, portsPerEdge: count) }
            return EdgeCode(portsPerEdge: count, occupied: ports).values == folderValues
        })
    }

    /// Builds a tile from legacy pipe lines. Placement rules are not applied,
    /// because the original editor enforced slightly different ones.
    public static func tile(from lines: [PipeLine], portsPerEdge: Int) -> Tile {
        Tile(
            portsPerEdge: portsPerEdge,
            uncheckedPipes: lines.map { line in
                Pipe(
                    line.kind,
                    a: Port(index: line.index0, portsPerEdge: portsPerEdge),
                    b: Port(index: line.index1, portsPerEdge: portsPerEdge)
                )
            }
        )
    }

    public static func pipeLine(for pipe: Pipe, portsPerEdge: Int) -> String {
        "\(code(for: pipe.kind))_\(pipe.a.index(portsPerEdge: portsPerEdge))_\(pipe.b.index(portsPerEdge: portsPerEdge))"
    }
}

/// A whole exported set, read from disk.
public struct LegacyTileSet: Sendable {
    public var name: String
    public var portsPerEdge: Int
    public var tiles: [Tile]

    /// Loads every tile under `url`, the folder of a single exported set.
    public static func load(from url: URL) throws -> LegacyTileSet {
        let files = FileManager.default
        func visibleContents(of folder: URL) throws -> [URL] {
            try files.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ).sorted { $0.lastPathComponent < $1.lastPathComponent }
        }

        var entries: [(lines: [LegacyFormat.PipeLine], folderValues: [Int])] = []
        for codeFolder in try visibleContents(of: url) where codeFolder.hasDirectoryPath {
            let folderValues = try LegacyFormat.parseFolderName(codeFolder.lastPathComponent)
            for tileFolder in try visibleContents(of: codeFolder) where tileFolder.hasDirectoryPath {
                for file in try visibleContents(of: tileFolder) where file.pathExtension == "txt" {
                    let contents = try String(contentsOf: file, encoding: .utf8)
                    entries.append((try LegacyFormat.parsePipeFile(contents), folderValues))
                }
            }
        }

        var counts = Set(1...16)
        for entry in entries {
            counts.formIntersection(
                LegacyFormat.compatiblePortCounts(for: entry.lines, folderValues: entry.folderValues)
            )
        }
        guard let portsPerEdge = counts.min() else {
            throw LegacyFormat.ImportError.cannotInferPortsPerEdge
        }

        return LegacyTileSet(
            name: url.lastPathComponent,
            portsPerEdge: portsPerEdge,
            tiles: entries.map { LegacyFormat.tile(from: $0.lines, portsPerEdge: portsPerEdge) }
        )
    }
}
