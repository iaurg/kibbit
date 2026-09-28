import SwiftUI

enum Theme {
    static let background = Color(red: 0.11, green: 0.10, blue: 0.17)
    static let panel = Color(red: 0.17, green: 0.15, blue: 0.26)
    static let panelHi = Color(red: 0.23, green: 0.21, blue: 0.35)
    static let border = Color(red: 0.05, green: 0.04, blue: 0.09)
    static let code = Color(red: 0.07, green: 0.06, blue: 0.12)
    static let text = Color(red: 0.96, green: 0.94, blue: 0.90)
    static let muted = Color(red: 0.60, green: 0.57, blue: 0.72)
    static let danger = Color(red: 1.0, green: 0.36, blue: 0.40)
    static let good = Color(red: 0.45, green: 0.90, blue: 0.55)
}

/// Rectangle with 1-step notched corners, the classic pixel-art window shape.
struct PixelBox: Shape {
    var notch: CGFloat = 2

    func path(in r: CGRect) -> Path {
        let n = notch
        var p = Path()
        p.addLines([
            CGPoint(x: r.minX + n, y: r.minY), CGPoint(x: r.maxX - n, y: r.minY),
            CGPoint(x: r.maxX - n, y: r.minY + n), CGPoint(x: r.maxX, y: r.minY + n),
            CGPoint(x: r.maxX, y: r.maxY - n), CGPoint(x: r.maxX - n, y: r.maxY - n),
            CGPoint(x: r.maxX - n, y: r.maxY), CGPoint(x: r.minX + n, y: r.maxY),
            CGPoint(x: r.minX + n, y: r.maxY - n), CGPoint(x: r.minX, y: r.maxY - n),
            CGPoint(x: r.minX, y: r.minY + n), CGPoint(x: r.minX + n, y: r.minY + n),
        ])
        p.closeSubpath()
        return p
    }
}

extension View {
    /// Filled pixel box with a hard 2pt border and an offset drop shadow.
    func pixelPanel(fill: Color = Theme.panel, border: Color = Theme.border, shadow: Bool = true) -> some View {
        background(
            ZStack {
                if shadow { PixelBox().fill(Theme.border.opacity(0.6)).offset(x: 2, y: 2) }
                PixelBox().fill(border)
                PixelBox().fill(fill).padding(2)
            }
        )
    }
}

struct PixelButtonStyle: ButtonStyle {
    var fill: Color = Theme.panelHi
    var border: Color = Theme.border

    func makeBody(configuration: Configuration) -> some View {
        PixelButtonBody(configuration: configuration, fill: fill, border: border)
    }

    private struct PixelButtonBody: View {
        let configuration: Configuration
        let fill: Color
        let border: Color
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .pixelPanel(fill: hovering && enabled ? fill.opacity(0.75) : fill, border: border, shadow: !configuration.isPressed)
                .offset(x: configuration.isPressed ? 2 : 0, y: configuration.isPressed ? 2 : 0)
                .opacity(enabled ? 1 : 0.45)
                .onHover { hovering = $0 }
                .contentShape(Rectangle())
        }
    }
}

struct PetSpriteView: View {
    let pet: PetKind
    let palette: PetPalette
    var frame = PetFrame()
    var pixel: CGFloat = 3

    var body: some View {
        CellCanvas(cells: Sprite.cells(pet: pet, palette: palette, frame: frame), pixel: pixel)
            .accessibilityLabel(pet.displayName)
    }
}

/// Draws sprite cells on the shared 22×18 canvas.
struct CellCanvas: View {
    let cells: [Cell]
    var pixel: CGFloat = 3

    var body: some View {
        Canvas { ctx, _ in
            for cell in cells {
                ctx.fill(Path(CGRect(x: CGFloat(cell.x) * pixel, y: CGFloat(cell.y) * pixel, width: pixel, height: pixel)),
                         with: .color(cell.color.color))
            }
        }
        .frame(width: CGFloat(Sprite.width) * pixel, height: CGFloat(Sprite.height) * pixel)
    }
}

extension Rarity {
    var color: Color {
        switch self {
        case .common: Theme.muted
        case .rare: Color(red: 0.45, green: 0.75, blue: 1)
        case .legendary: Color(red: 1, green: 0.85, blue: 0.3)
        }
    }
}
