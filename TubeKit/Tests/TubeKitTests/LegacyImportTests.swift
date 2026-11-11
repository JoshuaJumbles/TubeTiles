import Foundation
import Testing
@testable import TubeKit

@Suite struct LegacyImportTests {
    @Test func parsesPipeLines() throws {
        #expect(try LegacyFormat.parsePipeLine("BZR_23_26") == .init(kind: .bezier, index0: 23, index1: 26))
        #expect(try LegacyFormat.parsePipeLine("CR2_0_17\n") == .init(kind: .roomLarge, index0: 0, index1: 17))
        #expect(throws: LegacyFormat.ImportError.malformedPipeLine("XYZ_1_2")) {
            try LegacyFormat.parsePipeLine("XYZ_1_2")
        }
        #expect(try LegacyFormat.parsePipeFile("CNR_1_8\n\nBZR_3_20\n").count == 2)
    }

    @Test func parsesFolderNames() throws {
        #expect(try LegacyFormat.parseFolderName("Pipes_0-0-0-0-2-8") == [0, 0, 0, 0, 2, 8])
        #expect(throws: LegacyFormat.ImportError.self) {
            try LegacyFormat.parseFolderName("Pipes_0-0-0")
        }
    }

    /// A real tile from the original editor: one bezier saved as `BZR_23_26`
    /// in a folder named `Pipes_0-0-0-0-2-8`. Only five ports per edge
    /// reproduces that folder name.
    @Test func infersPortsPerEdgeFromTheFolderCode() throws {
        let lines = [try LegacyFormat.parsePipeLine("BZR_23_26")]
        let counts = LegacyFormat.compatiblePortCounts(for: lines, folderValues: [0, 0, 0, 0, 2, 8])
        #expect(counts == [5])

        let tile = LegacyFormat.tile(from: lines, portsPerEdge: 5)
        #expect(tile.edgeCode.description == "0-0-0-0-2-8")
        #expect(tile.pipes == [Pipe(.bezier, a: Port(edge: 4, slot: 3), b: Port(edge: 5, slot: 1))])
        #expect(LegacyFormat.pipeLine(for: tile.pipes[0], portsPerEdge: 5) == "BZR_23_26")
    }

    @Test func loadsASetFromDisk() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TubeKitTests-\(UUID().uuidString)")
        let set = root.appendingPathComponent("SampleSet")
        defer { try? FileManager.default.removeItem(at: root) }

        func write(_ lines: String, code: String, index: Int) throws {
            let folder = set.appendingPathComponent("Pipes_\(code)/pipe\(index)_BZR-1")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try lines.write(
                to: folder.appendingPathComponent("SampleSet_\(index).txt"),
                atomically: true, encoding: .utf8
            )
        }
        try write("BZR_23_26\n", code: "0-0-0-0-2-8", index: 0)
        try write("CNR_0_19\nBZR_7_12\n", code: "16-4-4-1-0-0", index: 1)

        let loaded = try LegacyTileSet.load(from: set)
        #expect(loaded.name == "SampleSet")
        #expect(loaded.portsPerEdge == 5)
        #expect(loaded.tiles.count == 2)
        #expect(loaded.tiles.map(\.edgeCode.description).sorted() == ["0-0-0-0-2-8", "16-4-4-1-0-0"])
    }

    /// Optional check against real exports. Point `TUBETILES_LEGACY_EXPORT`
    /// at the old editor's `Export` folder (or a single set) to run it.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TUBETILES_LEGACY_EXPORT"] != nil))
    func realExportsImportCleanly() throws {
        let path = ProcessInfo.processInfo.environment["TUBETILES_LEGACY_EXPORT"]!
        let root = URL(fileURLWithPath: path, isDirectory: true)
        let children = try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ).filter(\.hasDirectoryPath)
        let isSingleSet = children.contains { $0.lastPathComponent.hasPrefix("Pipes_") }
        let sets = isSingleSet ? [root] : children

        var total = 0
        defer { #expect(total > 0) }
        for url in sets.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let set = try LegacyTileSet.load(from: url)
            total += set.tiles.count
            // The earliest sets were saved as images only, with no pipe list.
            guard !set.tiles.isEmpty else {
                print("\(set.name): no pipe lists, skipped")
                continue
            }
            let broken = set.tiles.filter { tile in
                tile.pipes.contains {
                    PlacementRules.shapeError(for: $0, portsPerEdge: set.portsPerEdge) != nil
                } || tile.occupiedPorts.count != tile.pipes.count * 2
            }
            let overlapping = set.tiles.filter { CoverageMap(tile: $0).hasViolation }
            print("\(set.name): \(set.tiles.count) tiles, \(set.portsPerEdge) ports per edge, \(broken.count) outside shape rules, \(overlapping.count) outside overlap rule")
        }
    }
}
