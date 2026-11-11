import Foundation
import Testing
@testable import TubeKit

/// A deterministic spread of tiles: for each seed, pair off free ports with
/// whatever pipe kind the rules allow.
private func sampleTile(portsPerEdge: Int, seed: Int) -> Tile {
    var state = UInt64(truncatingIfNeeded: seed &* 2654435761 &+ 12345)
    func next(_ bound: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 33) % UInt64(bound))
    }
    var tile = Tile(portsPerEdge: portsPerEdge)
    for _ in 0..<(portsPerEdge * 6) {
        let free = tile.freePorts
        guard free.count >= 2 else { break }
        let a = free[next(free.count)]
        let b = free[next(free.count)]
        let kind = PipeKind.allCases[next(PipeKind.allCases.count)]
        try? tile.add(Pipe(kind, a: a, b: b))
    }
    return tile
}

@Suite struct PipeTests {
    @Test func pipesAreUndirected() {
        let a = Port(edge: 4, slot: 1)
        let b = Port(edge: 0, slot: 2)
        #expect(Pipe(.bezier, a: a, b: b) == Pipe(.bezier, a: b, b: a))
        #expect(Pipe(.bezier, a: a, b: b).a == b)
        #expect(Pipe(.bezier, a: a, b: b).otherEnd(from: a) == b)
        #expect(Pipe(.bezier, a: a, b: b).otherEnd(from: Port(edge: 2, slot: 0)) == nil)
    }
}

@Suite struct PlacementRuleTests {
    let portsPerEdge = 6

    private func error(_ kind: PipeKind, _ a: (Int, Int), _ b: (Int, Int)) -> PlacementError? {
        PlacementRules.shapeError(
            for: Pipe(kind, a: Port(edge: a.0, slot: a.1), b: Port(edge: b.0, slot: b.1)),
            portsPerEdge: portsPerEdge
        )
    }

    @Test func bezierAllowsWideUTurnsOnly() {
        #expect(error(.bezier, (0, 0), (0, 1)) == .tightUTurn)
        #expect(error(.bezier, (0, 0), (0, 2)) == nil)
        #expect(error(.bezier, (0, 0), (3, 0)) == nil)
    }

    @Test(arguments: [PipeKind.corner, .roomSmall, .roomMedium, .roomLarge])
    func cornersAndRoomsTurnOrRunStraightAcross(kind: PipeKind) {
        #expect(error(kind, (0, 0), (0, 3)) == .needsTwoEdges)
        #expect(error(kind, (0, 1), (3, 1)) == .mustRunStraightAcross)
        #expect(error(kind, (0, 1), (3, 4)) == nil)
        #expect(error(kind, (0, 1), (2, 5)) == nil)
    }

    @Test func rejectsBadPorts() {
        #expect(error(.bezier, (0, 0), (0, 0)) == .samePort)
        #expect(error(.bezier, (0, 0), (0, 6)) == .portOutOfRange(Port(edge: 0, slot: 6)))
        #expect(error(.bezier, (6, 0), (0, 0)) == .portOutOfRange(Port(edge: 6, slot: 0)))
    }

    @Test func aPortTakesOnePipe() throws {
        var tile = Tile(portsPerEdge: portsPerEdge)
        let shared = Port(edge: 1, slot: 2)
        try tile.add(Pipe(.bezier, a: shared, b: Port(edge: 4, slot: 0)))
        #expect(throws: PlacementError.portOccupied(shared)) {
            try tile.add(Pipe(.corner, a: Port(edge: 2, slot: 2), b: shared))
        }
        #expect(tile.pipes.count == 1)
        #expect(tile.removePipe(at: shared) != nil)
        #expect(tile.pipes.isEmpty)
    }
}

@Suite struct EdgeCodeTests {
    @Test func slotZeroIsTheHighBit() throws {
        let tile = try Tile(portsPerEdge: 4, pipes: [
            Pipe(.bezier, a: Port(edge: 0, slot: 0), b: Port(edge: 2, slot: 3)),
        ])
        #expect(tile.edgeCode.values == [8, 0, 1, 0, 0, 0])
        #expect(tile.edgeCode.description == "8-0-1-0-0-0")
        #expect(EdgeCode("8-0-1-0-0-0", portsPerEdge: 4) == tile.edgeCode)
        #expect(EdgeCode("8-0-1", portsPerEdge: 4) == nil)
    }

    @Test func reversingBits() {
        #expect(EdgeCode.reversed(0b0011, width: 4) == 0b1100)
        #expect(EdgeCode.reversed(0b00001, width: 5) == 0b10000)
        #expect(EdgeCode.reversed(0, width: 6) == 0)
    }

    @Test func occupiedPortsRoundTrip() {
        for seed in 0..<20 {
            let tile = sampleTile(portsPerEdge: 5, seed: seed)
            #expect(Set(tile.edgeCode.occupiedPorts) == tile.occupiedPorts)
        }
    }

    /// Transforming a tile and reading its code must match transforming the
    /// code directly, for every placement.
    @Test(arguments: [2, 4, 5, 6])
    func codeTransformAgreesWithTileTransform(portsPerEdge: Int) {
        for seed in 0..<25 {
            let tile = sampleTile(portsPerEdge: portsPerEdge, seed: seed)
            #expect(!tile.pipes.isEmpty)
            for transform in TileTransform.allCases {
                #expect(
                    tile.transformed(by: transform).edgeCode
                        == tile.edgeCode.transformed(by: transform)
                )
            }
        }
    }

    /// A tile always fits against its own reflection through a shared edge.
    @Test func neighbourValueMatchesTheTouchingPorts() {
        for seed in 0..<25 {
            let tile = sampleTile(portsPerEdge: 6, seed: seed)
            let touching = tile.occupiedPorts.map { $0.neighbourPort(portsPerEdge: 6) }
            let neighbour = EdgeCode(portsPerEdge: 6, occupied: touching)
            for edge in 0..<6 {
                #expect(neighbour.values[(edge + 3) % 6] == tile.edgeCode.requiredNeighbourValue(forEdge: edge))
            }
        }
    }
}

@Suite struct TileTests {
    @Test func pairingIsSymmetricAndSurvivesTransforms() {
        for seed in 0..<25 {
            let tile = sampleTile(portsPerEdge: 6, seed: seed)
            for (from, to) in tile.pairing {
                #expect(tile.connection(from: to) == from)
            }
            for transform in TileTransform.allCases {
                let moved = tile.transformed(by: transform)
                #expect(moved.id == tile.id)
                for (from, to) in tile.pairing {
                    let movedFrom = transform.apply(to: from, portsPerEdge: 6)
                    let movedTo = transform.apply(to: to, portsPerEdge: 6)
                    #expect(moved.connection(from: movedFrom) == movedTo)
                }
                #expect(moved.transformed(by: transform.inverse) == tile)
            }
        }
    }

    @Test func encodesAndDecodes() throws {
        let tile = sampleTile(portsPerEdge: 6, seed: 7)
        let data = try JSONEncoder().encode(tile)
        #expect(try JSONDecoder().decode(Tile.self, from: data) == tile)
    }

    @Test func decodingNormalisesPipeOrder() throws {
        let json = #"{"kind":"bezier","a":{"edge":4,"slot":1},"b":{"edge":0,"slot":2}}"#
        let pipe = try JSONDecoder().decode(Pipe.self, from: Data(json.utf8))
        #expect(pipe.a == Port(edge: 0, slot: 2))
    }
}
