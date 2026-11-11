import SwiftUI
import TubeKit

/// The interactive hex: draws the tile being edited and turns touches into
/// port taps and port-to-port drags.
struct TileCanvas: View {
    var model: EditorModel

    @State private var touchStart: Port??
    @State private var isDragging = false

    private static let tileFace = TilePalette.face
    private static let outline = TilePalette.outline
    private static let good = TilePalette.positive

    var body: some View {
        GeometryReader { proxy in
            let frame = TileFrame(fitting: proxy.size, padding: 30)
            let tile = model.tile
            let style = model.style
            let selectedPort = model.selectedPort
            let selectedPipe = model.selectedPipe
            let validTargets = model.validTargets
            let ghost = model.ghost

            Canvas { context, _ in
                let hex = TileRenderer.hexPath(in: frame)
                context.fill(hex, with: .color(Self.tileFace))
                TileRenderer.draw(tile, in: frame, context: &context)

                var clipped = context
                clipped.clip(to: hex)
                if let selectedPipe {
                    TileRenderer.draw(selectedPipe, style: style, in: frame, context: &clipped, palette: .selected)
                }
                if let ghost {
                    clipped.opacity = 0.6
                    TileRenderer.draw(
                        ghost.pipe, style: style, in: frame, context: &clipped,
                        palette: ghost.error == nil ? .standard : .rejected
                    )
                    clipped.opacity = 0.75
                    let cell = CoverageMap.sampleSize * frame.scale
                    for point in ghost.conflicts {
                        let center = frame.point(point)
                        clipped.fill(
                            Path(CGRect(x: center.x - cell / 2, y: center.y - cell / 2, width: cell, height: cell)),
                            with: .color(TilePalette.negative)
                        )
                    }
                }

                context.stroke(hex, with: .color(Self.outline), style: StrokeStyle(lineWidth: 2, lineJoin: .round))

                let occupied = tile.occupiedPorts
                for edge in 0..<HexGeometry.edgeCount {
                    for slot in 0..<tile.portsPerEdge {
                        let port = Port(edge: edge, slot: slot)
                        guard !occupied.contains(port) else { continue }
                        let center = frame.point(HexGeometry.position(of: port, portsPerEdge: tile.portsPerEdge))
                        func dot(_ radius: CGFloat) -> Path {
                            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                        }
                        if port == selectedPort {
                            context.fill(dot(7), with: .color(.accentColor))
                            context.stroke(dot(12), with: .color(.accentColor), lineWidth: 2)
                        } else if selectedPort != nil {
                            if validTargets.contains(port) {
                                context.fill(dot(6), with: .color(Self.good))
                            } else {
                                context.fill(dot(2.5), with: .color(Self.outline.opacity(0.35)))
                            }
                        } else {
                            context.fill(dot(3.5), with: .color(Self.outline))
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if touchStart == nil {
                            touchStart = .some(nearestPort(to: value.startLocation, in: frame))
                        }
                        let distance = hypot(value.translation.width, value.translation.height)
                        if distance > 12 { isDragging = true }
                        if isDragging, let start = touchStart {
                            model.drag(from: start, to: nearestPort(to: value.location, in: frame))
                        }
                    }
                    .onEnded { _ in
                        if isDragging {
                            model.endDrag()
                        } else if let start = touchStart {
                            model.tap(start)
                        }
                        touchStart = nil
                        isDragging = false
                    }
            )
            .accessibilityLabel("Tile canvas")
        }
    }

    /// The port closest to a touch, if the touch is reasonably near one.
    private func nearestPort(to location: CGPoint, in frame: TileFrame) -> Port? {
        let point = frame.tilePoint(location)
        let count = model.tile.portsPerEdge
        var best: (port: Port, distance: Double)?
        for edge in 0..<HexGeometry.edgeCount {
            for slot in 0..<count {
                let port = Port(edge: edge, slot: slot)
                let distance = HexGeometry.position(of: port, portsPerEdge: count).distance(to: point)
                if distance < (best?.distance ?? 0.3) {
                    best = (port, distance)
                }
            }
        }
        return best?.port
    }
}
