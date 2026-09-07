import AppKit
import Foundation

// Рисуем иконку MacPulse в стиле системной геометрической сетки.
let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = base * scale
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        guard let context = NSGraphicsContext.current?.cgContext else { continue }
        context.setShouldAntialias(true)
        let factor = CGFloat(size) / 1024
        context.scaleBy(x: factor, y: factor)

        NSColor(calibratedRed: 0.27, green: 0.32, blue: 0.35, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()

        let tile = NSRect(x: 145, y: 125, width: 734, height: 774)
        NSColor(calibratedWhite: 0.05, alpha: 0.22).setFill()
        NSBezierPath(roundedRect: tile.offsetBy(dx: 0, dy: -12), xRadius: 142, yRadius: 142).fill()

        NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
        NSBezierPath(roundedRect: tile, xRadius: 142, yRadius: 142).fill()

        let field = tile.insetBy(dx: 25, dy: 25)
        NSColor(calibratedRed: 0.77, green: 0.84, blue: 0.87, alpha: 1).setFill()
        NSBezierPath(roundedRect: field, xRadius: 118, yRadius: 118).fill()

        context.saveGState()
        NSBezierPath(roundedRect: field, xRadius: 118, yRadius: 118).addClip()

        let center = NSPoint(x: 512, y: 512)
        let line = NSBezierPath()
        line.lineWidth = 3
        line.lineCapStyle = .round
        NSColor(calibratedWhite: 1, alpha: 0.43).setStroke()
        for x in stride(from: 205, through: 819, by: 68) {
            line.move(to: NSPoint(x: CGFloat(x), y: 95))
            line.line(to: NSPoint(x: CGFloat(x), y: 929))
        }
        for y in stride(from: 95, through: 929, by: 68) {
            line.move(to: NSPoint(x: 95, y: CGFloat(y)))
            line.line(to: NSPoint(x: 929, y: CGFloat(y)))
        }
        line.stroke()

        NSColor(calibratedWhite: 1, alpha: 0.48).setStroke()
        for radius in [100.0, 205.0, 310.0, 415.0] {
            NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).stroke()
        }
        for width in [170.0, 330.0, 500.0] {
            NSBezierPath(ovalIn: NSRect(x: center.x - width / 2, y: center.y - 415, width: width, height: 830)).stroke()
            NSBezierPath(ovalIn: NSRect(x: center.x - 415, y: center.y - width / 2, width: 830, height: width)).stroke()
        }

        let diagonals = NSBezierPath()
        diagonals.lineWidth = 3
        diagonals.move(to: NSPoint(x: 95, y: 95)); diagonals.line(to: NSPoint(x: 929, y: 929))
        diagonals.move(to: NSPoint(x: 95, y: 929)); diagonals.line(to: NSPoint(x: 929, y: 95))
        diagonals.stroke()
        context.restoreGState()

        NSColor.white.withAlphaComponent(0.7).setStroke()
        let border = NSBezierPath(roundedRect: tile.insetBy(dx: 7, dy: 7), xRadius: 136, yRadius: 136)
        border.lineWidth = 5
        border.stroke()

        image.unlockFocus()
        guard let representation = NSBitmapImageRep(data: image.tiffRepresentation!) else { continue }
        let name = "icon_\(base)x\(base)" + (scale == 2 ? "@2x" : "") + ".png"
        try representation.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
    }
}
