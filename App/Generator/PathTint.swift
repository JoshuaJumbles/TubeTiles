import SwiftUI
import TubeKit

/// The colour given to each path, shared by the screen and the exported
/// drawing so the two match.
enum PathTint {
    /// Red, green and blue from 0 to 1. A path keeps its colour as long as
    /// its first pipe stays put, so merging elsewhere does not reshuffle the
    /// rest.
    static func components(for path: MazePath) -> (red: Double, green: Double, blue: Double) {
        guard let first = path.steps.first else { return (1, 1, 1) }
        let seed = first.coord.q * 73 + first.coord.r * 151 + first.pipe.a.edge * 31 + first.pipe.a.slot * 17
        var hue = (Double(seed) * 0.618034).truncatingRemainder(dividingBy: 1)
        if hue < 0 { hue += 1 }
        return rgb(hue: hue, saturation: 0.45, brightness: 0.97)
    }

    /// Kept loops are drawn plain.
    static func palette(for path: MazePath, isKept: Bool) -> TilePalette {
        guard !isKept else { return .standard }
        let color = components(for: path)
        return TilePalette(tube: Color(red: color.red, green: color.green, blue: color.blue))
    }

    static func hex(for path: MazePath) -> String {
        let color = components(for: path)
        func byte(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(color.red), byte(color.green), byte(color.blue))
    }

    private static func rgb(hue: Double, saturation: Double, brightness: Double) -> (red: Double, green: Double, blue: Double) {
        let sector = hue * 6
        let chroma = brightness * saturation
        let x = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let m = brightness - chroma
        let (r, g, b): (Double, Double, Double) = switch Int(sector) % 6 {
        case 0: (chroma, x, 0)
        case 1: (x, chroma, 0)
        case 2: (0, chroma, x)
        case 3: (0, x, chroma)
        case 4: (x, 0, chroma)
        default: (chroma, 0, x)
        }
        return (r + m, g + m, b + m)
    }
}
