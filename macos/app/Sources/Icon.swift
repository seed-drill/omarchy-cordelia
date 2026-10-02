// The app icon, drawn at build time from the same symbol the menu bar shows:
// `Cordelia --make-iconset <dir>`, then iconutil turns the folder into .icns.

import AppKit

func makeIconset(_ dir: String) -> Bool {
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    // (points, scale): the ten files an .iconset holds.
    let sizes: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
    for (points, scale) in sizes {
        let px = points * scale
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return false }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        drawIcon(size: CGFloat(px))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        guard FileManager.default.createFile(atPath: dir + "/" + name, contents: png) else { return false }
    }
    return true
}

private func drawIcon(size: CGFloat) {
    // The rounded square of a Mac app icon, inset as the system grid insets it.
    let inset = size * 0.1
    let tile = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let shape = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    let top = NSColor(calibratedRed: 0.22, green: 0.26, blue: 0.36, alpha: 1)
    let bottom = NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.18, alpha: 1)
    NSGradient(starting: top, ending: bottom)?.draw(in: shape, angle: -90)

    let config = NSImage.SymbolConfiguration(pointSize: tile.width * 0.6, weight: .medium)
    guard let symbol = NSImage(systemSymbolName: "brain", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) else { return }
    let white = NSImage(size: symbol.size, flipped: false) { rect in
        symbol.draw(in: rect)
        NSColor.white.set()
        rect.fill(using: .sourceAtop)
        return true
    }
    // Fit the symbol into the middle 74% of the tile, keeping its shape.
    let box = tile.width * 0.74
    let scale = min(box / symbol.size.width, box / symbol.size.height)
    let w = symbol.size.width * scale, h = symbol.size.height * scale
    white.draw(in: NSRect(x: tile.midX - w / 2, y: tile.midY - h / 2, width: w, height: h))
}
