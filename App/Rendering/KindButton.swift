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

/// A pipe kind drawn as a miniature tile.
struct KindIcon: View {
    var kind: PipeKind

    var body: some View {
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
    }
}

/// One choice in a grid of tools or kinds: a picture, a short title, and a
/// highlight when it is the one in use.
struct ToolCell<Icon: View>: View {
    var title: String
    var isSelected: Bool
    var action: () -> Void
    @ViewBuilder var icon: () -> Icon

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                icon()
                    .frame(height: 32)
                Text(title)
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
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A pipe kind as a choice. Used to pick the kind to draw in the editor,
/// and to switch kinds on and off for a library.
struct KindButton: View {
    var kind: PipeKind
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        ToolCell(title: kind.shortTitle, isSelected: isSelected, action: action) {
            KindIcon(kind: kind)
        }
    }
}
