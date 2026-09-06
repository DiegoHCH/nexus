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

  /// El rótulo de la casilla del visor y su ayuda, en el idioma **de la app**.
  ///
  /// Se mandan desde Dart por el mismo motivo que los del menú de la barra de
  /// estado: el idioma se elige en Ajustes y puede no ser el del sistema. Lo que
  /// hay aquí es lo que se ve hasta que Dart hable, que en la práctica es antes
  /// de que se abra ninguna ventana.
  static var etiquetaPermiso = "Permitir scripts y red"
  static var ayudaPermiso =
    "Este documento lo escribió Claude. Sin esto no ejecuta scripts ni carga nada de internet."

  /// El canal, guardado para poder hablar **hacia** Flutter.
  ///
  /// Hasta ahora este canal solo iba en un sentido —la app pide abrir, aquí se
  /// abre—. La página de una prueba corriendo necesita el de vuelta: su botón de
  /// detener es un enlace, y quien sabe parar el proceso es Dart.
  private static var channel: FlutterMethodChannel?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.katanalabs.nexus/artifacts",
      binaryMessenger: registrar.messenger
    )
    channel.setMethodCallHandler { call, result in
      // Los rótulos no hablan de ningún archivo, así que entran antes de exigir
      // uno.
      if call.method == "textos" {
        let args = call.arguments as? [String: Any]
        if let etiqueta = args?["permitir"] as? String { etiquetaPermiso = etiqueta }
        if let ayuda = args?["permitirAyuda"] as? String { ayudaPermiso = ayuda }
        result(true)
        return
      }
      // La consola de una app corriendo no es un archivo, así que entra antes
      // de exigir uno. Y no reusa el visor a propósito: aquél nace con los
      // scripts apagados y sin red porque lo que enseña lo escribió un modelo;
      // esto es un servidor nuestro en el loopback y necesita justo lo
      // contrario. Mezclarlos sería dejarle al visor un modo «déjalo todo
      // pasar», que es la mitad de su razón de existir.
      if call.method == "consola" {
        let args = call.arguments as? [String: Any]
        guard let url = args?["url"] as? String else {
          result(FlutterMethodNotImplemented)
          return
        }
        Consola.enseña(
          url: url,
          titulo: args?["titulo"] as? String,
          width: args?["width"] as? Double,
          height: args?["height"] as? Double
        )
        result(true)
        return
      }
      guard let path = (call.arguments as? [String: Any])?["path"] as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      let args = call.arguments as? [String: Any]
      switch call.method {
      case "open":
        // El tamaño es opcional y por eso llega así: un documento quiere la
        // ventana grande de siempre, y una prueba corriendo quiere una columna
        // estrecha y alta que se pueda dejar al lado mientras se trabaja.
        show(
          path: path,
          width: args?["width"] as? Double,
          height: args?["height"] as? Double
        )
        result(true)
      case "reveal":
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
    log.info("canal de artefactos registrado")
  }

  /// Una página pidió algo. Se le pasa a Flutter tal cual.
  ///
  /// **Solo el nombre de lo pedido, nada de la URL.** Una página es contenido y
  /// no una fuente de confianza: reenviar su URL entera invitaría a que mañana
  /// alguien la usara para decidir algo con lo que venga dentro.
  /// Que el bloqueo de red no se pudo poner. Se anota y se sigue: los scripts
  /// del contenido siguen apagados, que es la mitad que de verdad cierra la
  /// puerta.
  static func noSePudoBloquear(_ error: Error?) {
    log.error(
      "el visor no pudo bloquear la red: \(error?.localizedDescription ?? "sin motivo", privacy: .public)"
    )
  }

  /// Lo que una página nuestra le pide a la app.
  ///
  /// `que` es el host —`nexus://parar` pide parar— y `ruta` es lo que venga
  /// detrás. La ruta existe porque **hay más de una ventana pidiendo cosas** y
  /// no siempre basta con saber qué se pide: la de un encargo en curso tiene
  /// que decir además de cuál, y eso viaja como `nexus://detener/<id>`.
  static func pidieron(_ que: String, ruta: String = "") {
    log.info("la página pidió \(que, privacy: .public)")
    channel?.invokeMethod("desdeLaPagina", arguments: ["que": que, "ruta": ruta])
  }

  private static func show(path: String, width: Double? = nil, height: Double? = nil) {
    if let already = open[path], already.window.isVisible {
      already.window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    let viewer = Viewer(path: path, width: width, height: height) {
      open.removeValue(forKey: path)
    }
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

  /// El documento puede ejecutar sus scripts y salir a la red.
  ///
  /// **Nace apagado.** El HTML lo escribe Claude, y lo que Claude escribe puede
  /// venir influido por lo que leyó en un repositorio; con los scripts
  /// corriendo, un `fetch` a un dominio cualquiera convierte el visor en un
  /// canal de salida, y con lectura de toda la carpeta —que hace falta para el
  /// `assets/` de al lado— lo que sale puede ser el documento del vecino.
  ///
  /// Se puede encender, y por eso esto no es una amputación: un mockup que
  /// necesita su gráfica pide el permiso con la casilla del título. Lo que
  /// cambia es quién decide, y ahora decide quien mira.
  private(set) var permitido = false

  /// La casilla del título. Guardada para poder reflejar el estado cuando el
  /// permiso cambie desde otro sitio.
  private var casilla: NSButton?

  /// Dónde estaba el scroll, para devolverlo tras recargar. Sin esto cada
  /// cambio te sube al principio, y en un documento largo eso es peor que no
  /// recargar.
  private var scrollY: Double = 0

  init(
    path: String,
    width: Double? = nil,
    height: Double? = nil,
    onClose: @escaping () -> Void
  ) {
    self.url = URL(fileURLWithPath: path)
    self.onClose = onClose
    window = NSWindow(
      // Los mil por setecientos ochenta de siempre cuando nadie dice otra cosa:
      // es la medida de un documento y no hay motivo para cambiarla.
      contentRect: NSRect(
        x: 0, y: 0, width: width ?? 1000, height: height ?? 780
      ),
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
    window.identifier = NexusAppearance.ourMark
    window.appearance = NSAppearance(named: NexusAppearance.isDark ? .darkAqua : .aqua)
    window.backgroundColor = NexusAppearance.voidColor

    window.title = url.lastPathComponent
    window.center()
    window.contentView = web
    window.delegate = self
    web.navigationDelegate = self
    ponerLaCasilla()
    load()
    watch()
  }

  // MARK: - El permiso, y dónde se pide

  /// La casilla en la barra de título.
  ///
  /// Ahí y no en un menú porque tiene que verse sin buscarla: es la diferencia
  /// entre un documento que solo se mira y uno que puede hablar con internet, y
  /// eso no puede vivir detrás de dos clics.
  private func ponerLaCasilla() {
    let boton = NSButton(
      checkboxWithTitle: NexusArtifacts.etiquetaPermiso,
      target: self,
      action: #selector(cambiarPermiso(_:))
    )
    boton.state = .off
    boton.toolTip = NexusArtifacts.ayudaPermiso
    boton.sizeToFit()

    let caja = NSView(
      frame: NSRect(x: 0, y: 0, width: boton.frame.width + 16, height: 28)
    )
    boton.frame = NSRect(
      x: 8, y: (28 - boton.frame.height) / 2,
      width: boton.frame.width, height: boton.frame.height
    )
    caja.addSubview(boton)

    let accesorio = NSTitlebarAccessoryViewController()
    accesorio.layoutAttribute = .right
    accesorio.view = caja
    window.addTitlebarAccessoryViewController(accesorio)
    casilla = boton
  }

  @objc private func cambiarPermiso(_ sender: NSButton) {
    permitir(sender.state == .on)
  }

  /// Enciende o apaga el permiso y recarga.
  ///
  /// Recargar hace falta: el JavaScript del contenido se decide **al navegar**,
  /// así que un documento ya pintado no empieza a ejecutar nada por marcar la
  /// casilla. Y al revés —desmarcarla con los scripts ya corriendo no los para—,
  /// que es el motivo de verdad por el que se recarga en los dos sentidos.
  func permitir(_ nuevo: Bool) {
    guard nuevo != permitido else { return }
    permitido = nuevo
    casilla?.state = nuevo ? .on : .off
    load()
  }

  private func load() {
    // Las reglas primero. Cargar y bloquear después dejaría pasar justo la
    // primera vuelta, que es la única que un documento necesita.
    conLasReglas { [weak self] in
      guard let self else { return }
      // Acceso de lectura a la carpeta y no solo al archivo: un artefacto HTML
      // suele traer al lado su `assets/`, y sin esto las imágenes salen rotas.
      //
      // Ese acceso es también la razón por la que existe todo lo de arriba: con
      // los vecinos legibles, un script del documento podía leerlos y mandarlos
      // fuera. Sin scripts y sin red, lo que la carpeta permite es enseñar, no
      // contar.
      self.web.loadFileURL(
        self.url, allowingReadAccessTo: self.url.deletingLastPathComponent()
      )
    }
  }

  /// Lo que el documento **no** puede cargar: nada que no sea él mismo.
  ///
  /// Es la lista de bloqueo de WebKit y no una `Content-Security-Policy` porque
  /// una CSP hay que meterla dentro del HTML, y el HTML es del usuario: no se
  /// reescribe un archivo suyo para poder enseñarlo. Esto lo aplica el motor por
  /// fuera, y no hay nada que la página pueda escribir para quitárselo.
  ///
  /// `file`, `data`, `about` y `blob` siguen pasando: son el propio documento,
  /// sus imágenes incrustadas y su `assets/`. `nexus` también, que es como la
  /// página de una pasada pide parar.
  ///
  /// **Una regla por esquema y no una alternancia.** El motor de expresiones de
  /// las listas de WebKit no admite grupos con `|`: `^(file|data):` no compila
  /// —falla con `WKErrorDomain 6`— y una lista que no compila es un visor sin
  /// bloqueo. Lo dice la prueba que compila esta constante, que está justo para
  /// eso: el error no aparece al construir el proyecto, aparece al abrir una
  /// ventana, y ahí ya no lo ve nadie.
  static let sinRed = #"""
    [
      {"trigger": {"url-filter": ".*"}, "action": {"type": "block"}},
      {"trigger": {"url-filter": "^file:"}, "action": {"type": "ignore-previous-rules"}},
      {"trigger": {"url-filter": "^data:"}, "action": {"type": "ignore-previous-rules"}},
      {"trigger": {"url-filter": "^about:"}, "action": {"type": "ignore-previous-rules"}},
      {"trigger": {"url-filter": "^blob:"}, "action": {"type": "ignore-previous-rules"}},
      {"trigger": {"url-filter": "^nexus:"}, "action": {"type": "ignore-previous-rules"}}
    ]
    """#

  static let reglaId = "nexus-visor-sin-red"

  /// Compilada una vez para toda la app: hacerlo por ventana y por recarga sería
  /// trabajo repetido para un texto que no cambia nunca.
  private static var reglaCompilada: WKContentRuleList?

  /// Deja el bloqueo como toque y **entonces** sigue.
  ///
  /// Si la compilación falla se sigue igual, sin bloqueo, y se anota. Sería un
  /// fallo de nuestro texto y no del documento, y dejar la ventana en blanco por
  /// él cambiaría un problema de seguridad por uno de «no se ve nada». La
  /// defensa que de verdad cierra la puerta —los scripts apagados— sigue puesta.
  private func conLasReglas(_ luego: @escaping () -> Void) {
    let controlador = web.configuration.userContentController
    controlador.removeAllContentRuleLists()
    guard !permitido else { return luego() }

    if let ya = Viewer.reglaCompilada {
      controlador.add(ya)
      return luego()
    }
    guard let almacen = WKContentRuleListStore.default() else { return luego() }
    almacen.compileContentRuleList(
      forIdentifier: Viewer.reglaId, encodedContentRuleList: Viewer.sinRed
    ) { lista, error in
      if let lista {
        Viewer.reglaCompilada = lista
        controlador.add(lista)
      } else {
        NexusArtifacts.noSePudoBloquear(error)
      }
      luego()
    }
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
  /// **La variante con `preferences`, y no la de siempre.**
  ///
  /// WebKit llama a una o a otra, nunca a las dos: implementando esta se puede
  /// decir, en cada navegación, si el contenido ejecuta JavaScript. Sin ella el
  /// permiso solo se puede fijar al construir la vista, y encenderlo desde la
  /// casilla obligaría a tirar el `WKWebView` y hacer otro.
  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
    preferences: WKWebpagePreferences,
    decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
  ) {
    preferences.allowsContentJavaScript = permitido

    // Lo nuestro se queda dentro: una página de Nexus puede pedirle algo a la
    // app, y eso no es navegar. Antes que el reenvío al navegador, porque
    // `nexus://parar` no es una dirección de internet.
    if let target = navigationAction.request.url, target.scheme == "nexus" {
      NexusArtifacts.pidieron(target.host ?? "", ruta: target.path)
      decisionHandler(.cancel, preferences)
      return
    }
    if let target = navigationAction.request.url, !target.isFileURL {
      NSWorkspace.shared.open(target)
      decisionHandler(.cancel, preferences)
      return
    }
    decisionHandler(.allow, preferences)
  }

  func windowWillClose(_ notification: Notification) {
    pending?.cancel()
    watcher?.cancel()
    // **Que se cerró hay que decirlo, o nadie se entera.** Una página que se
    // repinta sola —el registro de una corrida— seguiría escribiendo su archivo
    // cada pocos milisegundos para una ventana que ya no existe, y el botón que
    // la abrió seguiría marcado. Va la ruta porque hay más de una abierta.
    NexusArtifacts.pidieron("cerrada", ruta: url.path)
    // Al siguiente turno del run loop, no aquí mismo. `onClose` saca este
    // `Viewer` del diccionario, que es quien lo sostiene: soltarlo dentro de
    // `windowWillClose` lo destruye —y con él la ventana— mientras AppKit
    // todavía está cerrándola. Es la segunda mitad del mismo fallo.
    DispatchQueue.main.async { [onClose] in onClose() }
  }
}

// MARK: - La consola de una app corriendo

/// La consola de depuración de la app, en una ventana de Nexus.
///
/// 🔴 **No es el visor de documentos y no debe serlo.** Aquél enseña HTML que
/// escribió un modelo, así que nace sin scripts y con la red cortada; esto es un
/// servidor de depuración en el loopback —el que la propia app levanta— y sin
/// scripts ni red no hay nada que enseñar. Compartir clase obligaría a darle al
/// visor un modo «déjalo todo pasar», y ese modo es exactamente lo que su
/// bloqueo existe para que no haya.
///
/// **Lo que sí se comparte es la idea**: una `NSWindow` de verdad, que se mueve,
/// se deja al lado y no bloquea la app — al contrario que un diálogo.
final class Consola: NSObject, NSWindowDelegate {
  /// Una por dirección. Abrir dos veces la misma trae la que ya está delante en
  /// vez de apilar ventanas iguales, que es lo que hace el visor con sus
  /// archivos y lo que espera cualquiera que pulse dos veces.
  private static var abiertas: [String: Consola] = [:]

  static func enseña(url: String, titulo: String?, width: Double?, height: Double?) {
    if let ya = abiertas[url], ya.window.isVisible {
      ya.window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    guard let destino = URL(string: url) else { return }
    let consola = Consola(url: destino, titulo: titulo, width: width, height: height)
    abiertas[url] = consola
    consola.window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  let window: NSWindow
  private let web: WKWebView
  private let clave: String

  private init(url: URL, titulo: String?, width: Double?, height: Double?) {
    clave = url.absoluteString

    // Persistente y compartida con el resto de la app: un panel de depuración
    // recuerda en qué pestaña lo dejaste, y con un almacén de los de usar y
    // tirar volvería al principio en cada arranque.
    let configuracion = WKWebViewConfiguration()
    configuracion.websiteDataStore = .default()
    web = WKWebView(frame: .zero, configuration: configuracion)

    window = NSWindow(
      // Más ancha que alta: lo que se lee aquí son tablas —rutas, providers,
      // filas de una base— y partirlas es lo que estorba.
      contentRect: NSRect(
        x: 0, y: 0, width: width ?? 1100, height: height ?? 760
      ),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    super.init()

    // Una `NSWindow` creada a mano llega con `isReleasedWhenClosed = true`, y
    // aquí la posee esta clase: ese release de más mata la app al cerrar. Es la
    // misma piedra que ya se documentó en el visor, y se paga igual.
    window.isReleasedWhenClosed = false
    window.identifier = NexusAppearance.ourMark
    window.appearance = NSAppearance(named: NexusAppearance.isDark ? .darkAqua : .aqua)
    window.backgroundColor = NexusAppearance.voidColor
    window.title = titulo ?? url.absoluteString
    window.center()
    window.contentView = web
    window.delegate = self

    web.load(URLRequest(url: url))
  }

  func windowWillClose(_ notification: Notification) {
    // Al siguiente turno del run loop y no aquí: quien sostiene esta instancia
    // es el diccionario, y soltarla dentro de `windowWillClose` la destruye
    // mientras AppKit todavía está cerrando su ventana.
    let clave = self.clave
    DispatchQueue.main.async { Consola.abiertas.removeValue(forKey: clave) }
  }
}
