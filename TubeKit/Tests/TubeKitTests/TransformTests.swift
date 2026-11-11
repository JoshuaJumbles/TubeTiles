import Testing
@testable import TubeKit

private let portCounts = [1, 2, 4, 5, 6]

private func allPorts(_ portsPerEdge: Int) -> [Port] {
    (0..<6).flatMap { edge in (0..<portsPerEdge).map { Port(edge: edge, slot: $0) } }
}

private func isClose(_ a: Point, _ b: Point) -> Bool {
    a.distance(to: b) < 1e-9
}

@Suite struct GeometryTests {
    @Test func topEdgeIsFlatAndRunsLeftToRight() {
        let start = HexGeometry.corner(0)
        let end = HexGeometry.corner(1)
        #expect(abs(start.y - end.y) < 1e-12)
        #expect(start.x < end.x)
        #expect(start.y < 0)
    }

    @Test func inwardDirectionPointsAtCentre() {
        for edge in 0..<6 {
            let middle = (HexGeometry.corner(edge) + HexGeometry.corner(edge + 1)) * 0.5
            let stepped = middle + HexGeometry.inwardDirection(edge: edge) * HexGeometry.inradius
            #expect(isClose(stepped, .zero))
        }
    }

    @Test(arguments: portCounts)
    func neighbourPortsTouch(portsPerEdge: Int) {
        // Two tiles sharing an edge are a reflection of each other through
        // the middle of that edge.
        for port in allPorts(portsPerEdge) {
            let middle = (HexGeometry.corner(port.edge) + HexGeometry.corner(port.edge + 1)) * 0.5
            let neighbourCentre = middle * 2
            let mine = HexGeometry.position(of: port, portsPerEdge: portsPerEdge)
            let theirs = neighbourCentre + HexGeometry.position(
                of: port.neighbourPort(portsPerEdge: portsPerEdge), portsPerEdge: portsPerEdge
            )
            #expect(isClose(mine, theirs))
        }
    }

    @Test func facingPortsAreStraightAcross() {
        let port = Port(edge: 0, slot: 1)
        let across = Port(edge: 3, slot: 4)
        #expect(port.faces(across, portsPerEdge: 6))
        #expect(!port.faces(Port(edge: 3, slot: 1), portsPerEdge: 6))
        let a = HexGeometry.position(of: port, portsPerEdge: 6)
        let b = HexGeometry.position(of: across, portsPerEdge: 6)
        #expect(abs(a.x - b.x) < 1e-12)
    }
}

@Suite struct TransformTests {
    @Test func thereAreTwelveDistinctTransforms() {
        #expect(Set(TileTransform.allCases).count == 12)
    }

    @Test func turnsAreNormalised() {
        #expect(TileTransform(turns: -1) == TileTransform(turns: 5))
        #expect(TileTransform(turns: 13, mirrored: true) == TileTransform(turns: 1, mirrored: true))
    }

    /// The property the original generator got wrong: moving a port by index
    /// must land exactly where moving its drawn position lands.
    @Test(arguments: portCounts)
    func portIndexTransformMatchesGeometry(portsPerEdge: Int) {
        for transform in TileTransform.allCases {
            for port in allPorts(portsPerEdge) {
                let viaIndex = HexGeometry.position(
                    of: transform.apply(to: port, portsPerEdge: portsPerEdge),
                    portsPerEdge: portsPerEdge
                )
                let viaGeometry = transform.apply(
                    to: HexGeometry.position(of: port, portsPerEdge: portsPerEdge)
                )
                #expect(isClose(viaIndex, viaGeometry), "\(transform) \(port)")
            }
        }
    }

    @Test func mirrorSwapsSideEdgesAcrossTheVerticalAxis() {
        let mirror = TileTransform(mirrored: true)
        let moved = (0..<6).map { mirror.apply(to: Port(edge: $0, slot: 0), portsPerEdge: 3).edge }
        #expect(moved == [0, 5, 4, 3, 2, 1])
        #expect(mirror.apply(to: Port(edge: 1, slot: 0), portsPerEdge: 3).slot == 2)
    }

    @Test func compositionMatchesApplyingInSequence() {
        let portsPerEdge = 4
        for first in TileTransform.allCases {
            for second in TileTransform.allCases {
                let combined = first.then(second)
                for port in allPorts(portsPerEdge) {
                    let stepwise = second.apply(
                        to: first.apply(to: port, portsPerEdge: portsPerEdge),
                        portsPerEdge: portsPerEdge
                    )
                    #expect(combined.apply(to: port, portsPerEdge: portsPerEdge) == stepwise)
                }
            }
        }
    }

    @Test func inverseUndoesTheTransform() {
        for transform in TileTransform.allCases {
            #expect(transform.then(transform.inverse) == .identity)
            #expect(transform.inverse.then(transform) == .identity)
        }
    }
}
