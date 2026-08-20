import AppKit

// Builds every form of the mark from the supplied artwork:
//   AppIcon.iconset          — dark plate, on Apple's icon grid
//   HootMark-Template.png    — menu bar glyph, alpha-masked
//   HootMark-Black/White.png — branding surfaces

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
guard let dark = NSImage(contentsOf: root.appending(path: "woot-logo-bw-on-dark.png")),
      let light = NSImage(contentsOf: root.appending(path: "woot-logo-bw-on-light.png"))
else { fatalError("missing source artwork next to Package.swift") }

/// Draws an image into a known RGBA buffer. Reading pixels straight out of an
/// arbitrary PNG's colorspace fails, loudly and then silently.
func rgbaBuffer(_ image: NSImage, side: Int) -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: side * side * 4)
    pixels.withUnsafeMutableBytes { raw in
        guard let context = CGContext(
            data: raw.baseAddress, width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
    }
    return pixels
}

/// Separates the glyph from its plate and returns it as a tinted, tightly
/// cropped image. The ink is whatever contrasts with the background.
func glyph(from image: NSImage, tint: NSColor) -> CGImage {
    let side = Int(max(image.size.width, image.size.height))
    let source = rgbaBuffer(image, side: side)

    var alpha = [Double](repeating: 0, count: side * side)
    var minX = side, minY = side, maxX = 0, maxY = 0

    // The artwork's plate has a faint border stroke; ignore a margin so the
    // frame isn't mistaken for part of the glyph.
    let margin = Int(Double(side) * 0.08)

    for y in margin..<(side - margin) {
        for x in margin..<(side - margin) {
            let o = (y * side + x) * 4
            let luma = (0.299 * Double(source[o]) + 0.587 * Double(source[o + 1])
                        + 0.114 * Double(source[o + 2])) / 255
            // Dark ink on a light plate.
            let ink = 1 - luma
            guard ink > 0.45 else { continue }
            alpha[y * side + x] = ink
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard maxX > minX else { fatalError("no glyph found in artwork") }

    let pad = 2
    let x0 = max(0, minX - pad), y0 = max(0, minY - pad)
    let w = min(side - x0, maxX - minX + pad * 2)
    let h = min(side - y0, maxY - minY + pad * 2)

    let tintColor = tint.usingColorSpace(.deviceRGB) ?? .black
    let tr = tintColor.redComponent, tg = tintColor.greenComponent, tb = tintColor.blueComponent

    var out = [UInt8](repeating: 0, count: w * h * 4)
    for y in 0..<h {
        for x in 0..<w {
            let a = alpha[(y + y0) * side + (x + x0)]
            let o = (y * w + x) * 4
            // Premultiplied: colour is already scaled by coverage.
            out[o] = UInt8(tr * a * 255)
            out[o + 1] = UInt8(tg * a * 255)
            out[o + 2] = UInt8(tb * a * 255)
            out[o + 3] = UInt8(a * 255)
        }
    }

    return out.withUnsafeMutableBytes { raw -> CGImage in
        let context = CGContext(
            data: raw.baseAddress, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }
}

func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let resources = root.appending(path: "Sources/Hoot/Resources")
writePNG(glyph(from: light, tint: .black), to: resources.appending(path: "HootMark-Template.png"))
writePNG(glyph(from: light, tint: .black), to: resources.appending(path: "HootMark-Black.png"))
writePNG(glyph(from: light, tint: .white), to: resources.appending(path: "HootMark-White.png"))

// App icon: the supplied dark plate, clipped to Apple's rounded-rect grid.
func iconImage(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let scale = size / 1024
    let inset = 100 * scale
    let plate = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    NSBezierPath(roundedRect: plate, xRadius: 185 * scale, yRadius: 185 * scale).setClip()
    dark.draw(in: plate)
    image.unlockFocus()
    return image
}

let iconset = root.appending(path: "Packaging/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for (suffix, px) in [("", base), ("@2x", base * 2)] {
        let img = iconImage(size: CGFloat(px))
        let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
        try! rep.representation(using: .png, properties: [:])!
            .write(to: iconset.appending(path: "icon_\(base)x\(base)\(suffix).png"))
    }
}
print("icon + marks generated")
