import Foundation
import Testing
@testable import TubeKit

private func tiles(count: Int, seed: UInt64, portsPerEdge: Int = 5) -> [Tile] {
    var random = SeededGenerator(seed: seed)
    var result: [Tile] = []
    while result.count < count {
        var tile = Tile(portsPerEdge: portsPerEdge)
        tile.fillRandomly(kinds: [.bezier, .corner], avoiding: [], using: &random)
        if !tile.pipes.isEmpty { result.append(tile) }
    }
    return result
}

@Suite struct LibraryMergeTests {
    @Test func mergingAddsOnlyWhatIsNew() {
        let shared = tiles(count: 6, seed: 1)
        let fresh = tiles(count: 5, seed: 2)
        var mine = TileLibrary(name: "Mine", portsPerEdge: 5)
        shared.forEach { mine.save($0) }

        var theirs = TileLibrary(name: "Theirs", portsPerEdge: 5, allowedKinds: [.bezier])
        // The shared tiles again, but turned and flipped and with identities
        // of their own, as they would be coming from another device.
        for (index, tile) in shared.enumerated() {
            let way = TileTransform.allCases[index % TileTransform.allCases.count]
            theirs.save(Tile(portsPerEdge: 5, uncheckedPipes: tile.transformed(by: way).pipes))
        }
        fresh.forEach { theirs.save($0) }

        let result = mine.merge(theirs)
        #expect(result.added == 5)
        #expect(result.skipped == 6)
        #expect(mine.tiles.count == 11)
        // Each added tile is a copy of its own, not the other library's.
        #expect(Set(mine.tiles.map(\.id)).isDisjoint(with: theirs.tiles.suffix(5).map(\.id)))
        // The rules stay this library's.
        #expect(mine.allowedKinds == Set(PipeKind.allCases))
        #expect(mine.name == "Mine")

        // Merging the same library again changes nothing.
        let again = mine.merge(theirs)
        #expect(again.added == 0)
        #expect(again.skipped == 11)
        #expect(mine.tiles.count == 11)
    }

    @Test func mergingNeedsTheSamePortCount() {
        var mine = TileLibrary(name: "Mine", portsPerEdge: 5)
        var other = TileLibrary(name: "Other", portsPerEdge: 4)
        tiles(count: 3, seed: 4, portsPerEdge: 4).forEach { other.save($0) }
        let result = mine.merge(other)
        #expect(result.added == 0)
        #expect(result.skipped == 3)
        #expect(mine.tiles.isEmpty)
    }

    @Test func mergedTilesTakeOnThisLibrarysThickness() {
        let thick = PipeGauge(width: 0.9, wall: 0.3)
        var mine = TileLibrary(name: "Mine", portsPerEdge: 5, gauge: thick)
        var theirs = TileLibrary(name: "Theirs", portsPerEdge: 5)
        tiles(count: 4, seed: 6).forEach { theirs.save($0) }
        mine.merge(theirs)
        #expect(mine.tiles.count == 4)
        #expect(mine.tiles.allSatisfy { $0.gauge == thick })
    }

    @Test func anAdoptedLibraryIsAWholeNewCopy() throws {
        var theirs = TileLibrary(
            name: "Theirs", note: "Curvy", portsPerEdge: 5, allowedKinds: [.bezier, .roomSmall],
            deadSlots: [0], gauge: PipeGauge(width: 0.5, wall: 0.1)
        )
        tiles(count: 4, seed: 9).forEach { theirs.save($0) }

        // What travels between devices is the library as a file.
        let received = try JSONDecoder().decode(TileLibrary.self, from: JSONEncoder().encode(theirs))
        #expect(received == theirs)

        let adopted = received.adopted(named: "Theirs 2")
        #expect(adopted.id != theirs.id)
        #expect(adopted.name == "Theirs 2")
        #expect(adopted.note == "Curvy")
        #expect(adopted.allowedKinds == theirs.allowedKinds)
        #expect(adopted.deadPorts == theirs.deadPorts)
        #expect(adopted.gauge == theirs.gauge)
        #expect(adopted.tiles.count == 4)
        #expect(Set(adopted.tiles.map(\.id)).isDisjoint(with: theirs.tiles.map(\.id)))
        #expect(zip(adopted.tiles, theirs.tiles).allSatisfy { $0.pipes == $1.pipes })
    }
}
