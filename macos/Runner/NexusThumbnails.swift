import AppKit
import FlutterMacOS
import Foundation
import QuickLookThumbnailing
import os

/// La miniatura de un archivo, la que enseña el Finder.
///
/// Se pide a QuickLook y no se dibuja aquí un icono por extensión, que es lo
/// barato: para una imagen, un PDF o una presentación, la miniatura **es el
/// contenido** —se reconoce de un vistazo cuál de los tres archivos que acabas
/// de arrastrar era el bueno—, mientras que un icono por extensión los deja a
/// los tres idénticos y no ahorra ni una duda.
///
/// Para lo que QuickLook no sabe representar —código, texto plano, un binario—
/// se cae al icono del sistema, que es exactamente lo que hace el Finder y ya
/// distingue un `.dart` de un `.zip`.
final class NexusThumbnails {
  private static let log = Logger(subsystem: "com.katanalabs.nexus", category: "miniaturas")

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.katanalabs.nexus/thumbnails",
      binaryMessenger: registrar.messenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "thumbnail",
            let args = call.arguments as? [String: Any],
            let path = args["path"] as? String
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      let size = (args["size"] as? NSNumber)?.doubleValue ?? 64
      let scale = (args["scale"] as? NSNumber)?.doubleValue ?? 2
      generate(path: path, size: size, scale: scale, result: result)
    }
    log.info("canal de miniaturas registrado")
  }

  private static func generate(
    path: String,
    size: Double,
    scale: Double,
    result: @escaping FlutterResult
  ) {
    let url = URL(fileURLWithPath: path)
    let request = QLThumbnailGenerator.Request(
      fileAt: url,
      size: CGSize(width: size, height: size),
      scale: CGFloat(scale),
      // `.all` y no solo la miniatura de verdad: si el archivo no tiene una,
      // que devuelva el icono decorado antes que nada. Quedarse sin imagen es
      // el único resultado inservible.
      representationTypes: .all
    )

    QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, error in
      // Al hilo principal: el canal de Flutter no se puede tocar desde el hilo
      // en el que QuickLook responde.
      DispatchQueue.main.async {
        if let image = thumbnail?.nsImage, let png = png(from: image) {
          result(FlutterStandardTypedData(bytes: png))
          return
        }
        if let error {
          log.debug("sin miniatura · \(error.localizedDescription, privacy: .public)")
        }
        // El icono del sistema como red: para un `.dart` o un `.zip` QuickLook
        // no tiene nada que enseñar, y el icono sí distingue uno de otro.
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: size * scale, height: size * scale)
        result(png(from: icon).map(FlutterStandardTypedData.init(bytes:)))
      }
    }
  }

  private static func png(from image: NSImage) -> Data? {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff)
    else { return nil }
    return bitmap.representation(using: .png, properties: [:])
  }
}
