import AppKit
import Foundation
// Рисуем собственный простой знак средствами AppKit, без внешних изображений.
let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for base in [16,32,128,256,512] {
    for scale in [1,2] {
        let size = base * scale
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(size)/1024, y: CGFloat(size)/1024)
        NSColor(calibratedWhite: 0.16, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 50,y: 50,width: 924,height: 924), xRadius: 205,yRadius: 205).fill()
        let line = NSBezierPath();line.lineWidth=65;line.lineCapStyle = .round;line.lineJoinStyle = .round
        let points: [NSPoint] = [.init(x:225,y:500),.init(x:360,y:500),.init(x:435,y:690),.init(x:565,y:320),.init(x:640,y:500),.init(x:800,y:500)]
        line.move(to: points[0]);for p in points.dropFirst(){line.line(to:p)}
        NSColor(calibratedRed:0.44,green:0.79,blue:0.71,alpha:1).setStroke();line.stroke()
        image.unlockFocus()
        let representation=NSBitmapImageRep(data:image.tiffRepresentation!)!
        let name="icon_\(base)x\(base)"+(scale==2 ? "@2x" : "")+".png"
        try representation.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent(name))
    }
}
