import SwiftUI

/// A 5-pixel-tall bitmap font plus a few 5×5 icons, so UI chrome matches the sprites.
enum PixelFont {
    static let height = 5

    static let glyphs: [Character: [String]] = [
        "A": [".x.", "x.x", "xxx", "x.x", "x.x"], "B": ["xx.", "x.x", "xx.", "x.x", "xx."],
        "C": [".xx", "x..", "x..", "x..", ".xx"], "D": ["xx.", "x.x", "x.x", "x.x", "xx."],
        "E": ["xxx", "x..", "xx.", "x..", "xxx"], "F": ["xxx", "x..", "xx.", "x..", "x.."],
        "G": [".xx", "x..", "x.x", "x.x", ".xx"], "H": ["x.x", "x.x", "xxx", "x.x", "x.x"],
        "I": ["xxx", ".x.", ".x.", ".x.", "xxx"], "J": ["..x", "..x", "..x", "x.x", ".x."],
        "K": ["x.x", "x.x", "xx.", "x.x", "x.x"], "L": ["x..", "x..", "x..", "x..", "xxx"],
        "M": ["x...x", "xx.xx", "x.x.x", "x...x", "x...x"], "N": ["x..x", "xx.x", "x.xx", "x..x", "x..x"],
        "O": [".x.", "x.x", "x.x", "x.x", ".x."], "P": ["xx.", "x.x", "xx.", "x..", "x.."],
        "Q": [".x.", "x.x", "x.x", "xx.", ".xx"], "R": ["xx.", "x.x", "xx.", "x.x", "x.x"],
        "S": [".xx", "x..", ".x.", "..x", "xx."], "T": ["xxx", ".x.", ".x.", ".x.", ".x."],
        "U": ["x.x", "x.x", "x.x", "x.x", "xxx"], "V": ["x.x", "x.x", "x.x", "x.x", ".x."],
        "W": ["x...x", "x...x", "x.x.x", "xx.xx", "x...x"], "X": ["x.x", "x.x", ".x.", "x.x", "x.x"],
        "Y": ["x.x", "x.x", ".x.", ".x.", ".x."], "Z": ["xxx", "..x", ".x.", "x..", "xxx"],
        "0": ["xxx", "x.x", "x.x", "x.x", "xxx"], "1": [".x.", "xx.", ".x.", ".x.", "xxx"],
        "2": ["xx.", "..x", ".x.", "x..", "xxx"], "3": ["xx.", "..x", ".x.", "..x", "xx."],
        "4": ["x.x", "x.x", "xxx", "..x", "..x"], "5": ["xxx", "x..", "xx.", "..x", "xx."],
        "6": [".xx", "x..", "xxx", "x.x", "xxx"], "7": ["xxx", "..x", ".x.", ".x.", ".x."],
        "8": ["xxx", "x.x", "xxx", "x.x", "xxx"], "9": ["xxx", "x.x", "xxx", "..x", "xx."],
        " ": ["..", "..", "..", "..", ".."], ".": [".", ".", ".", ".", "x"],
        "!": ["x", "x", "x", ".", "x"], "?": ["xx.", "..x", ".x.", "...", ".x."],
        "-": ["...", "...", "xxx", "...", "..."], "#": [".x.x.", "xxxxx", ".x.x.", "xxxxx", ".x.x."],
        ":": [".", "x", ".", "x", "."], "/": ["..x", "..x", ".x.", "x..", "x.."],
        "%": ["x.x", "..x", ".x.", "x..", "x.x"], "+": ["...", ".x.", "xxx", ".x.", "..."],
        "·": [".", ".", "x", ".", "."], "'": ["x", "x", ".", ".", "."],
        // Icons, addressed by private-use characters.
        Icon.gear: ["x.x.x", ".xxx.", "xx.xx", ".xxx.", "x.x.x"],
        Icon.plus: ["..x..", "..x..", "xxxxx", "..x..", "..x.."],
        Icon.send: ["x....", "xxx..", "xxxxx", "xxx..", "x...."],
        Icon.stop: ["xxxxx", "xxxxx", "xxxxx", "xxxxx", "xxxxx"],
        Icon.copy: ["xxx..", "x.xxx", "x.x.x", "xxx.x", "..xxx"],
        Icon.back: ["..x..", ".x...", "xxxxx", ".x...", "..x.."],
        Icon.clip: [".xxx.", "xx.xx", "x...x", "x...x", "xxxxx"],
        Icon.check: ["....x", "...x.", "x.x..", ".x...", "....."],
        Icon.dice: ["xxxxx", "x...x", "x.x.x", "x...x", "xxxxx"],
        Icon.close: ["x...x", ".x.x.", "..x..", ".x.x.", "x...x"],
    ]

    enum Icon {
        static let gear: Character = "\u{E000}"
        static let plus: Character = "\u{E001}"
        static let send: Character = "\u{E002}"
        static let stop: Character = "\u{E003}"
        static let copy: Character = "\u{E004}"
        static let back: Character = "\u{E005}"
        static let clip: Character = "\u{E006}"
        static let check: Character = "\u{E007}"
        static let dice: Character = "\u{E008}"
        static let close: Character = "\u{E009}"
    }

    static func glyph(_ c: Character) -> [String] {
        glyphs[Character(c.uppercased())] ?? glyphs["?"]!
    }

    static func width(of text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        return text.reduce(0) { $0 + glyph($1)[0].count + 1 } - 1
    }
}

struct PixelText: View {
    let text: String
    var pixel: CGFloat = 2
    var color: Color = Theme.text

    init(_ text: String, pixel: CGFloat = 2, color: Color = Theme.text) {
        self.text = text
        self.pixel = pixel
        self.color = color
    }

    init(icon: Character, pixel: CGFloat = 2, color: Color = Theme.text) {
        self.init(String(icon), pixel: pixel, color: color)
    }

    var body: some View {
        Canvas { ctx, _ in
            var x = 0
            for ch in text {
                let rows = PixelFont.glyph(ch)
                for (y, row) in rows.enumerated() {
                    for (dx, bit) in row.enumerated() where bit == "x" {
                        ctx.fill(Path(CGRect(x: CGFloat(x + dx) * pixel, y: CGFloat(y) * pixel, width: pixel, height: pixel)), with: .color(color))
                    }
                }
                x += rows[0].count + 1
            }
        }
        .frame(width: CGFloat(PixelFont.width(of: text)) * pixel, height: CGFloat(PixelFont.height) * pixel)
        .accessibilityLabel(text)
    }
}
