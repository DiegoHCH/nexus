import Cocoa
import FlutterMacOS
import Foundation
import os

/// El marco de la ventana, que no es Flutter.
///
/// La barra de título y el fondo son AppKit, así que el tema elegido en la app
/// no les llega solo. Estaban clavados en oscuro —`.darkAqua` y `#04070D`, sin
/// mirar el sistema— y el comentario que lo justificaba decía que era la
/// identidad visual del HUD. Lo era mientras el tema claro no se podía elegir:
/// en cuanto se puede, contenido claro dentro de una barra de título negra deja
/// de ser identidad y pasa a ser un tema a medias.
///
/// El fondo se pinta además del `appearance` porque **no es un gris del
/// sistema**: es el `--void` de la paleta, el mismo color que el contenido de
/// Flutter pinta encima. Si no coincidieran se vería una banda distinta al
/// redimensionar y en el fotograma anterior al primer dibujo.
final class NexusAppearance {
  private static let log = Logger(
    subsystem: "com.katanalabs.nexus",
    category: "apariencia"
  )

  /// El `--void` de cada tema, que es el fondo de la ventana.
  private static let voidDark = NSColor(
    red: 0x04 / 255, green: 0x07 / 255, blue: 0x0D / 255, alpha: 1
  )
  private static let voidLight = NSColor(
    red: 0xE9 / 255, green: 0xEE / 255, blue: 0xF5 / 255, alpha: 1
  )

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.katanalabs.nexus/appearance",
      binaryMessenger: registrar.messenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "apply":
        let dark = (call.arguments as? [String: Any])?["dark"] as? Bool ?? true
        apply(dark: dark)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    log.info("canal de apariencia registrado")
  }

  /// Lo que pide el sistema ahora mismo.
  ///
  /// Se usa para el primer fotograma, antes de que Dart haya leído la
  /// preferencia guardada: sin esto, arrancar siempre oscuro daba un parpadeo
  /// en negro al abrir la app con el Mac en claro.
  static func systemIsDark() -> Bool {
    let match = NSApplication.shared.effectiveAppearance.bestMatch(
      from: [.aqua, .darkAqua]
    )
    return match == .darkAqua
  }

  /// Se aplica a todas las ventanas y no solo a la principal: el visor de
  /// documentos es una ventana aparte, y dejarla con el tema anterior sería
  /// exactamente el fallo que esto viene a cerrar, un paso más allá.
  static func apply(dark: Bool) {
    let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let background = dark ? voidDark : voidLight
    for window in NSApplication.shared.windows {
      window.appearance = appearance
      window.backgroundColor = background
    }
  }
}
