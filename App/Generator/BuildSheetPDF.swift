import TubeKit
import UIKit

/// Draws a maze's build sheet as a PDF on US Letter pages: a map of which
/// tile goes where, the list of tiles, and each tile as a stencil at its
/// real size.
@MainActor
enum BuildSheetPDF {
    struct Options: Equatable {
        /// A tile's size from one flat side to the opposite one, in inches.
        var tileInches = 3.0
        /// Whether a tile flipped over counts as the same tile.
        var flippedIsSame = false

        /// The largest tile that still fits across a page.
        static let sizeRange = 1.0...6.25
    }

    static let pageSize = CGSize(width: 612, height: 792)
    private static let margin: CGFloat = 36
    private static let headerHeight: CGFloat = 30
    private static let ink = UIColor.black
    private static let faint = UIColor(white: 0.62, alpha: 1)

    /// Where the drawing goes on a page, below the header.
    private static var body: CGRect {
        CGRect(
            x: margin, y: margin + headerHeight,
            width: pageSize.width - margin * 2, height: pageSize.height - margin * 2 - headerHeight
        )
    }

    /// A tile's place on the page: its centre, and points per tile unit.
    private struct Frame {
        var center: CGPoint
        var scale: CGFloat
        /// How far the tile is turned, clockwise in radians.
        var angle: Double = 0

        func point(_ point: Point) -> CGPoint {
            let turned = CellFrame(center: .zero, angle: angle).turn(point)
            return CGPoint(x: center.x + turned.x * scale, y: center.y + turned.y * scale)
        }

        func outline(of shape: TileShape) -> CGPath {
            let path = CGMutablePath()
            path.addLines(between: shape.corners.map(point))
            path.closeSubpath()
            return path
        }
    }

    // MARK: Pages

    static func render(maze: Maze, options: Options) -> Data {
        let sheet = BuildSheet(maze: maze, flippedIsSame: options.flippedIsSame)
        var pages: [(title: String, draw: (CGContext) -> Void)] = []

        pages.append(("Layout", { drawMap(maze, sheet: sheet, options: options, in: $0) }))

        let perRecipePage = recipeColumns * recipeRows
        for start in stride(from: 0, to: sheet.entries.count, by: perRecipePage) {
            let slice = Array(sheet.entries[start..<min(start + perRecipePage, sheet.entries.count)])
            pages.append(("Tiles", { drawRecipe(slice, in: $0) }))
        }

        let grid = stencilGrid(options: options, shape: largestShape(in: sheet))
        let perStencilPage = grid.columns * grid.rows
        for start in stride(from: 0, to: sheet.entries.count, by: perStencilPage) {
            let slice = Array(sheet.entries[start..<min(start + perStencilPage, sheet.entries.count)])
            pages.append((
                "Stencils at \(inches(options.tileInches)) flat to flat",
                { drawStencils(slice, grid: grid, in: $0) }
            ))
        }

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        return renderer.pdfData { context in
            for (index, page) in pages.enumerated() {
                context.beginPage()
                draw("TubeTiles build sheet · \(page.title)", at: CGPoint(x: margin, y: margin), size: 11, weight: .semibold)
                draw(
                    "Page \(index + 1) of \(pages.count)", at: CGPoint(x: pageSize.width - margin, y: margin),
                    size: 11, color: faint, align: .right
                )
                page.draw(context.cgContext)
            }
        }
    }

    static func inches(_ value: Double) -> String {
        String(format: "%.2f in", value)
    }

    // MARK: Map

    private static func drawMap(_ maze: Maze, sheet: BuildSheet, options: Options, in context: CGContext) {
        let legendHeight: CGFloat = 78
        let area = CGRect(x: body.minX, y: body.minY, width: body.width, height: body.height - legendHeight)

        // The maze's extent, as in the app: its mask, or its whole region.
        let bounds = maze.mask?.bounds
        let whole = maze.tiling.extent(radius: maze.radius)
        let across = bounds.map { $0.max.x - $0.min.x } ?? whole.width
        let tall = bounds.map { $0.max.y - $0.min.y } ?? whole.height
        let middle = bounds.map { ($0.min + $0.max) * 0.5 } ?? .zero
        let scale = min(area.width / across, area.height / tall)
        let origin = CGPoint(x: area.midX - middle.x * scale, y: area.midY - middle.y * scale)
        func frame(_ coord: HexCoord) -> Frame {
            let cell = maze.frame(of: coord)
            return Frame(
                center: CGPoint(x: origin.x + cell.center.x * scale, y: origin.y + cell.center.y * scale),
                scale: scale, angle: cell.angle
            )
        }

        var frameRects: [CGRect] = []
        for shape in maze.mask?.shapes ?? [] where !shape.subtracts {
            frameRects.append(CGRect(
                x: origin.x + (shape.center.x - shape.width / 2) * scale,
                y: origin.y + (shape.center.y - shape.height / 2) * scale,
                width: shape.width * scale, height: shape.height * scale
            ))
        }

        let weave = maze.weave()
        context.saveGState()
        if !frameRects.isEmpty { context.clip(to: frameRects) }
        for coord in maze.coords {
            let cell = frame(coord)
            let outline = cell.outline(of: maze.tiling.shape(of: coord))
            context.saveGState()
            context.addPath(outline)
            context.clip()
            if let placed = maze.cells[coord] {
                drawPipes(placed.oriented.pipes, style: maze.style(at: coord), frame: cell, in: context, ink: faint, crossings: weave.crossings(at: coord))
            }
            context.restoreGState()
            context.addPath(outline)
            context.setStrokeColor(UIColor(white: 0.8, alpha: 1).cgColor)
            context.setLineWidth(0.5)
            context.strokePath()
        }
        context.restoreGState()
        for rect in frameRects {
            context.setStrokeColor(ink.cgColor)
            context.setLineWidth(1)
            context.stroke(rect)
        }

        // Each tile's letter, and a mark on the edge its stencil shows at
        // the top.
        let letterSize = min(max(scale * 0.5, 5), 20)
        for (coord, placement) in sheet.placements.sorted(by: { $0.key < $1.key }) {
            let cell = frame(coord)
            let top = placement.transform.apply(to: Port(edge: 0, slot: 0), portsPerEdge: maze.portsPerEdge).edge
            drawTopMark(
                edge: top, hollow: placement.transform.mirrored, shape: maze.tiling.shape(of: coord),
                portsPerEdge: maze.portsPerEdge, frame: cell, in: context
            )
            draw(
                sheet.entries[placement.entry].label,
                at: CGPoint(x: cell.center.x, y: cell.center.y - letterSize * 0.6),
                size: letterSize, weight: .bold, align: .center, halo: true
            )
        }

        // What the map means, and how big the finished piece is.
        // A tile's size is given flat to flat, which is its height.
        let unit = options.tileInches / largestShape(in: sheet).size.height
        var lines = [
            "\(sheet.tileCount) tiles, \(sheet.entries.count) different. Finished size about \(inches(across * unit)) by \(inches(tall * unit)) with tiles \(inches(options.tileInches)) flat to flat.",
            "Each cell shows its tile's letter. The triangle is on the edge that the tile's stencil shows at the top.",
            "Stencils leave crossings open. Finish each one to match the map, where the upper pipe is drawn unbroken.",
        ]
        if options.flippedIsSame {
            lines.insert("A hollow triangle means the tile is turned over before it is turned round.", at: 2)
        }
        for (index, line) in lines.enumerated() {
            draw(line, at: CGPoint(x: margin, y: area.maxY + 14 + CGFloat(index) * 14), size: 9.5)
        }
    }

    private static func drawTopMark(
        edge: Int, hollow: Bool, shape: TileShape, portsPerEdge: Int, frame: Frame, in context: CGContext
    ) {
        let first = shape.position(of: Port(edge: edge, slot: 0), portsPerEdge: portsPerEdge)
        let last = shape.position(of: Port(edge: edge, slot: portsPerEdge - 1), portsPerEdge: portsPerEdge)
        let middle = (first + last) * 0.5
        let inward = shape.inwardDirection(edge: edge)
        let along = Point(x: -inward.y, y: inward.x)
        let size = 0.13
        let path = CGMutablePath()
        path.addLines(between: [
            frame.point(middle + inward * 0.04 + along * size),
            frame.point(middle + inward * 0.04 + along * -size),
            frame.point(middle + inward * (0.04 + size * 1.5)),
        ])
        path.closeSubpath()
        context.addPath(path)
        context.setFillColor((hollow ? UIColor.white : ink).cgColor)
        context.setStrokeColor(ink.cgColor)
        context.setLineWidth(0.6)
        context.drawPath(using: .fillStroke)
    }

    // MARK: Recipe

    private static let recipeColumns = 6
    private static let recipeRows = 7

    private static func drawRecipe(_ entries: [BuildSheet.Entry], in context: CGContext) {
        let cellWidth = body.width / CGFloat(recipeColumns)
        let cellHeight = body.height / CGFloat(recipeRows)
        for (index, entry) in entries.enumerated() {
            let column = CGFloat(index % recipeColumns)
            let row = CGFloat(index / recipeColumns)
            let center = CGPoint(
                x: body.minX + (column + 0.5) * cellWidth, y: body.minY + row * cellHeight + cellHeight * 0.42
            )
            // As large as the cell allows, leaving room for the label.
            let outline = entry.tile.shape.size
            let scale = min(cellWidth * 0.88 / outline.width, (cellHeight - 26) * 0.866 / outline.height)
            drawStencil(entry.tile, frame: Frame(center: center, scale: scale), outline: 0.6, in: context)
            draw(
                "\(entry.label)  ×\(entry.count)",
                at: CGPoint(x: center.x, y: center.y + scale * outline.height / 2 + 4),
                size: 10, weight: .semibold, align: .center
            )
        }
    }

    // MARK: Stencils

    private static let topMarkRoom: CGFloat = 10

    private struct StencilGrid {
        var columns: Int
        var rows: Int
        var scale: CGFloat
        var cell: CGSize
    }

    /// The tallest shape among a sheet's tiles. The size asked for is this
    /// one's, flat to flat; smaller shapes are cut to the same edge length.
    private static func largestShape(in sheet: BuildSheet) -> TileShape {
        sheet.entries.map(\.tile.shape).max { $0.size.height < $1.size.height } ?? .hexagon
    }

    /// How many real-size tiles fit on a page, in plain rows and columns.
    private static func stencilGrid(options: Options, shape: TileShape) -> StencilGrid {
        // Points per tile unit. A tile's size is given flat to flat, which
        // is its height.
        let outline = shape.size
        let scale = options.tileInches * 72 / outline.height
        // Room above each tile for its top mark and below it for its label.
        let cell = CGSize(
            width: scale * outline.width + 12, height: CGFloat(options.tileInches * 72) + topMarkRoom + 24
        )
        return StencilGrid(
            columns: max(1, Int((body.width + 12) / cell.width)),
            rows: max(1, Int(body.height / cell.height)),
            scale: scale, cell: cell
        )
    }

    private static func drawStencils(_ entries: [BuildSheet.Entry], grid: StencilGrid, in context: CGContext) {
        let used = CGFloat(grid.columns) * grid.cell.width - 12
        let left = body.minX + (body.width - used) / 2
        for (index, entry) in entries.enumerated() {
            let column = CGFloat(index % grid.columns)
            let row = CGFloat(index / grid.columns)
            let outline = entry.tile.shape.size
            let half = grid.scale * outline.height / 2
            let center = CGPoint(
                x: left + column * grid.cell.width + (grid.cell.width - 12) / 2,
                y: body.minY + row * grid.cell.height + topMarkRoom + half
            )
            let frame = Frame(center: center, scale: grid.scale)
            drawStencil(entry.tile, frame: frame, outline: 0.75, in: context)
            // The top mark sits just outside the tile, clear of its pipes.
            let tip = CGPoint(x: center.x, y: center.y - half - 1.5)
            let mark = CGMutablePath()
            mark.addLines(between: [
                tip, CGPoint(x: tip.x - 5, y: tip.y - 7), CGPoint(x: tip.x + 5, y: tip.y - 7),
            ])
            mark.closeSubpath()
            context.addPath(mark)
            context.setFillColor(ink.cgColor)
            context.fillPath()
            draw(
                "\(entry.label)  ×\(entry.count)", at: CGPoint(x: center.x, y: center.y + half + 5),
                size: 11, weight: .semibold, align: .center
            )
        }
    }

    /// One tile with its crossings left open: every pipe's walls first, then
    /// every pipe's inside, so where two cross neither is on top.
    private static func drawStencil(_ tile: Tile, frame: Frame, outline: CGFloat, in context: CGContext) {
        let border = frame.outline(of: tile.shape)
        context.saveGState()
        context.addPath(border)
        context.clip()
        drawPipes(tile.pipes, style: tile.style, frame: frame, in: context, ink: ink, crossings: nil)
        context.restoreGState()
        context.addPath(border)
        context.setStrokeColor(ink.cgColor)
        context.setLineWidth(outline)
        context.strokePath()
    }

    // MARK: Pipes

    private static func linePath(_ shape: PipeShape, frame: Frame) -> CGPath {
        let path = CGMutablePath()
        for (index, segment) in shape.segments.enumerated() {
            switch segment {
            case let .line(start, end):
                if index == 0 { path.move(to: frame.point(start)) }
                path.addLine(to: frame.point(end))
            case let .cubic(start, control1, control2, end):
                if index == 0 { path.move(to: frame.point(start)) }
                path.addCurve(to: frame.point(end), control1: frame.point(control1), control2: frame.point(control2))
            }
        }
        return path
    }

    /// Draws pipes woven, with the upper one redrawn across each crossing,
    /// or with crossings open when `crossings` is nil.
    private static func drawPipes(
        _ pipes: [Pipe], style: TileStyle, frame: Frame, in context: CGContext, ink: UIColor, crossings: [Crossing]?
    ) {
        let outer = style.pipeWidth * frame.scale
        let inner = (style.pipeWidth - style.wallThickness * 2) * frame.scale
        context.setLineJoin(.round)

        func walls(_ shape: PipeShape) {
            context.setLineCap(.round)
            context.addPath(linePath(shape, frame: frame))
            context.setStrokeColor(ink.cgColor)
            context.setLineWidth(outer)
            context.strokePath()
            if let room = shape.room {
                context.setFillColor(ink.cgColor)
                context.fillEllipse(in: disc(room, inset: 0, frame: frame))
            }
        }
        func inside(_ shape: PipeShape) {
            context.setLineCap(.round)
            context.addPath(linePath(shape, frame: frame))
            context.setStrokeColor(UIColor.white.cgColor)
            context.setLineWidth(inner)
            context.strokePath()
            if let room = shape.room {
                context.setFillColor(UIColor.white.cgColor)
                context.fillEllipse(in: disc(room, inset: style.wallThickness, frame: frame))
            }
        }

        let shapes = pipes.map { PipeShape($0, style: style) }
        guard let crossings else {
            shapes.forEach(walls)
            shapes.forEach(inside)
            return
        }
        for shape in shapes {
            walls(shape)
            inside(shape)
        }
        context.setLineCap(.butt)
        for crossing in crossings {
            let line = Polyline(PipeShape(crossing.over, style: style))
            let half = crossing.bridgeHalfLength(style: style)
            let points = line.slice(from: crossing.overDistance - half, to: crossing.overDistance + half).map(frame.point)
            guard points.count > 1 else { continue }
            for (width, color) in [(outer, ink), (inner, UIColor.white)] {
                context.addLines(between: points)
                context.setStrokeColor(color.cgColor)
                context.setLineWidth(width)
                context.strokePath()
            }
        }
    }

    private static func disc(_ room: Disc, inset: Double, frame: Frame) -> CGRect {
        let radius = (room.diameter / 2 - inset) * frame.scale
        let center = frame.point(room.center)
        return CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    // MARK: Text

    private static func draw(
        _ text: String, at point: CGPoint, size: CGFloat, weight: UIFont.Weight = .regular,
        color: UIColor = .black, align: NSTextAlignment = .left, halo: Bool = false
    ) {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color,
        ]
        let measured = (text as NSString).size(withAttributes: attributes)
        var origin = point
        switch align {
        case .center: origin.x -= measured.width / 2
        case .right: origin.x -= measured.width
        default: break
        }
        if halo {
            // A white edge, so a letter reads over the pipes behind it.
            var edge = attributes
            edge[.strokeColor] = UIColor.white
            edge[.strokeWidth] = 28
            (text as NSString).draw(at: origin, withAttributes: edge)
        }
        attributes[.strokeWidth] = 0
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }
}
