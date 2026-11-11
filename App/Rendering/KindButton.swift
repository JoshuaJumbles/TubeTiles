import SwiftUI
import TubeKit

extension PipeKind {
    /// A short name for buttons and lists.
    var shortTitle: String {
        switch self {
        case .bezier: "Curve"
        case .corner: "Corner"
        case .roomSmall: "Room S"
        case .roomMedium: "Room M"
        case .roomLarge: "Room L"
        case .endSmall: "End S"
        case .endMedium: "End M"
        case .endLarge: "End L"
        }
    }
}

/// A pipe kind shown as a miniature tile. Used to pick the kind to draw in
/// the editor, and to switch kinds on and off for a library.
struct KindButton: View {
    var kind: PipeKind
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Canvas { context, size in
                    let frame = TileFrame(fitting: size, padding: 3)
                    let style = TileStyle(portsPerEdge: 3)
                    let hex = TileRenderer.hexPath(in: frame)
                    context.fill(hex, with: .color(TilePalette.face))
                    var clipped = context
                    clipped.clip(to: hex)
                    let sample = kind.isDeadEnd
                        ? Pipe(kind, at: Port(edge: 3, slot: 1))
                        : Pipe(kind, a: Port(edge: 5, slot: 1), b: Port(edge: 1, slot: 1))
                    TileRenderer.draw(sample, style: style, in: frame, context: &clipped)
                    context.stroke(hex, with: .color(TilePalette.outline), lineWidth: 1)
                }
                .frame(height: 32)
                Text(kind.shortTitle)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.shortTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
