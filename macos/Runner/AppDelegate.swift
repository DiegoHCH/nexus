import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// Por dónde entran las órdenes del menú de macOS a la app.
  private static let menuChannelName = "com.katanalabs.nexus/menu"

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// «Ajustes…» (⌘,) del menú de la aplicación.
  ///
  /// Tiene que pasar por aquí y no por un atajo de Flutter: AppKit resuelve los
  /// equivalentes de teclado del menú **antes** de entregarle la tecla a la
  /// vista, así que un `CallbackShortcuts` con ⌘, no llegaba a ejecutarse nunca
  /// mientras existiera el elemento de menú. Al revés funciona siempre, tenga
  /// el foco quien lo tenga —incluida la caja de escribir—.
  @objc func openNexusSettings(_ sender: Any?) {
    guard
      let controller = mainFlutterWindow?.contentViewController as? FlutterViewController
    else { return }
    FlutterMethodChannel(
      name: AppDelegate.menuChannelName,
      binaryMessenger: controller.engine.binaryMessenger
    ).invokeMethod("openSettings", arguments: nil)
  }
}
