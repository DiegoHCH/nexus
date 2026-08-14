import AppKit
import FlutterMacOS
import Foundation
import WebKit
import os

/// El visor de documentos generados: una ventana propia con el archivo dentro.
///
/// Ventana aparte y no un panel dentro de la app: un mockup se mira **al lado**
/// de la conversación en la que lo estás pidiendo, no en lugar de ella. Y es la
/// única forma de tenerlo abierto en un monitor mientras hablas en el otro.
///
/// Se apoya en `WKWebView`, así que sale gratis lo que de verdad se genera:
/// HTML, PDF, PNG y SVG los pinta el sistema sin que aquí haya que interpretar
/// nada.
final class NexusArtifacts: NSObject {
  private static let log = Logger(subsystem: "com.katanalabs.nexus", category: "artefactos")

  /// Las ventanas abiertas, por archivo. Existe para **no abrir una segunda**:
  /// al pedir cambios sobre un documento lo normal es volver al que ya tienes
  /// delante, y con la recarga automática esa ventana ya está al día.
  private static var open: [String: Viewer] = [:]

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.katanalabs.nexus/artifacts",
      binaryMessenger: registrar.messenger
    )
    channel.setMethodCallHandler { call, result in
      guard let path = (call.arguments as? [String: Any])?["path"] as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      switch call.method {
      case "open":
        show(path: path)
        result(true)
      case "reveal":
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    log.info("canal de artefactos registrado")
  }

  private static func show(path: String) {
    if let already = open[path], already.window.isVisible {
      already.window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    let viewer = Viewer(path: path) { open.removeValue(forKey: path) }
    open[path] = viewer
    viewer.window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}

/// Una ventana con el documento, que se entera de que ha cambiado.
/// Interna y no privada para que `RunnerTests` pueda construir una y comprobar
/// cómo se cierra. Es justo la parte que no se puede probar desde Dart.
final class Viewer: NSObject, NSWindowDelegate, WKNavigationDelegate {
  let window: NSWindow
  private let web = WKWebView()
  private let url: URL
  private let onClose: () -> Void
  private var watcher: DispatchSourceFileSystemObject?
  private var pending: DispatchWorkItem?

  /// Dónde estaba el scroll, para devolverlo tras recargar. Sin esto cada
  /// cambio te sube al principio, y en un documento largo eso es peor que no
  /// recargar.
  private var scrollY: Double = 0

  init(path: String, onClose: @escaping () -> Void) {
    self.url = URL(fileURLWithPath: path)
    self.onClose = onClose
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1000, height: 780),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    super.init()

    // Una `NSWindow` creada a mano llega con `isReleasedWhenClosed = true`: al
    // cerrarla, AppKit la libera. Pero aquí la ventana **la posee el `Viewer`**
    // con una referencia fuerte, así que ARC la libera también. Ese release de
    // más mataba la app entera al cerrar el visor: `EXC_BAD_ACCESS` en
    // `-[_NSWindowTransformAnimation dealloc]`, la animación de cierre soltando
    // algo que ya no estaba.
    window.isReleasedWhenClosed = false

    // La apariencia elegida en la app, no la del sistema: esta ventana nace
    // después de que `apply` haya recorrido las suyas.
    window.appearance = NSAppearance(named: NexusAppearance.isDark ? .darkAqua : .aqua)
    window.backgroundColor = NexusAppearance.voidColor

    window.title = url.lastPathComponent
    window.center()
    window.contentView = web
    window.delegate = self
    web.navigationDelegate = self
    load()
    watch()
  }

  private func load() {
    // Acceso de lectura a la carpeta y no solo al archivo: un artefacto HTML
    // suele traer al lado su `assets/`, y sin esto las imágenes salen rotas.
    web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
  }

  /// Se vigila **la carpeta**, no el archivo.
  ///
  /// Guardar no siempre es escribir encima: muchas herramientas escriben un
  /// temporal y lo renombran, y eso deja a un vigía del archivo mirando un
  /// inodo que ya no usa nadie — la ventana no se enteraría nunca.
  private func watch() {
    let dir = url.deletingLastPathComponent()
    let descriptor = Foundation.open(dir.path, O_EVTONLY)
    guard descriptor >= 0 else { return }

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor,
      eventMask: [.write, .rename, .delete],
      queue: .main
    )
    source.setEventHandler { [weak self] in self?.scheduleReload() }
    source.setCancelHandler { Foundation.close(descriptor) }
    source.resume()
    watcher = source
  }

  /// Con espera antes de recargar: un guardado no es atómico —el archivo pasa
  /// por vacío o a medias— y recargar en ese instante enseña una página en
  /// blanco. Además llegan varios eventos por guardado.
  private func scheduleReload() {
    pending?.cancel()
    let work = DispatchWorkItem { [weak self] in self?.reload() }
    pending = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
  }

  private func reload() {
    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
    let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
    guard size > 0 else { return }

    web.evaluateJavaScript("window.scrollY") { [weak self] value, _ in
      self?.scrollY = (value as? NSNumber)?.doubleValue ?? 0
      self?.load()
    }
  }

  /// Los formatos que `WKWebView` abre como **documento de imagen**.
  ///
  /// Con una imagen suelta, WebKit hace lo que hace un navegador: la pinta a
  /// tamaño natural, pegada arriba a la izquierda y sobre blanco. Eso, en una
  /// ventana de 1000×780, deja una captura pequeña en una esquina.
  ///
  /// Los demás formatos no se tocan: el HTML trae su propia maquetación, y el
  /// PDF ya lo encuadra el visor del sistema.
  static func isImage(_ path: String) -> Bool {
    let images: Set<String> = [
      "png", "jpg", "jpeg", "gif", "bmp", "webp", "heic", "heif", "tiff", "tif", "ico",
    ]
    return images.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
  }

  /// La imagen, centrada y a toda la ventana.
  ///
  /// `object-fit: contain` y no `cover`: llenar recortando un mockup es perder
  /// justo lo que se viene a mirar. Se permite agrandar —una captura de Retina
  /// llega a la mitad de su tamaño en píxeles CSS y se veía diminuta—, con un
  /// margen para que no quede pegada al marco.
  private func frameImage(_ webView: WKWebView) {
    let fondo = NexusAppearance.voidCSS
    webView.evaluateJavaScript(
      """
      document.documentElement.style.height = '100%';
      document.body.style.cssText =
        'margin:0;padding:16px;box-sizing:border-box;height:100%;display:flex;\
      align-items:center;justify-content:center;background:\(fondo)';
      var imagen = document.images[0];
      if (imagen) {
        imagen.style.cssText = 'width:100%;height:100%;object-fit:contain';
      }
      """
    )
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    if Viewer.isImage(url.path) { frameImage(webView) }
    guard scrollY > 0 else { return }
    webView.evaluateJavaScript("window.scrollTo(0, \(scrollY))")
  }

  /// Lo de fuera, fuera: el visor se queda en su archivo y cualquier enlace a
  /// la red se abre en el navegador. Una ventana sin barra de direcciones que
  /// navega a internet es una ventana en la que no sabes dónde estás.
  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    if let target = navigationAction.request.url, !target.isFileURL {
      NSWorkspace.shared.open(target)
      decisionHandler(.cancel)
      return
    }
    decisionHandler(.allow)
  }

  func windowWillClose(_ notification: Notification) {
    pending?.cancel()
    watcher?.cancel()
    // Al siguiente turno del run loop, no aquí mismo. `onClose` saca este
    // `Viewer` del diccionario, que es quien lo sostiene: soltarlo dentro de
    // `windowWillClose` lo destruye —y con él la ventana— mientras AppKit
    // todavía está cerrándola. Es la segunda mitad del mismo fallo.
    DispatchQueue.main.async { [onClose] in onClose() }
  }
}
