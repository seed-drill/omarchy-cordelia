// The app icon, drawn at build time from the mark the menu bar shows
// (Mark.swift), in the colours of seeddrill.ai:
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
    // The site's card and page backgrounds (#131e28 over #0a1118), and its accent (#1DD3B0).
    let top = NSColor(srgbRed: 0x13 / 255.0, green: 0x1e / 255.0, blue: 0x28 / 255.0, alpha: 1)
    let bottom = NSColor(srgbRed: 0x0a / 255.0, green: 0x11 / 255.0, blue: 0x18 / 255.0, alpha: 1)
    NSGradient(starting: top, ending: bottom)?.draw(in: shape, angle: -90)

    // The mark in the middle 80% of the tile.
    let box = tile.width * 0.8
    NSColor(srgbRed: 0x1d / 255.0, green: 0xd3 / 255.0, blue: 0xb0 / 255.0, alpha: 1).setStroke()
    strokeCordeliaMark(in: NSRect(x: tile.midX - box / 2, y: tile.midY - box / 2, width: box, height: box))
}
