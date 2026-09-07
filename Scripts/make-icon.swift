import AppKit
import Foundation

// Рисуем самостоятельную тёмную иконку MacPulse с импульсным знаком.
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

        let tile = NSRect(x: 70, y: 70, width: 884, height: 884)
        let tilePath = NSBezierPath(roundedRect: tile, xRadius: 222, yRadius: 222)
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
            NSColor(calibratedRed: 0.035, green: 0.055, blue: 0.12, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.08, green: 0.16, blue: 0.25, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.025, green: 0.10, blue: 0.16, alpha: 1).cgColor
        ] as CFArray, locations: [0, 0.55, 1])!
        context.saveGState()
        tilePath.addClip()
        context.drawLinearGradient(gradient, start: CGPoint(x: 80, y: 960), end: CGPoint(x: 960, y: 80), options: [])

        let center = NSPoint(x: 512, y: 512)
        NSColor(calibratedRed: 0.10, green: 0.48, blue: 0.55, alpha: 0.20).setStroke()
        for radius in [190.0, 300.0, 410.0] {
            let orbit = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius * 0.60, width: radius * 2, height: radius * 1.20))
            orbit.lineWidth = 5
            orbit.stroke()
        }
        let pulse = NSBezierPath()
        pulse.move(to: NSPoint(x: 170, y: 512))
        pulse.line(to: NSPoint(x: 330, y: 512))
        pulse.line(to: NSPoint(x: 408, y: 512))
        pulse.line(to: NSPoint(x: 475, y: 690))
        pulse.line(to: NSPoint(x: 565, y: 315))
        pulse.line(to: NSPoint(x: 640, y: 512))
        pulse.line(to: NSPoint(x: 855, y: 512))
        pulse.lineWidth = 58
        pulse.lineCapStyle = .round
        pulse.lineJoinStyle = .round
        NSColor(calibratedRed: 0.05, green: 0.95, blue: 0.86, alpha: 0.20).setStroke()
        let glow = pulse.copy() as! NSBezierPath
        glow.lineWidth = 120
        glow.stroke()
        NSColor(calibratedRed: 0.08, green: 0.95, blue: 0.86, alpha: 1).setStroke()
        pulse.stroke()
        context.restoreGState()

        NSColor(calibratedRed: 0.12, green: 0.62, blue: 0.70, alpha: 0.75).setStroke()
        let border = NSBezierPath(roundedRect: tile.insetBy(dx: 9, dy: 9), xRadius: 212, yRadius: 212)
        border.lineWidth = 6
        border.stroke()

        image.unlockFocus()
        guard let representation = NSBitmapImageRep(data: image.tiffRepresentation!) else { continue }
        let name = "icon_\(base)x\(base)" + (scale == 2 ? "@2x" : "") + ".png"
        try representation.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
    }
}
