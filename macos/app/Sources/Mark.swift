// The Cordelia mark: a brain seen from above, in the stroke of the Seed Drill
// chevrons. It is our own drawing, the one in assets/cordelia-mark.svg.
//
// Apple's terms keep SF Symbols, and images confusingly like them, out of app
// icons and logos. So the app icon is drawn from this, and the menu bar shows
// the same mark where the Omarchy panel shows its brain.

import AppKit

/// The name the menu tree gives this mark, beside the SF Symbol names.
let MARK = "cordelia"

// The shape on a 32-unit grid with y running down, as the SVG has it: eight
// arcs for the outline (four lobes a side), a line for the fissure, and two
// folds a side that curl inwards from where the lobes meet.
private let GRID: CGFloat = 32
private let STROKE: CGFloat = 2.5

private struct Lobe {
    let centre: CGPoint
    let radius: CGFloat
    let from, to: CGPoint
}

/// Clockwise from the notch at the top: down the right side, up the left.
private let OUTLINE: [Lobe] = [
    Lobe(centre: CGPoint(x: 20.4, y: 8.6), radius: 4.9,
         from: CGPoint(x: 16, y: 6.444), to: CGPoint(x: 25.297, y: 8.766)),
    Lobe(centre: CGPoint(x: 24.1, y: 13), radius: 4.4,
         from: CGPoint(x: 25.297, y: 8.766), to: CGPoint(x: 27.01, y: 16.3)),
    Lobe(centre: CGPoint(x: 24.1, y: 19.6), radius: 4.4,
         from: CGPoint(x: 27.01, y: 16.3), to: CGPoint(x: 25.3, y: 23.833)),
    Lobe(centre: CGPoint(x: 20.4, y: 23.8), radius: 4.9,
         from: CGPoint(x: 25.3, y: 23.833), to: CGPoint(x: 16, y: 25.956)),
    Lobe(centre: CGPoint(x: 11.6, y: 23.8), radius: 4.9,
         from: CGPoint(x: 16, y: 25.956), to: CGPoint(x: 6.7, y: 23.833)),
    Lobe(centre: CGPoint(x: 7.9, y: 19.6), radius: 4.4,
         from: CGPoint(x: 6.7, y: 23.833), to: CGPoint(x: 4.99, y: 16.3)),
    Lobe(centre: CGPoint(x: 7.9, y: 13), radius: 4.4,
         from: CGPoint(x: 4.99, y: 16.3), to: CGPoint(x: 6.703, y: 8.766)),
    Lobe(centre: CGPoint(x: 11.6, y: 8.6), radius: 4.9,
         from: CGPoint(x: 6.703, y: 8.766), to: CGPoint(x: 16, y: 6.444)),
]

private let FISSURE = (CGPoint(x: 16, y: 6.444), CGPoint(x: 16, y: 25.956))

/// The folds of the left side, as cubic curves: start, two controls, end. The
/// right side is their mirror image.
private let FOLDS: [[CGPoint]] = [
    [CGPoint(x: 6.703, y: 8.766), CGPoint(x: 8.2, y: 9.8), CGPoint(x: 10.6, y: 10.2), CGPoint(x: 10.9, y: 12.6)],
    [CGPoint(x: 4.99, y: 16.3), CGPoint(x: 7, y: 16.4), CGPoint(x: 9.4, y: 16.6), CGPoint(x: 10.2, y: 18.9)],
]

/// Strokes the mark into `rect`, in the stroke colour that is set. `weight` is
/// the line's width on the 32-unit grid.
func strokeCordeliaMark(in rect: NSRect, weight: CGFloat = STROKE) {
    let scale = min(rect.width, rect.height) / GRID
    // A grid point in the view: the grid's y runs down, AppKit's runs up.
    func place(_ g: CGPoint) -> NSPoint {
        NSPoint(x: rect.minX + g.x * scale, y: rect.maxY - g.y * scale)
    }
    func mirror(_ g: CGPoint) -> CGPoint { CGPoint(x: GRID - g.x, y: g.y) }
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
    path.move(to: place(FISSURE.0))
    path.line(to: place(FISSURE.1))
    for fold in FOLDS {
        for side in [fold, fold.map(mirror)] {
            path.move(to: place(side[0]))
            path.curve(to: place(side[3]), controlPoint1: place(side[1]), controlPoint2: place(side[2]))
        }
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
