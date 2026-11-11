import Foundation
import TubeKit

/// Made-up libraries for previews and screenshots. Launch the app with
/// `-sampleLibrary YES` to use them in place of the saved ones; nothing they
/// hold is written to disk.
@MainActor
enum SampleData {
    static var isRequested: Bool {
        UserDefaults.standard.bool(forKey: "sampleLibrary")
    }

    static func library() -> LibraryModel {
        let model = LibraryModel(store: nil)
        let placeholder = model.currentID
        var generator = SplitMix(state: 20_261_110)

        // A general library: sparse tiles in sets, each base tile plus the
        // same ports joined differently and turned or flipped, so there are
        // groups of variants like a hand-built library has.
        let mixedKinds: [PipeKind] =
            Array(repeating: .bezier, count: 8) + Array(repeating: .corner, count: 3) + [.roomSmall, .roomMedium]
        let mixed = try? model.create(
            name: "Mixed", note: "A bit of everything.", portsPerEdge: 6, allowedKinds: Set(PipeKind.allCases)
        )
        for _ in 0..<14 {
            var base = Tile(portsPerEdge: 6)
            for _ in 0..<Int.random(in: 2...4, using: &generator) {
                base.addRandomPipe(kinds: mixedKinds, using: &generator)
            }
            guard base.pipes.count >= 2 else { continue }
            try? model.save(base, to: mixed?.id)
            for _ in 0..<Int.random(in: 0...3, using: &generator) {
                if let variant = rewired(base, kinds: mixedKinds, using: &generator) {
                    let placement = TileTransform.allCases.randomElement(using: &generator)!
                    try? model.save(copy(variant.transformed(by: placement)), to: mixed?.id)
                }
            }
        }
        for _ in 0..<4 {
            var tile = Tile(portsPerEdge: 6)
            tile.fillRandomly(kinds: mixedKinds, using: &generator)
            try? model.save(tile, to: mixed?.id)
        }

        // Libraries built to a look: one of curves only, one of corners only.
        // The curves library also keeps to the middle four ports of each
        // edge, which draws its pipes together.
        for (name, note, kinds, dead) in [
            ("Curves only", "Soft and looping. No corners, no rooms. Middle four ports.",
             Set<PipeKind>([.bezier, .endMedium]), Set<Int>([0])),
            ("Angular", "Straight runs and sharp corners.", Set<PipeKind>([.corner, .endSmall]), Set<Int>()),
        ] {
            let styled = try? model.create(
                name: name, note: note, portsPerEdge: 6, allowedKinds: kinds, deadSlots: dead
            )
            for _ in 0..<12 {
                var tile = Tile(portsPerEdge: 6)
                for _ in 0..<Int.random(in: 2...4, using: &generator) {
                    tile.addRandomPipe(
                        kinds: kinds.filter { !$0.isDeadEnd }, avoiding: styled?.deadPorts ?? [], using: &generator
                    )
                }
                if !tile.pipes.isEmpty { try? model.save(tile, to: styled?.id) }
            }
        }

        // A second port count.
        let small = try? model.create(name: "Four ports", note: "", portsPerEdge: 4, allowedKinds: Set(PipeKind.allCases))
        for _ in 0..<5 {
            var tile = Tile(portsPerEdge: 4)
            for _ in 0..<3 {
                tile.addRandomPipe(kinds: mixedKinds, using: &generator)
            }
            try? model.save(tile, to: small?.id)
        }

        if let mixed { model.select(mixed.id) }
        try? model.deleteLibrary(id: placeholder)
        return model
    }

    /// The same ports as `tile`, paired up in a different valid way.
    private static func rewired(_ tile: Tile, kinds: [PipeKind], using generator: inout SplitMix) -> Tile? {
        let ports = tile.occupiedPorts.sorted()
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
