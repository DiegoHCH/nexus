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
      miniatura(ruta: path, tamano: size, escala: scale) { png in
        result(png.map(FlutterStandardTypedData.init(bytes:)))
      }
    }
    log.info("canal de miniaturas registrado")
  }

  /// La miniatura como bytes PNG, o `nil` si no hubo forma.
  ///
  /// Separada del canal para poder probarla: lo que hay que comprobar es que
  /// **siempre salga algo** para un archivo normal —quedarse sin imagen es el
  /// único resultado inservible— y eso no necesita un `FlutterResult`.
  static func miniatura(
    ruta path: String,
    tamano size: Double,
    escala scale: Double,
    luego: @escaping (Data?) -> Void
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
          luego(png)
          return
        }
        if let error {
          log.debug("sin miniatura · \(error.localizedDescription, privacy: .public)")
        }
        // El icono del sistema como red: para un `.dart` o un `.zip` QuickLook
        // no tiene nada que enseñar, y el icono sí distingue uno de otro.
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: size * scale, height: size * scale)
        luego(png(from: icon))
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
