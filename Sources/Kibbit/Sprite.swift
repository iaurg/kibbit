import AppKit

enum Overlay: Equatable {
    case none
    case dots(Int)
    case heart
    case zzz(Int)
    case bang
    case sparkle
}

struct PetFrame: Equatable {
    /// Vertical offset of the pet inside the canvas: 0 = jump, 1 = rest, 2 = squat.
    var y = 1
    var eyesClosed = false
    var overlay: Overlay = .none
}

struct Cell {
    let x, y: Int
    let color: RGB
}

enum Sprite {
    static let width = 22
    static let height = 18

    static func cells(pet: PetKind, palette: PetPalette, frame: PetFrame) -> [Cell] {
        let grid = pet.grid
        var out: [Cell] = []
        out.reserveCapacity(200)
        for (row, line) in grid.enumerated() {
            for (col, key) in line.enumerated() {
                var key = key
                if frame.eyesClosed, key == "e" || key == "w" {
                    let below = row + 1 < grid.count ? grid[row + 1][col] : "."
                    key = (below == "e" || below == "w") ? "b" : "o"
                }
                if let color = palette.color(for: key) {
                    out.append(Cell(x: col, y: row + frame.y, color: color))
                }
            }
        }
        out += overlayCells(frame.overlay, palette: palette)
        return out
    }

    private struct Glyph {
        let pattern: [String]
        let color: RGB
        /// Row offset, used to float the Z upward.
        var top = 0

        var points: [(x: Int, y: Int)] {
            pattern.enumerated().flatMap { row, line in
                line.enumerated().compactMap { col, ch in ch == "x" ? (col, top + row) : nil }
            }
        }
        var width: Int { pattern.first?.count ?? 0 }
    }

    private static func glyph(for overlay: Overlay) -> Glyph? {
        switch overlay {
        case .none: nil
        case .dots(let n) where n <= 0: nil
        case .dots(let n): Glyph(pattern: [String("x.x.x".prefix(n * 2 - 1))], color: RGB(r: 1, g: 0.75, b: 0.2))
        case .heart: Glyph(pattern: ["x.x", "xxx", ".x."], color: RGB(r: 1, g: 0.3, b: 0.43))
        case .zzz(let step): Glyph(pattern: ["xxx", "..x", ".x.", "x..", "xxx"], color: RGB(r: 0.55, g: 0.75, b: 1), top: 2 - step % 3)
        case .bang: Glyph(pattern: ["x", "x", "x", ".", "x"], color: RGB(r: 1, g: 0.3, b: 0.3))
        case .sparkle: Glyph(pattern: [".x.", "xxx", ".x."], color: RGB(r: 1, g: 0.85, b: 0.3))
        }
    }

    /// In the chat header and setup there's room beside the pet.
    private static func overlayCells(_ overlay: Overlay, palette: PetPalette) -> [Cell] {
        guard let glyph = glyph(for: overlay) else { return [] }
        return glyph.points.map { Cell(x: 16 + $0.x, y: $0.y, color: glyph.color) }
    }

    // MARK: Menu bar

    /// The menu bar icon is just the pet, so macOS pads it evenly like any other icon.
    static let menuBarWidth = 16

    /// Pet plus the overlay as a badge in its top-right corner. The badge gets a 1px outline ring
    /// so it reads on top of the pet instead of needing its own empty columns.
    static func menuBarCells(pet: PetKind, palette: PetPalette, frame: PetFrame) -> [Cell] {
        var bare = frame
        bare.overlay = .none
        var out = cells(pet: pet, palette: palette, frame: bare)
        guard let glyph = glyph(for: frame.overlay) else { return out }

        let x0 = menuBarWidth - glyph.width
        let points = glyph.points.map { (x: x0 + $0.x, y: $0.y) }
        var ring: [(x: Int, y: Int)] = []
        for p in points {
            for dx in -1...1 {
                for dy in -1...1 {
                    let n = (x: p.x + dx, y: p.y + dy)
                    guard (0..<menuBarWidth).contains(n.x), (0..<height).contains(n.y),
                          !points.contains(where: { $0 == n }), !ring.contains(where: { $0 == n }) else { continue }
                    ring.append(n)
                }
            }
        }
        // Later cells paint over earlier ones, so the badge lands on top of the pet.
        out += ring.map { Cell(x: $0.x, y: $0.y, color: palette.outline) }
        out += points.map { Cell(x: $0.x, y: $0.y, color: glyph.color) }
        return out
    }

    /// Crack pixels per hatch stage, drawn in outline color across the egg's middle.
    static let eggCracks: [[(x: Int, y: Int)]] = [
        [],
        [(6, 8), (7, 7), (8, 8), (9, 7)],
        [(4, 8), (5, 7), (6, 8), (7, 7), (8, 8), (9, 7), (10, 8), (11, 7), (7, 6), (8, 9)],
    ]

    static func eggCells(palette: PetPalette, wobble: Int = 0, crack: Int = 0) -> [Cell] {
        let cracks = eggCracks[min(max(crack, 0), eggCracks.count - 1)]
        var out: [Cell] = []
        for (row, line) in PetKind.eggGrid.enumerated() {
            for (col, key) in line.enumerated() {
                let isCrack = key != "." && cracks.contains { $0.x == col && $0.y == row }
                guard let color = palette.color(for: isCrack ? "o" : key) else { continue }
                out.append(Cell(x: col + 1 + wobble, y: row + 1, color: color))
            }
        }
        return out
    }

    static func draw(_ cells: [Cell], in ctx: CGContext, pixel: CGFloat, originX: CGFloat = 0, originY: CGFloat = 0) {
        for cell in cells {
            ctx.setFillColor(cell.color.cgColor)
            ctx.fill(CGRect(x: originX + CGFloat(cell.x) * pixel, y: originY + CGFloat(cell.y) * pixel, width: pixel, height: pixel))
        }
    }

    /// Point-per-pixel image sized for the menu bar; on Retina each sprite pixel lands on a crisp 2×2 block.
    static func menuBarImage(pet: PetKind, palette: PetPalette, frame: PetFrame) -> NSImage {
        let cells = menuBarCells(pet: pet, palette: palette, frame: frame)
        let image = NSImage(size: NSSize(width: menuBarWidth, height: height), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.interpolationQuality = .none
            ctx.setShouldAntialias(false)
            draw(cells, in: ctx, pixel: 1)
            return true
        }
        image.isTemplate = false
        return image
    }
}
