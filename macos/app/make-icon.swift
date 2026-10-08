// Draws the Diskwatch app icon (1024×1024 PNG): a disk-usage sunburst on a
// macOS-style rounded square. Usage: swift make-icon.swift out.png
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let space = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
                          bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

// Background: Apple icon grid keeps ~10% margin; continuous-corner rounded rect.
let inset: CGFloat = 100
let tile = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: rgb(0x000000, 0.35))
ctx.addPath(tilePath); ctx.setFillColor(rgb(0x0B1530)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath); ctx.clip()
let bg = CGGradient(colorsSpace: space, colors: [rgb(0x18284F), rgb(0x0A1226)] as CFArray,
                    locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
ctx.restoreGState()

// Sunburst: inner ring = top-level folders, outer ring = their largest children.
let center = CGPoint(x: size / 2, y: size / 2)
func arc(_ r0: CGFloat, _ r1: CGFloat, _ a0: CGFloat, _ a1: CGFloat, _ color: CGColor) {
    let gap: CGFloat = 0.018   // radians between segments
    let s = a0 + gap / 2, e = a1 - gap / 2
    guard e > s else { return }
    let p = CGMutablePath()
    p.addArc(center: center, radius: r1, startAngle: s, endAngle: e, clockwise: false)
    p.addArc(center: center, radius: r0, startAngle: e, endAngle: s, clockwise: true)
    p.closeSubpath()
    ctx.addPath(p); ctx.setFillColor(color); ctx.fillPath()
}

let start = CGFloat.pi / 2   // 12 o'clock, drawing counter-clockwise
let tau = 2 * CGFloat.pi
// (fraction of disk, color, children as fractions of the parent)
let groups: [(CGFloat, UInt32, [CGFloat])] = [
    (0.42, 0x4F8DF7, [0.45, 0.30, 0.15]),   // blue: biggest folder
    (0.22, 0x34C3A0, [0.55, 0.30]),         // teal
    (0.14, 0xF2B544, [0.60, 0.25]),         // amber
    (0.09, 0xEF6B73, [0.70]),               // coral
    (0.06, 0xA685F2, []),                   // violet
]
var a = start
for (frac, color, kids) in groups {
    let span = frac * tau
    arc(150, 282, a, a + span, rgb(color))
    var k = a
    for kf in kids {
        let ks = span * kf
        arc(290, 370, k, k + ks, rgb(color, 0.72))
        k += ks
    }
    a += span
}
// Remaining 7%: free space, a faint track.
arc(150, 282, a, start + tau, rgb(0xFFFFFF, 0.10))

// Center: a glossy "watch" dot.
let hub = CGRect(x: center.x - 108, y: center.y - 108, width: 216, height: 216)
ctx.addEllipse(in: hub); ctx.setFillColor(rgb(0x0B1530)); ctx.fillPath()
let dot = CGRect(x: center.x - 62, y: center.y - 62, width: 124, height: 124)
ctx.saveGState()
ctx.addEllipse(in: dot); ctx.clip()
let g = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF), rgb(0xB9CCF5)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(g, startCenter: CGPoint(x: center.x - 22, y: center.y + 22), startRadius: 4,
                       endCenter: center, endRadius: 62, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
ctx.restoreGState()

guard let image = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: image)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
