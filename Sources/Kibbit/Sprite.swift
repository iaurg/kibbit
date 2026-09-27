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

    private static func overlayCells(_ overlay: Overlay, palette: PetPalette) -> [Cell] {
        var top = 0
        let (pattern, color): ([String], RGB) = switch overlay {
        case .none:
            ([], palette.white)
        case .dots(let n):
            ([String("x.x.x".prefix(max(0, n * 2 - 1)))], RGB(r: 1, g: 0.75, b: 0.2))
        case .heart:
            (["x.x", "xxx", ".x."], RGB(r: 1, g: 0.3, b: 0.43))
        case .zzz(let step):
            // The Z drifts upward as the pet snoozes.
            {
                top = 2 - step % 3
                return (["xxx", "..x", ".x.", "x..", "xxx"], RGB(r: 0.55, g: 0.75, b: 1))
            }()
        case .bang:
            (["x", "x", "x", ".", "x"], RGB(r: 1, g: 0.3, b: 0.3))
        case .sparkle:
            ([".x.", "xxx", ".x."], RGB(r: 1, g: 0.85, b: 0.3))
        }
        var out: [Cell] = []
        for (row, line) in pattern.enumerated() {
            for (col, ch) in line.enumerated() where ch == "x" {
                out.append(Cell(x: 16 + col, y: top + row, color: color))
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
        let cells = cells(pet: pet, palette: palette, frame: frame)
        let image = NSImage(size: NSSize(width: width, height: height), flipped: true) { _ in
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
