import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Marco oscuro, no sin marco: la barra de título se funde con --void
    // (#04070D) en vez del cromo claro por defecto de macOS. Se fuerza
    // .darkAqua en el marco nativo sin importar el tema del sistema —el
    // contenido de Flutter sigue el tema claro/oscuro del sistema aparte,
    // vía ThemeMode.system— porque es la identidad visual del HUD, no una
    // preferencia de accesibilidad.
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.appearance = NSAppearance(named: .darkAqua)
    self.backgroundColor = NSColor(red: 0x04 / 255, green: 0x07 / 255, blue: 0x0D / 255, alpha: 1)
    self.isOpaque = true

    super.awakeFromNib()
  }
}
