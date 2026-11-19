import SwiftUI
import TubeKit

extension TileShape {
    /// The shape's name, for a choice of shapes.
    var title: String {
        switch self {
        case .hexagon: "Hexagon"
        case .square: "Square"
        case .cairo: "Cairo"
        case .octagon: "Octagon"
        case .triangle: "Triangle"
        }
    }

    /// A plain picture of the shape, for where its name will not fit.
    var symbolName: String {
        switch self {
        case .hexagon: "hexagon"
        case .square: "square"
        case .cairo: "pentagon"
        case .octagon: "octagon"
        case .triangle: "triangle"
        }
    }

    /// Several of the shape, as a heading or in a summary.
    var pluralTitle: String {
        switch self {
        case .hexagon: "Hexagons"
        case .square: "Squares"
        case .cairo: "Cairo pentagons"
        case .octagon: "Octagons"
        case .triangle: "Triangles"
        }
    }

    /// What a library of this shape holds, as in "square tiles".
    var tilesTitle: String {
        switch self {
        case .hexagon: "hexagon tiles"
        case .square: "square tiles"
        case .cairo: "Cairo tiles"
        case .octagon: "octagon tiles"
        case .triangle: "triangle tiles"
        }
    }
}

extension Tiling {
    /// The shapes the tiling is made of, as in "Octagons and squares".
    var shapesTitle: String {
        let names = shapes.map(\.pluralTitle)
        let rest = names.dropFirst().map { $0.lowercased() }
        return ListFormatter.localizedString(byJoining: [names[0]] + rest)
    }

    /// The tiling's name, for choosing between the ways a library can be
    /// laid. Most are told apart by their shapes; two share theirs and are
    /// named for how the shapes are arranged.
    var title: String {
        switch self {
        case .elongatedTriangular: "Squares and triangles in rows"
        case .snubSquare: "Squares and triangles in pinwheels"
        case .hexagonal, .square, .cairo, .truncatedSquare, .trihexagonal, .rhombitrihexagonal: shapesTitle
        }
    }

    /// One tiling for each set of shapes a library can be made of.
    static var librarySets: [Tiling] {
        var seen: [[TileShape]] = []
        return allCases.filter { tiling in
            guard !seen.contains(tiling.shapes) else { return false }
            seen.append(tiling.shapes)
            return true
        }
    }
}

extension TileLibrary {
    /// What the library holds, as in "square tiles" or "octagon and square
    /// tiles".
    var tilesTitle: String {
        guard shapes.count > 1 else { return shapes[0].tilesTitle }
        return ListFormatter.localizedString(byJoining: shapes.map { $0.title.lowercased() }) + " tiles"
    }
}

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
            let hex = TileRenderer.outline(of: style.shape, in: frame)
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

/// The button that shows the tool in use and opens the choice of tools. It
/// sits in the bottom right corner of a canvas, within reach of a thumb.
struct ToolBadge<Icon: View>: View {
    var title: String
    var tint: Color = .accentColor
    @ViewBuilder var icon: () -> Icon

    var body: some View {
        VStack(spacing: 2) {
            icon()
                .frame(width: 44, height: 34)
            HStack(spacing: 3) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                Image(systemName: "chevron.up")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(Color.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12).fill(TilePalette.face))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint, lineWidth: 2))
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

extension String {
    /// The same text with its first letter in upper case.
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
