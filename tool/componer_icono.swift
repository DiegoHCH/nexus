import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

// Compone el arte del icono sobre un cuadrado opaco, con Core Graphics.
//
// La primera versión usaba `NSImage.draw` y salía el fondo **sin el arte**: en un
// proceso de línea de comandos sin app de AppKit detrás, ese dibujo no pinta nada y
// no avisa. Core Graphics no depende de eso.
let a = CommandLine.arguments
guard a.count == 6, let lado = Int(a[3]), let escala = Double(a[4]),
      let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, nil),
      let arte = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
  FileHandle.standardError.write("no pude leer el arte\n".data(using: .utf8)!); exit(1)
}
func canal(_ i: Int) -> CGFloat {
  let h = a[5]; let s = h.index(h.startIndex, offsetBy: i)
  return CGFloat(Int(h[s...h.index(s, offsetBy: 1)], radix: 16) ?? 0) / 255
}
guard let ctx = CGContext(data: nil, width: lado, height: lado, bitsPerComponent: 8,
                          bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                          // `noneSkipLast`: sin alfa en la salida, que es lo que iOS
                          // exige y lo que evita el borde negro en las esquinas.
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
  FileHandle.standardError.write("no pude crear el lienzo\n".data(using: .utf8)!); exit(1)
}
ctx.setFillColor(red: canal(0), green: canal(2), blue: canal(4), alpha: 1)
ctx.fill(CGRect(x: 0, y: 0, width: lado, height: lado))
let dentro = Double(lado) * escala, margen = (Double(lado) - dentro) / 2
ctx.interpolationQuality = .high
ctx.draw(arte, in: CGRect(x: margen, y: margen, width: dentro, height: dentro))

guard let salida = ctx.makeImage(),
      let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[2]) as CFURL,
                                               UTType.png.identifier as CFString, 1, nil) else {
  FileHandle.standardError.write("no pude escribir\n".data(using: .utf8)!); exit(1)
}
CGImageDestinationAddImage(dst, salida, nil)
guard CGImageDestinationFinalize(dst) else { exit(1) }
