import SwiftUI
import AiTwinCore

extension Color {
    init(_ palette: PaletteColor) {
        self.init(.sRGB, red: palette.red, green: palette.green, blue: palette.blue, opacity: 1)
    }
}

/// A pixel-art thought cloud, drawn rather than loaded from an image.
///
/// Drawn instead of shipped as a PNG for one reason: the cloud has to stretch to
/// whatever the message needs, and a stretched bitmap either distorts its lumps
/// or needs nine-slice art with the corners fixed. Generating the silhouette and
/// then *quantising it to a pixel grid* keeps every lump the same size and every
/// edge a genuine staircase, at any width the text asks for.
///
/// The shape is the union of a core rectangle and a ring of equal-sized circles
/// sitting on its perimeter -- which is why a wide cloud grows more lumps rather
/// than wider ones, exactly like hand-drawn cloud art.
public struct PixelCloud: View {
    /// Edge length of one "pixel", in points. Bigger reads chunkier.
    static let cell: CGFloat = 3
    /// Radius of each lump. Constant in points, so lumps never stretch.
    ///
    /// Small on purpose: the lump radius also sets how much padding the text
    /// needs to clear the scalloped edge, so a big lump forces a big box. 18
    /// keeps the cloud compact without losing the shape.
    static let lump: CGFloat = 18
    /// Vertical space the tail occupies below the body.
    static let tailHeight: CGFloat = 17
    /// Width of the tail where it meets the body.
    static let tailWidth: CGFloat = 28

    /// Corner rounding for the non-cloud styles.
    static let cornerRadius: CGFloat = 9

    let palette: CharacterPalette
    let tailOnLeft: Bool
    let style: BubbleStyle

    public init(palette: CharacterPalette, tailOnLeft: Bool, style: BubbleStyle = .cloud) {
        self.palette = palette
        self.tailOnLeft = tailOnLeft
        self.style = style
    }

    /// Space the text must leave clear on each side for the chosen style.
    public static func insets(for style: BubbleStyle) -> (horizontal: CGFloat, top: CGFloat, bottom: CGFloat) {
        switch style {
        case .cloud:   return (lump * 0.95, lump * 0.85, lump * 0.85 + tailHeight)
        case .speech:  return (13, 10, 10 + tailHeight)
        case .rounded: return (13, 10, 10)
        case .plain:   return (2, 2, 2)
        }
    }

    public var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            guard style.isFramed else { return }
            let grid = Self.grid(for: size, tailOnLeft: tailOnLeft, style: style)
            Self.draw(grid, in: &context, palette: palette)
        }
        .drawingGroup()
    }

    // MARK: Silhouette

    /// Which colour each cell of the pixel grid should be.
    enum Cell: UInt8 { case empty, ink, accent, paper, highlight, sparkle }

    struct Grid {
        var cells: [Cell]
        let columns: Int
        let rows: Int
        subscript(column: Int, row: Int) -> Cell {
            get {
                guard column >= 0, column < columns, row >= 0, row < rows else { return .empty }
                return cells[row * columns + column]
            }
            set {
                guard column >= 0, column < columns, row >= 0, row < rows else { return }
                cells[row * columns + column] = newValue
            }
        }
    }

    static func grid(for size: CGSize, tailOnLeft: Bool, style: BubbleStyle = .cloud) -> Grid {
        let columns = max(4, Int((size.width / cell).rounded()))
        let rows = max(4, Int((size.height / cell).rounded()))

        let bodyHeight = max(cell * 3, size.height - (style.hasTail ? tailHeight : 0))
        // Lump centres sit `lump` in from every edge, so the lumps land exactly
        // on the boundary instead of being clipped off it.
        var left = lump, top = lump
        var right = size.width - lump, bottom = bodyHeight - lump
        if right <= left { left = size.width / 2; right = left }
        if bottom <= top { top = bodyHeight / 2; bottom = top }

        var centres: [CGPoint] = []
        func spread(_ from: CGFloat, _ to: CGFloat, step: CGFloat) -> [CGFloat] {
            let count = max(2, Int(((to - from) / step).rounded()) + 1)
            return (0..<count).map { from + (to - from) * CGFloat($0) / CGFloat(count - 1) }
        }
        if style == .cloud {
            // A ring of equal circles on the core's perimeter. Because the
            // radius is fixed in points, a wider cloud grows *more* lumps
            // rather than wider ones -- which is how hand-drawn cloud art works.
            for x in spread(left, right, step: lump * 1.55) {
                centres.append(CGPoint(x: x, y: top))
                centres.append(CGPoint(x: x, y: bottom))
            }
            for y in spread(top, bottom, step: lump * 1.55) {
                centres.append(CGPoint(x: left, y: y))
                centres.append(CGPoint(x: right, y: y))
            }
        } else {
            // Speech and rounded fill the whole box -- only the cloud is inset
            // to leave room for its lumps. Corner circles give the rounding.
            let radius = min(cornerRadius, min(size.width, bodyHeight) / 2)
            for x in [radius, size.width - radius] {
                for y in [radius, bodyHeight - radius] {
                    centres.append(CGPoint(x: x, y: y))
                }
            }
        }

        // A wedge hanging off the bottom corner, pointing back at the character.
        // The tail hangs from the body's own bottom corner, which differs
        // between the inset cloud and the full-bleed rounded styles.
        let tailInset: CGFloat = style == .cloud ? lump * 1.15 : cornerRadius + 4
        let anchorX = tailOnLeft ? tailInset : size.width - tailInset
        let tail: (CGPoint, CGPoint, CGPoint)
        if style.hasTail {
            tail = (
                CGPoint(x: anchorX, y: bodyHeight - (style == .cloud ? lump * 0.55 : 6)),
                CGPoint(x: tailOnLeft ? anchorX + tailWidth : anchorX - tailWidth, y: bodyHeight + 2),
                CGPoint(x: tailOnLeft ? max(1, anchorX - tailWidth * 0.5) : min(size.width - 1, anchorX + tailWidth * 0.5),
                        y: size.height - 1)
            )
        } else {
            tail = (.zero, .zero, .zero)
        }

        func isInside(_ point: CGPoint) -> Bool {
            if style == .cloud {
                if point.x >= left, point.x <= right, point.y >= top, point.y <= bottom { return true }
            } else {
                // A rounded rectangle covering the whole body: two overlapping
                // rectangles plus the corner circles added above.
                let radius = min(cornerRadius, min(size.width, bodyHeight) / 2)
                if point.x >= radius, point.x <= size.width - radius,
                   point.y >= 0, point.y <= bodyHeight { return true }
                if point.x >= 0, point.x <= size.width,
                   point.y >= radius, point.y <= bodyHeight - radius { return true }
            }
            for centre in centres {
                let dx = point.x - centre.x, dy = point.y - centre.y
                if dx * dx + dy * dy <= lump * lump { return true }
            }
            return contains(point, tail)
        }

        var grid = Grid(cells: Array(repeating: .empty, count: columns * rows),
                        columns: columns, rows: rows)
        for row in 0..<rows {
            for column in 0..<columns {
                let point = CGPoint(x: (CGFloat(column) + 0.5) * cell, y: (CGFloat(row) + 0.5) * cell)
                if isInside(point) { grid[column, row] = .paper }
            }
        }

        // Outline, then a one-cell accent ring just inside it. The ring is what
        // makes it read as painted art rather than a flat vector shape.
        let filled = grid
        func solid(_ c: Int, _ r: Int) -> Bool { filled[c, r] != .empty }
        for row in 0..<rows {
            for column in 0..<columns where filled[column, row] != .empty {
                var touchesEdge = false, nearEdge = false
                for dx in -2...2 {
                    for dy in -2...2 where !(dx == 0 && dy == 0) {
                        if !solid(column + dx, row + dy) {
                            nearEdge = true
                            if abs(dx) <= 1 && abs(dy) <= 1 { touchesEdge = true }
                        }
                    }
                }
                grid[column, row] = touchesEdge ? .ink : (nearEdge ? .accent : .paper)
            }
        }

        // Highlight streaks and sparkles, only where there is room for them.
        func isDeep(_ c: Int, _ r: Int) -> Bool {
            for dx in -2...2 { for dy in -2...2 where !solid(c + dx, r + dy) { return false } }
            return true
        }
        func streak(atX fx: Double, y fy: Double, length: Int) {
            var c = Int(Double(columns) * fx), r = Int(Double(rows) * fy)
            for _ in 0..<length {
                if isDeep(c, r) { grid[c, r] = .highlight }
                c += 1; r -= 1
            }
        }
        // A single soft highlight, no decorative sparkles: they read as specks
        // of dust at this size rather than as sparkle.
        streak(atX: 0.10, y: 0.40, length: 3)

        return grid
    }

    private static func contains(_ point: CGPoint, _ triangle: (CGPoint, CGPoint, CGPoint)) -> Bool {
        let (a, b, c) = triangle
        let denominator = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
        guard abs(denominator) > .ulpOfOne else { return false }
        let u = ((b.y - c.y) * (point.x - c.x) + (c.x - b.x) * (point.y - c.y)) / denominator
        let v = ((c.y - a.y) * (point.x - c.x) + (a.x - c.x) * (point.y - c.y)) / denominator
        return u >= -0.02 && v >= -0.02 && (1 - u - v) >= -0.02
    }

    // MARK: Drawing

    private static func draw(_ grid: Grid, in context: inout GraphicsContext, palette: CharacterPalette) {
        let colours: [Cell: Color] = [
            .ink: Color(palette.ink),
            .accent: Color(palette.accent),
            .paper: Color(palette.paper),
            .highlight: .white,
            .sparkle: Color(palette.sparkle),
        ]

        // Merge horizontal runs of the same colour into one rectangle. A cloud
        // is a few thousand cells; drawing each one individually would be
        // needlessly slow on every animation frame.
        for row in 0..<grid.rows {
            var column = 0
            while column < grid.columns {
                let value = grid[column, row]
                guard value != .empty else { column += 1; continue }
                var end = column
                while end + 1 < grid.columns, grid[end + 1, row] == value { end += 1 }
                let rect = CGRect(
                    x: CGFloat(column) * cell,
                    y: CGFloat(row) * cell,
                    width: CGFloat(end - column + 1) * cell,
                    height: cell
                )
                context.fill(Path(rect), with: .color(colours[value] ?? .clear))
                column = end + 1
            }
        }
    }
}
