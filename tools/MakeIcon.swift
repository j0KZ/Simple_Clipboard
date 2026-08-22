// Genera el icono de la app sin recursos externos.
// Uso: swift tools/MakeIcon.swift <carpeta-destino>
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let sizes = [16, 32, 64, 128, 256, 512, 1024]

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let body = rect.insetBy(dx: size * 0.06, dy: size * 0.06)
    let squircle = NSBezierPath(roundedRect: body, xRadius: size * 0.22, yRadius: size * 0.22)

    NSGraphicsContext.current!.cgContext.saveGState()
    squircle.addClip()
    NSGradient(colors: [NSColor(calibratedRed: 0.20, green: 0.52, blue: 0.96, alpha: 1),
                        NSColor(calibratedRed: 0.10, green: 0.31, blue: 0.78, alpha: 1)])!
        .draw(in: body, angle: -90)

    // Pila de tarjetas: el historial.
    let cardW = body.width * 0.50
    let cardH = body.height * 0.40
    let step = body.height * 0.085
    for i in (0..<3).reversed() {
        let alpha = [1.0, 0.55, 0.3][i]
        let inset = CGFloat(i) * body.width * 0.035
        let card = CGRect(x: body.midX - cardW / 2 + inset,
                          y: body.midY - cardH / 2 - step + CGFloat(i) * step,
                          width: cardW - inset * 2, height: cardH)
        NSColor(calibratedWhite: 1, alpha: alpha).setFill()
        NSBezierPath(roundedRect: card, xRadius: size * 0.035, yRadius: size * 0.035).fill()

        // Renglones en la tarjeta de adelante.
        if i == 0 {
            NSColor(calibratedRed: 0.15, green: 0.35, blue: 0.75, alpha: 0.5).setFill()
            let lineH = card.height * 0.09
            for j in 0..<3 {
                let w = card.width * [0.66, 0.78, 0.44][j]
                let y = card.maxY - card.height * (0.28 + Double(j) * 0.22)
                NSBezierPath(roundedRect: CGRect(x: card.minX + card.width * 0.11, y: y,
                                                 width: w, height: lineH),
                             xRadius: lineH / 2, yRadius: lineH / 2).fill()
            }
        }
    }
    NSGraphicsContext.current!.cgContext.restoreGState()

    NSColor(calibratedWhite: 1, alpha: 0.16).setStroke()
    squircle.lineWidth = max(1, size * 0.006)
    squircle.stroke()
    image.unlockFocus()
    return image
}

for size in sizes {
    let img = drawIcon(size: CGFloat(size))
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    let name = size == 1024 ? "icon_512x512@2x.png" : "icon_\(size)x\(size).png"
    try? png.write(to: URL(fileURLWithPath: outDir + "/" + name))
    if size >= 32 {
        try? png.write(to: URL(fileURLWithPath: outDir + "/icon_\(size / 2)x\(size / 2)@2x.png"))
    }
}
print("iconos generados en \(outDir)")
