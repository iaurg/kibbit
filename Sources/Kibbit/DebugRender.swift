import AppKit

/// Offline rendering used by the build script (app icon) and for eyeballing sprite art.
enum DebugRender {
    static func gallery(to path: String) {
        let seeds: [UInt64] = [1, 42, 1337, 9001, 0xC0FFEE, 0xBADA55]
        let frames = [PetFrame(), PetFrame(y: 2, eyesClosed: true, overlay: .zzz(0)), PetFrame(y: 0, overlay: .heart), PetFrame(overlay: .dots(3))]
        let pixel: CGFloat = 8
        let cellW = CGFloat(Sprite.width) * pixel + 8
        let cellH = CGFloat(Sprite.height) * pixel + 8
        let cols = seeds.count + frames.count - 1
        let size = CGSize(width: cellW * CGFloat(cols), height: cellH * CGFloat(PetKind.allCases.count))
        write(size: size, to: path) { ctx in
            ctx.setFillColor(CGColor(srgbRed: 0.12, green: 0.11, blue: 0.18, alpha: 1))
            ctx.fill(CGRect(origin: .zero, size: size))
            for (row, pet) in PetKind.allCases.enumerated() {
                var col = 0
                for seed in seeds {
                    let cells = Sprite.cells(pet: pet, palette: PetPalette(seed: seed, pet: pet), frame: PetFrame())
                    Sprite.draw(cells, in: ctx, pixel: pixel, originX: CGFloat(col) * cellW + 4, originY: CGFloat(row) * cellH + 4)
                    col += 1
                }
                for frame in frames.dropFirst() {
                    let cells = Sprite.cells(pet: pet, palette: PetPalette(seed: seeds[1], pet: pet), frame: frame)
                    Sprite.draw(cells, in: ctx, pixel: pixel, originX: CGFloat(col) * cellW + 4, originY: CGFloat(row) * cellH + 4)
                    col += 1
                }
            }
        }
    }

    /// Writes the PNG sizes `iconutil` expects for an .iconset folder.
    static func iconset(to dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let palette = PetPalette(seed: 42, pet: .cat)
        let cells = Sprite.cells(pet: .cat, palette: palette, frame: PetFrame(y: 0))
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let px = base * scale
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                let size = CGSize(width: px, height: px)
                write(size: size, to: dir + "/" + name) { ctx in
                    let inset = CGFloat(px) * 0.1
                    let bg = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
                    ctx.setFillColor(CGColor(srgbRed: 0.16, green: 0.15, blue: 0.25, alpha: 1))
                    ctx.addPath(CGPath(roundedRect: bg, cornerWidth: bg.width * 0.22, cornerHeight: bg.width * 0.22, transform: nil))
                    ctx.fillPath()
                    let pixel = bg.width * 0.8 / 16
                    let origin = bg.midX - pixel * 8
                    Sprite.draw(cells, in: ctx, pixel: pixel, originX: origin, originY: bg.midY - pixel * 8)
                }
            }
        }
    }

    private static func write(size: CGSize, to path: String, draw: (CGContext) -> Void) {
        let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Flip so row 0 of a sprite is the top, matching the grids.
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        draw(ctx)
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
