import AppKit
import SwiftUI

struct RGB: Equatable {
    var r, g, b: Double

    static func hsb(_ h: Double, _ s: Double, _ v: Double) -> RGB {
        let h = (h.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 6
        let c = v * s
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c
        let (r, g, b): (Double, Double, Double) = switch Int(h) {
        case 0: (c, x, 0)
        case 1: (x, c, 0)
        case 2: (0, c, x)
        case 3: (0, x, c)
        case 4: (x, 0, c)
        default: (c, 0, x)
        }
        return RGB(r: r + m, g: g + m, b: b + m)
    }

    var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }
    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }
}

/// SplitMix64: tiny, fast and fully deterministic, so a seed always yields the same pet.
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }

    mutating func pick(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + unit() * (range.upperBound - range.lowerBound)
    }
}

enum Rarity: String {
    case common, rare, legendary

    var label: String { rawValue.uppercased() }
}

struct PetPalette: Equatable {
    let body, secondary, accent, outline, eye, white: RGB
    let rarity: Rarity

    init(seed: UInt64, pet: PetKind) {
        var rng = SeededRNG(state: seed)
        let roll = rng.unit()
        rarity = roll < 0.03 ? .legendary : roll < 0.18 ? .rare : .common

        let hue = rng.unit()
        let sat = rng.pick(pet.saturation)
        let bri = rng.pick(pet.brightness)
        body = .hsb(hue, sat, bri)

        switch rarity {
        case .common where pet == .penguin:
            secondary = .hsb(hue, 0.06, 0.97)
        case .common:
            secondary = .hsb(hue, sat * 0.3, min(1, bri + 0.25))
        case .rare, .legendary:
            secondary = .hsb(hue + 0.5, 0.35, 0.97)
        }

        if rarity == .legendary {
            accent = .hsb(0.13, 0.75, 1)
            outline = .hsb(0.75, 0.7, 0.25)
        } else {
            accent = .hsb(rng.unit(), rng.pick(0.45...0.7), 0.98)
            outline = .hsb(hue, min(1, sat + 0.25), 0.2)
        }
        eye = .hsb(hue, 0.35, 0.1)
        white = RGB(r: 1, g: 1, b: 1)
    }

    func color(for key: Character) -> RGB? {
        switch key {
        case "o": outline
        case "b": body
        case "s": secondary
        case "a": accent
        case "e": eye
        case "w": white
        default: nil
        }
    }

    static func randomSeed() -> UInt64 { UInt64(UInt32.random(in: .min ... .max)) }

    static func seedCode(_ seed: UInt64) -> String {
        let hex = String(format: "%08llX", seed & 0xFFFF_FFFF)
        return "#" + hex.prefix(4) + "-" + hex.dropFirst(4).prefix(4)
    }
}
