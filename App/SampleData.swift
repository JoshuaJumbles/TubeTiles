import Foundation
import TubeKit

/// A made-up library for previews and screenshots. Launch the app with
/// `-sampleLibrary YES` to use it in place of the saved one; nothing it holds
/// is written to disk.
@MainActor
enum SampleData {
    static var isRequested: Bool {
        UserDefaults.standard.bool(forKey: "sampleLibrary")
    }

    static func library() -> LibraryModel {
        let model = LibraryModel(store: nil)
        var generator = SplitMix(state: 20_261_110)

        // Sparse tiles in sets: each base tile, plus the same ports joined
        // differently, plus a turned or flipped copy. That gives groups of
        // variants like a hand-built library has.
        for _ in 0..<14 {
            var base = Tile(portsPerEdge: 6)
            let pipeCount = Int.random(in: 2...4, using: &generator)
            for _ in 0..<pipeCount {
                base.addRandomPipe(kinds: kinds, using: &generator)
            }
            guard base.pipes.count >= 2 else { continue }
            try? model.save(base)

            for _ in 0..<Int.random(in: 0...3, using: &generator) {
                if let variant = rewired(base, using: &generator) {
                    let placement = TileTransform.allCases.randomElement(using: &generator)!
                    try? model.save(copy(variant.transformed(by: placement)))
                }
            }
        }

        // A few dense tiles, and a second port count.
        for _ in 0..<4 {
            var tile = Tile(portsPerEdge: 6)
            tile.fillRandomly(kinds: kinds, using: &generator)
            try? model.save(tile)
        }
        for _ in 0..<5 {
            var tile = Tile(portsPerEdge: 4)
            for _ in 0..<3 {
                tile.addRandomPipe(kinds: kinds, using: &generator)
            }
            try? model.save(tile)
        }
        return model
    }

    private static let kinds: [PipeKind] =
        Array(repeating: .bezier, count: 8) + Array(repeating: .corner, count: 3) + [.roomSmall, .roomMedium]

    /// The same ports as `tile`, paired up in a different valid way.
    private static func rewired(_ tile: Tile, using generator: inout SplitMix) -> Tile? {
        let ports = Array(tile.occupiedPorts)
        for _ in 0..<20 {
            var next = Tile(portsPerEdge: tile.portsPerEdge)
            var remaining = ports.shuffled(using: &generator)
            var fits = true
            while remaining.count >= 2, fits {
                let a = remaining.removeLast()
                let b = remaining.removeLast()
                let options = kinds.shuffled(using: &generator)
                fits = options.contains { (try? next.add(Pipe($0, a: a, b: b))) != nil }
            }
            if fits, next.pairing != tile.pairing { return next }
        }
        return nil
    }

    private static func copy(_ tile: Tile) -> Tile {
        var copy = tile
        copy.id = UUID()
        return copy
    }

    private struct SplitMix: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }
}
