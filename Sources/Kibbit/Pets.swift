import Foundation

/// Pixel keys used in sprite grids:
/// `.` empty · `o` outline · `b` body · `s` secondary · `a` accent · `e` eye · `w` white
enum PetKind: String, CaseIterable, Identifiable, Codable {
    case cat, dog, bunny, frog, penguin, ghost, axolotl

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cat: "Cat"
        case .dog: "Dog"
        case .bunny: "Bunny"
        case .frog: "Frog"
        case .penguin: "Penguin"
        case .ghost: "Ghost"
        case .axolotl: "Axolotl"
        }
    }

    var saturation: ClosedRange<Double> {
        switch self {
        case .ghost: 0.08...0.3
        case .penguin: 0.35...0.7
        default: 0.4...0.8
        }
    }

    var brightness: ClosedRange<Double> {
        switch self {
        case .ghost: 0.9...1.0
        case .penguin: 0.3...0.55
        default: 0.7...0.95
        }
    }

    var grid: [[Character]] { Self.grids[self]! }

    private static let grids: [PetKind: [[Character]]] = [
        .cat: mirrored([
            "........",
            ".o......",
            ".oo.....",
            ".oso....",
            ".ossoooo",
            "obbbbbbb",
            "obbbbbbb",
            "obbeebbb",
            "obbeebbb",
            "obabbbba",
            ".obbbbbo",
            "..oooooo",
            "..obbbbb",
            "..obssss",
            "..obssss",
            "..ooooo.",
        ]),
        .dog: mirrored([
            "........",
            "........",
            "...ooooo",
            "..obbbbb",
            ".oobbbbb",
            "ossobbbb",
            "ossobebb",
            "ossobebb",
            "ossobbss",
            ".oo.obsa",
            "....obso",
            "....oooo",
            "...obbbb",
            "...obsss",
            "...obsss",
            "...oooo.",
        ]),
        .bunny: mirrored([
            "..oo....",
            ".obso...",
            ".obso...",
            ".obso...",
            ".obso...",
            "..oboooo",
            ".obbbbbb",
            "obbbbbbb",
            "obbeebbb",
            "obbeebbb",
            "obabbbsa",
            ".obbbbbo",
            "..oooooo",
            "..obbsss",
            "..obbsss",
            "..ooooo.",
        ]),
        .frog: mirrored([
            "........",
            "........",
            "........",
            ".oooo...",
            "obwweo..",
            "obweeooo",
            "obbbbbbb",
            "obbbbbbb",
            "obabbbbb",
            "obbooooo",
            ".obbbbbb",
            "..oooooo",
            ".obbssss",
            "obbbssss",
            "obbbssss",
            ".oooooo.",
        ]),
        .penguin: mirrored([
            "........",
            "....oooo",
            "...obbbb",
            "..obbbbb",
            "..obssss",
            ".obsesss",
            ".obsessa",
            ".obsssaa",
            "obbsssss",
            "obbsssss",
            "obbsssss",
            "obbsssss",
            ".obsssss",
            "..obssss",
            "...ooooo",
            "..aaa...",
        ]),
        .ghost: mirrored([
            "........",
            "....oooo",
            "...obbbb",
            "..obbbbb",
            ".obbbbbb",
            ".obbbbbb",
            "obbeebbb",
            "obbeebbb",
            "obabbbbb",
            "obbbbboo",
            "obbbbboo",
            "obbbbbbb",
            "obbbbbbb",
            "obbbbbbb",
            "obbobbbo",
            "o..o.oo.",
        ]),
        .axolotl: mirrored([
            "........",
            "........",
            "........",
            "a...oooo",
            ".a.obbbb",
            "aaobbbbb",
            "..obbbbb",
            "aaobebbb",
            "..obebbb",
            ".aobbbbb",
            "a.oabboo",
            "...obbbb",
            "...ooooo",
            "...obsss",
            "...obsss",
            "...oooo.",
        ]),
    ]

    /// Sprites are front-facing and symmetric, so each one is authored as its left half.
    private static func mirrored(_ half: [String]) -> [[Character]] {
        half.map { Array($0) + Array($0).reversed() }
    }
}

extension PetKind {
    /// Shown before hatching. `s` shell, `b` spots in the pet's body color, so the egg hints at what's inside.
    static let eggGrid: [[Character]] = mirrored([
        "........",
        "........",
        "......oo",
        ".....oss",
        "....osss",
        "....osbb",
        "...osssb",
        "...ossss",
        "..obbsss",
        "..obbsss",
        "..ossssb",
        "..osssbb",
        "..osssss",
        "...ossss",
        "....oooo",
        "........",
    ])
}
