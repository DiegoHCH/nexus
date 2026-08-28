import AppKit
import FlutterMacOS
import Foundation
import os

/// Operaciones de archivos que el sistema no deja hacer desde Dart.
///
/// Se registra como los plugins, desde `MainFlutterWindow`, y **no** desde
/// `applicationDidFinishLaunching`: ahí la ventana todavía no existe, así que
/// el registro se saltaba en silencio y cada llamada moría con
/// «MissingPluginException». El síntoma era que borrar una conversación quitaba
/// la copia de la app y dejaba la nota intacta.
final class NexusFiles {
  private static let log = Logger(subsystem: "com.katanalabs.nexus", category: "archivos")

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.katanalabs.nexus/files",
      binaryMessenger: registrar.messenger
    )
    channel.setMethodCallHandler { call, result in
      guard let path = (call.arguments as? [String: Any])?["path"] as? String else {
        result(FlutterMethodNotImplemented)
        return
      }

      // Enseñarlo en el Finder, seleccionado. Es lo que se hace con un registro:
      // no se lee dentro de la app —para eso hay editores— se abre donde está.
      if call.method == "reveal" {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        result(true)
        return
      }

      guard call.method == "moveToTrash" else {
        result(FlutterMethodNotImplemented)
        return
      }

      // `trashItem` y no mover el archivo a mano: renombrarlo hacia `~/.Trash`
      // lo prohíbe el sistema —«Operation not permitted», comprobado en vivo— y
      // además así la papelera recuerda de dónde salió, que es lo que hace
      // funcionar el «Devolver» del Finder.
      do {
        try FileManager.default.trashItem(
          at: URL(fileURLWithPath: path),
          resultingItemURL: nil
        )
        log.info("a la papelera · \(path, privacy: .public)")
        result(true)
      } catch {
        log.error("no se pudo · \(error.localizedDescription, privacy: .public)")
        result(FlutterError(code: "trash_failed", message: "\(error)", details: path))
      }
    }
    log.info("canal de archivos registrado")
  }
}
