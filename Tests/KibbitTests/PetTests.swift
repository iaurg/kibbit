import Foundation
import Testing
@testable import Kibbit

@Suite("Palettes and seeds")
struct PaletteTests {
    @Test func sameSeedSamePet() {
        for pet in PetKind.allCases {
            #expect(PetPalette(seed: 0xDA6B_2B9B, pet: pet) == PetPalette(seed: 0xDA6B_2B9B, pet: pet))
        }
    }

    @Test func seedsProduceVariety() {
        let bodies = (0..<200 as Range<UInt64>).map { PetPalette(seed: $0, pet: .cat).body }
        let distinct = Set(bodies.map { "\($0.r)-\($0.g)-\($0.b)" })
        #expect(distinct.count == bodies.count)
    }

    /// Guards the promised odds (3% legendary, 15% rare) against accidental RNG changes.
    @Test func rarityOdds() {
        let n = 20_000
        let rarities = (0..<UInt64(n)).map { PetPalette(seed: $0, pet: .cat).rarity }
        let legendary = Double(rarities.filter { $0 == .legendary }.count) / Double(n)
        let rare = Double(rarities.filter { $0 == .rare }.count) / Double(n)
        #expect((0.02...0.04).contains(legendary))
        #expect((0.13...0.17).contains(rare))
    }

    @Test func legendaryIsGold() throws {
        let seed = try #require((0..<UInt64(5_000)).first { PetPalette(seed: $0, pet: .cat).rarity == .legendary })
        #expect(PetPalette(seed: seed, pet: .cat).accent == .hsb(0.13, 0.75, 1))
    }

    @Test func rarityDoesNotDependOnPet() {
        for seed in 0..<UInt64(300) {
            let rarities = Set(PetKind.allCases.map { PetPalette(seed: seed, pet: $0).rarity })
            #expect(rarities.count == 1)
        }
    }

    @Test func penguinBellyStaysLight() {
        for seed in 0..<UInt64(300) {
            let s = PetPalette(seed: seed, pet: .penguin).secondary
            #expect(max(s.r, s.g, s.b) > 0.9)
        }
    }

    @Test func seedCodes() {
        #expect(PetPalette.seedCode(0xDA6B_2B9B) == "#DA6B-2B9B")
        #expect(PetPalette.seedCode(0) == "#0000-0000")
        for _ in 0..<100 { #expect(PetPalette.randomSeed() <= UInt64(UInt32.max)) }
    }

    @Test func hsbConversion() {
        #expect(RGB.hsb(0, 1, 1) == RGB(r: 1, g: 0, b: 0))
        #expect(RGB.hsb(0, 0, 1) == RGB(r: 1, g: 1, b: 1))
        #expect(RGB.hsb(1.0 / 3, 1, 0) == RGB(r: 0, g: 0, b: 0))
        let wrapped = RGB.hsb(1.5, 1, 1)
        let half = RGB.hsb(0.5, 1, 1)
        #expect(abs(wrapped.g - half.g) < 1e-9 && abs(wrapped.b - half.b) < 1e-9)
    }
}

@Suite("Sprites")
struct SpriteTests {
    @Test(arguments: PetKind.allCases)
    func gridIsWellFormed(pet: PetKind) {
        let grid = pet.grid
        #expect(grid.count == 16)
        #expect(grid.allSatisfy { $0.count == 16 })
        #expect(grid.allSatisfy { row in row.allSatisfy { ".obsaew".contains($0) } })
        #expect(grid.allSatisfy { $0 == Array($0.reversed()) }, "sprites are mirrored")
        #expect(grid.joined().contains("e"), "every pet needs eyes to blink")
    }

    @Test(arguments: PetKind.allCases)
    func everyFrameStaysOnCanvas(pet: PetKind) {
        let palette = PetPalette(seed: 7, pet: pet)
        let overlays: [Overlay] = [.none, .dots(0), .dots(3), .heart, .zzz(0), .zzz(1), .zzz(2), .bang, .sparkle]
        for y in 0...2 {
            for closed in [false, true] {
                for overlay in overlays {
                    let cells = Sprite.cells(pet: pet, palette: palette, frame: PetFrame(y: y, eyesClosed: closed, overlay: overlay))
                    #expect(cells.allSatisfy { (0..<Sprite.width).contains($0.x) && (0..<Sprite.height).contains($0.y) })
                }
            }
        }
    }

    @Test(arguments: PetKind.allCases)
    func blinkHidesEyes(pet: PetKind) {
        let palette = PetPalette(seed: 11, pet: pet)
        let open = Sprite.cells(pet: pet, palette: palette, frame: PetFrame())
        let closed = Sprite.cells(pet: pet, palette: palette, frame: PetFrame(eyesClosed: true))
        #expect(open.contains { $0.color == palette.eye })
        #expect(!closed.contains { $0.color == palette.eye })
        #expect(open.count == closed.count)
    }

    @Test func overlaysDrawBesideThePet() {
        let palette = PetPalette(seed: 1, pet: .cat)
        let base = Sprite.cells(pet: .cat, palette: palette, frame: PetFrame()).count
        let withHeart = Sprite.cells(pet: .cat, palette: palette, frame: PetFrame(overlay: .heart))
        #expect(withHeart.count > base)
        #expect(withHeart.dropFirst(base).allSatisfy { $0.x >= 16 })
    }

    @Test func eggIsWellFormed() {
        let grid = PetKind.eggGrid
        #expect(grid.count == 16 && grid.allSatisfy { $0.count == 16 })
        #expect(grid.allSatisfy { $0 == Array($0.reversed()) })
        #expect(grid.allSatisfy { row in row.allSatisfy { ".osb".contains($0) } })
    }

    @Test func eggCracksAndWobblesOnCanvas() {
        let palette = PetPalette(seed: 5, pet: .cat)
        for crack in 0..<Sprite.eggCracks.count {
            for wobble in -1...1 {
                let cells = Sprite.eggCells(palette: palette, wobble: wobble, crack: crack)
                #expect(cells.allSatisfy { (0..<Sprite.width).contains($0.x) && (0..<Sprite.height).contains($0.y) })
            }
        }
        // Every crack pixel lands on the shell, so each stage shows more outline and the same shape.
        let outline = { (crack: Int) in Sprite.eggCells(palette: palette, crack: crack).filter { $0.color == palette.outline }.count }
        #expect(outline(0) < outline(1) && outline(1) < outline(2))
        #expect(Sprite.eggCells(palette: palette, crack: 2).count == Sprite.eggCells(palette: palette).count)
    }

    @Test func eggSpotsHintAtThePet() {
        let palette = PetPalette(seed: 9, pet: .frog)
        #expect(Sprite.eggCells(palette: palette).contains { $0.color == palette.body })
    }

    @Test @MainActor func menuBarImageSize() {
        let image = Sprite.menuBarImage(pet: .frog, palette: PetPalette(seed: 3, pet: .frog), frame: PetFrame())
        #expect(image.size == NSSize(width: Sprite.width, height: Sprite.height))
        #expect(!image.isTemplate, "colored sprites must not be tinted by the menu bar")
    }
}

@Suite("Pixel font")
struct PixelFontTests {
    @Test func glyphsAreRectangular() {
        for (char, rows) in PixelFont.glyphs {
            #expect(rows.count == PixelFont.height, "\(char)")
            #expect(Set(rows.map(\.count)).count == 1, "\(char) has ragged rows")
            #expect(rows.allSatisfy { $0.allSatisfy { ".x".contains($0) } }, "\(char)")
        }
    }

    /// Every string the UI draws in pixel text must have real glyphs, not the "?" fallback.
    @Test func uiStringsHaveGlyphs() {
        var strings = [
            "SETTINGS", "PET", "COLORS", "MODEL", "HOTKEY", "CLAUDE", "SYSTEM", "QUIT", "SAVE", "REROLL",
            "STOPPED", "THINKING...", "COPY", "COPIED", "CLIPBOARD", "ASK ME ANYTHING", "CODE",
            "SETUP", "SKIP", "NEXT", "HATCH", "IT'S HATCHING!", "SOMETHING IS INSIDE...", "COPY SHARE CARD", "CARD COPIED",
            "CONNECT CLAUDE", "CHECKING...", "INSTALL IN TERMINAL", "SIGN IN IN TERMINAL", "YOU'RE CONNECTED!",
            "SUMMON ME ANYWHERE", "TRY IT NOW", "GOT IT!", "ALL SET!", "START ASKING", "SKIP FOR NOW",
            "HATCHED IN KIBBIT", "RUN SETUP AGAIN", "I'M HIDDEN IN YOUR MENU BAR", "MOVE ME",
            "bash", "zsh", "sh", "swift", "python", "js", "ts", "json", "yaml", "go", "rust", "sql", "c++", "objective-c",
        ]
        strings += PetKind.allCases.map(\.displayName)
        strings += [Rarity.common, .rare, .legendary].map(\.label)
        for model in ClaudeModel.allCases {
            strings += ["THINKING", "TYPING", "ZZZ", "OOPS", "READY"].map { "\(model.label) · \($0)" }
        }
        strings += (0..<50).map { _ in PetPalette.seedCode(PetPalette.randomSeed()) }

        for string in strings {
            for char in string {
                #expect(PixelFont.glyphs[Character(char.uppercased())] != nil, "missing glyph '\(char)' in \"\(string)\"")
            }
        }
    }

    @Test func widthAddsOnePixelGaps() {
        #expect(PixelFont.width(of: "") == 0)
        #expect(PixelFont.width(of: "A") == 3)
        #expect(PixelFont.width(of: "AA") == 7)
        #expect(PixelFont.width(of: "M") == 5)
    }
}
