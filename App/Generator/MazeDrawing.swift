import CoreTransferable
import Foundation
import TubeKit
import UniformTypeIdentifiers

/// A maze ready to be shared as an SVG file. The drawing is only produced
/// when something actually asks for it.
struct MazeDrawing: Transferable {
    var maze: Maze
    var options: MazeSVG.Options

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .svg) { drawing in
            Data(MazeSVG.render(drawing.maze, options: drawing.options).utf8)
        }
        .suggestedFileName("TubeTiles maze.svg")
    }
}
