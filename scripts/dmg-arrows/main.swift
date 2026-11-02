// Renders the DMG background's arrows with Impact's own ArrowLayer, so the installer uses the exact
// arrow style of the app. Output: a transparent PNG overlay that generate_dmg_background.py composites.
//
//   dmg-arrows <output.png>
//
// Coordinates are Finder window points (840 x 460, y down), matching build_dmg.sh's icon positions:
// Shots {150, 217}, Impact {370, 217}, Applications {690, 217}. Rendered at 2x for Retina.
import AppKit

let pointSize = CGSize(width: 840, height: 460)
let scale: CGFloat = 2.0
let arrowColor = "#FF3B30"   // Impact's default annotation red
let strokeWidth: CGFloat = 3.0   // Impact's medium-thin width: the arrow guides, the icons stay the focus

let arrows = [
    // Shots → Applications, arching over Impact
    ArrowLayer(start: CGPoint(x: 200, y: 166), control: CGPoint(x: 420, y: 40), end: CGPoint(x: 636, y: 166),
               color: arrowColor, strokeWidth: strokeWidth),
    // Impact → Applications, sweeping underneath
    ArrowLayer(start: CGPoint(x: 418, y: 258), control: CGPoint(x: 530, y: 330), end: CGPoint(x: 634, y: 266),
               color: arrowColor, strokeWidth: strokeWidth),
]

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: dmg-arrows <output.png>\n".data(using: .utf8)!)
    exit(2)
}
let width = Int(pointSize.width * scale), height = Int(pointSize.height * scale)
guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
// y-down points, like Impact's flipped canvas
ctx.translateBy(x: 0, y: CGFloat(height))
ctx.scaleBy(x: scale, y: -scale)
for arrow in arrows { arrow.draw(in: ctx, scale: scale) }

guard let image = ctx.makeImage(),
      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { exit(1) }
do {
    try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
} catch {
    FileHandle.standardError.write("dmg-arrows: \(error.localizedDescription)\n".data(using: .utf8)!)
    exit(1)
}
