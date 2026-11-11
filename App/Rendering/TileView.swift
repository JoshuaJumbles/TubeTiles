import SwiftUI
import TubeKit

/// A read-only picture of a tile, at whatever size it is given.
struct TileView: View {
    var tile: Tile
    var outlineWidth: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            let frame = TileFrame(fitting: size, padding: outlineWidth)
            let hex = TileRenderer.hexPath(in: frame)
            context.fill(hex, with: .color(TilePalette.face))
            TileRenderer.draw(tile, in: frame, context: &context)
            context.stroke(hex, with: .color(TilePalette.outline), style: StrokeStyle(lineWidth: outlineWidth, lineJoin: .round))
        }
        .aspectRatio(1 / HexGeometry.inradius, contentMode: .fit)
        .accessibilityLabel("Tile \(tile.edgeCode.description)")
    }
}
