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

  /// El último tema aplicado, para las ventanas que **aún no existían**.
  ///
  /// `apply` recorre las ventanas abiertas, y el visor de documentos nace
  /// después: sin esto se queda con la apariencia del sistema en vez de con la
  /// elegida en la app, que es justo el fallo que este archivo viene a cerrar.
  private(set) static var isDark: Bool = systemIsDark()

  /// El `--void` de ahora, para quien tenga que pintarlo por su cuenta.
  static var voidColor: NSColor { isDark ? voidDark : voidLight }

  /// El mismo color en CSS, que es como lo necesita el visor. Se deriva del
  /// `NSColor` y no se escribe a mano para que no puedan separarse.
  static var voidCSS: String {
    let color = voidColor.usingColorSpace(.sRGB) ?? .black
    return String(
      format: "#%02X%02X%02X",
      Int((color.redComponent * 255).rounded()),
      Int((color.greenComponent * 255).rounded()),
      Int((color.blueComponent * 255).rounded())
    )
  }

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
    isDark = dark
    let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    let background = dark ? voidDark : voidLight
    for window in NSApplication.shared.windows where isOurs(window) {
      window.appearance = appearance
      window.backgroundColor = background
    }
  }

  /// La marca que llevan **nuestras** ventanas: la principal y las del visor.
  ///
  /// Hace falta porque `NSApplication.shared.windows` no son solo las que abre la
  /// app: el icono de la barra de estado vive en una ventana del sistema que
  /// también sale en esa lista, y pintarle el `--void` de fondo le ponía **un
  /// recuadro negro detrás** — se vio en la barra, junto a iconos que no llevan
  /// ninguno.
  static let ourMark = NSUserInterfaceItemIdentifier("nexus")

  /// Se marcan a mano y no se adivinan.
  ///
  /// Se probó con `canBecomeMain` y es un mal criterio: también es falso para una
  /// ventana **que todavía no se ha mostrado**, así que al arrancar se habría
  /// saltado la principal y el tema no se habría aplicado al marco. Y mirar la
  /// clase sería peor: `NSStatusBarWindow` es privada y puede cambiar de nombre
  /// sin avisar.
  static func isOurs(_ window: NSWindow) -> Bool { window.identifier == ourMark }
}
