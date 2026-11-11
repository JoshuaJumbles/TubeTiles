import SwiftUI
import TubeKit

/// Shows which edge patterns the library can offer a neighbour, and which it
/// cannot yet. A pattern no tile has is an edge the generator could never
/// continue from.
struct EdgeCoverageView: View {
    var library: TileLibrary

    @State private var isExpanded = false

    private static let covered = TilePalette.positive
    private static let missing = TilePalette.negative

    var body: some View {
        let patterns = EdgeCode.allPatterns(portsPerEdge: library.portsPerEdge)
        let counts = library.edgePatternCounts
        let coveredCount = patterns.filter { counts[$0] != nil }.count
        let busiest = max(1, counts.values.max() ?? 1)

        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Edge patterns")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.primary)
                        Text("\(coveredCount) of \(patterns.count) covered")
                            .font(.footnote)
                            .foregroundStyle(Color.secondary)
                    }
                    Spacer()
                    ProgressView(value: Double(coveredCount), total: Double(patterns.count))
                        .tint(Self.covered)
                        .frame(width: 90)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text("Each cell is one arrangement of pipes along an edge, with the number of tiles that have it. Empty cells are arrangements no tile can connect to yet.")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 6)], spacing: 6) {
                    ForEach(patterns, id: \.self) { pattern in
                        cell(pattern: pattern, count: counts[pattern] ?? 0, busiest: busiest)
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(TilePalette.face))
    }

    private func cell(pattern: Int, count: Int, busiest: Int) -> some View {
        let width = library.portsPerEdge
        let strength = count == 0 ? 0 : 0.15 + 0.45 * Double(count) / Double(busiest)
        return VStack(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(0..<width, id: \.self) { slot in
                    let isUsed = pattern & (1 << (width - 1 - slot)) != 0
                    Circle()
                        .fill(isUsed ? Color.primary : Color.clear)
                        .overlay(Circle().stroke(Color.primary.opacity(isUsed ? 1 : 0.35), lineWidth: 1))
                        .frame(width: 5, height: 5)
                }
            }
            Text(count == 0 ? "none" : "\(count)")
                .font(.caption2.weight(count == 0 ? .regular : .semibold))
                .foregroundStyle(count == 0 ? Self.missing : Color.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Self.covered.opacity(strength)))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(count == 0 ? Self.missing.opacity(0.5) : .clear, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pattern \(pattern), \(count == 0 ? "no tiles" : "\(count) tiles")")
    }
}
