// The Cordelia mark: a brain seen from above, in the stroke of the Seed Drill
// chevrons. It is our own drawing, the one in assets/cordelia-mark.svg.
//
// Apple's terms keep SF Symbols, and images confusingly like them, out of app
// icons and logos. So the app icon is drawn from this, and the menu bar shows
// the same mark where the Omarchy panel shows its brain.

import AppKit

/// The name the menu tree gives this mark, beside the SF Symbol names.
let MARK = "cordelia"

// The shape on a 32-unit grid with y running down, as the SVG has it: six
// arcs for the outline, a line for the fissure, four folds.
private let GRID: CGFloat = 32
private let STROKE: CGFloat = 2.5

private struct Lobe {
    let centre: CGPoint
    let radius: CGFloat
    let from, to: CGPoint
}

private let OUTLINE: [Lobe] = [
    Lobe(centre: CGPoint(x: 20.75, y: 9.25), radius: 5.75,
         from: CGPoint(x: 16, y: 6.01), to: CGPoint(x: 25.986, y: 11.626)),
    Lobe(centre: CGPoint(x: 23.5, y: 16.25), radius: 5.25,
         from: CGPoint(x: 25.986, y: 11.626), to: CGPoint(x: 25.867, y: 20.936)),
    Lobe(centre: CGPoint(x: 20.5, y: 23), radius: 5.75,
         from: CGPoint(x: 25.867, y: 20.936), to: CGPoint(x: 16, y: 26.58)),
    Lobe(centre: CGPoint(x: 11.5, y: 23), radius: 5.75,
         from: CGPoint(x: 16, y: 26.58), to: CGPoint(x: 6.133, y: 20.936)),
    Lobe(centre: CGPoint(x: 8.5, y: 16.25), radius: 5.25,
         from: CGPoint(x: 6.133, y: 20.936), to: CGPoint(x: 6.014, y: 11.626)),
    Lobe(centre: CGPoint(x: 11.25, y: 9.25), radius: 5.75,
         from: CGPoint(x: 6.014, y: 11.626), to: CGPoint(x: 16, y: 6.01)),
]

private let LINES: [(CGPoint, CGPoint)] = [
    (CGPoint(x: 16, y: 6.01), CGPoint(x: 16, y: 26.58)),
    (CGPoint(x: 6.014, y: 11.626), CGPoint(x: 10.2, y: 13.2)),
    (CGPoint(x: 25.986, y: 11.626), CGPoint(x: 21.8, y: 13.2)),
    (CGPoint(x: 6.133, y: 20.936), CGPoint(x: 10.2, y: 19.4)),
    (CGPoint(x: 25.867, y: 20.936), CGPoint(x: 21.8, y: 19.4)),
]

/// Strokes the mark into `rect`, in the stroke colour that is set. `weight` is
/// the line's width on the 32-unit grid.
func strokeCordeliaMark(in rect: NSRect, weight: CGFloat = STROKE) {
    let scale = min(rect.width, rect.height) / GRID
    // A grid point in the view: the grid's y runs down, AppKit's runs up.
    func place(_ g: CGPoint) -> NSPoint {
        NSPoint(x: rect.minX + g.x * scale, y: rect.maxY - g.y * scale)
    }
    func angle(_ centre: NSPoint, _ p: NSPoint) -> CGFloat {
        atan2(p.y - centre.y, p.x - centre.x) * 180 / .pi
    }
    let path = NSBezierPath()
    path.lineWidth = weight * scale
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.move(to: place(OUTLINE[0].from))
    for lobe in OUTLINE {
        let centre = place(lobe.centre)
        path.appendArc(withCenter: centre, radius: lobe.radius * scale,
                       startAngle: angle(centre, place(lobe.from)),
                       endAngle: angle(centre, place(lobe.to)), clockwise: true)
    }
    path.close()
    for (a, b) in LINES {
        path.move(to: place(a))
        path.line(to: place(b))
    }
    path.stroke()
}

/// The mark as a menu bar image. It is a template, so the system colours it
/// for a light or a dark bar and dims it when the item is inactive.
func cordeliaMarkImage(points: CGFloat = 18) -> NSImage {
    let image = NSImage(size: NSSize(width: points, height: points), flipped: false) { rect in
        NSColor.black.setStroke()
        // A little heavier than on the grid, to sit with the bar's other icons.
        strokeCordeliaMark(in: rect, weight: 2.75)
        return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "Cordelia"
    return image
}

/// Writes the menu bar image as a PNG at `scale` times its size, black on
/// clear, to look at it (`Cordelia --make-menubar-image FILE`).
func writeMenuBarImage(_ file: String, scale: Int = 8) -> Bool {
    let points: CGFloat = 18
    let px = Int(points) * scale
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: rep) else { return false }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSColor.black.setStroke()
    strokeCordeliaMark(in: NSRect(x: 0, y: 0, width: px, height: px), weight: 2.75)
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { return false }
    return FileManager.default.createFile(atPath: file, contents: png)
}
