import Cocoa
import WebKit
import FlutterMacOS
import XCTest

@testable import Nexus

/// Cerrar el visor de documentos **mataba la app entera**.
///
/// Dos veces el mismo día, con la misma firma: `EXC_BAD_ACCESS` en
/// `objc_release`, dentro de `-[_NSWindowTransformAnimation dealloc]` — la
/// animación de cierre de la ventana soltando algo que ya estaba liberado.
///
/// Ninguna de las pruebas de Dart podía verlo: el fallo está entero del lado de
/// AppKit, en quién libera la ventana y cuándo.
///
/// Lo que se fija aquí **no es el segfault** —depende de la animación y del
/// momento del run loop, y no se reproduce a voluntad— sino las dos condiciones
/// que lo causaban. Con cualquiera de las dos de vuelta, la app se vuelve a
/// morir al cerrar el visor.
final class VisorDeArtefactosTests: XCTestCase {
  private var carpeta: URL!

  override func setUpWithError() throws {
    carpeta = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("nexus-visor-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: carpeta)
  }

  private func documento() throws -> String {
    let archivo = carpeta.appendingPathComponent("mockup.html")
    try "<html><body>hola</body></html>".write(to: archivo, atomically: true, encoding: .utf8)
    return archivo.path
  }

  /// Una imagen **pequeña** a propósito: 40×40 es el caso que se veía mal.
  private func imagenPequena() throws -> String {
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 40,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.red.setFill()
    NSRect(x: 0, y: 0, width: 40, height: 40).fill()
    NSGraphicsContext.restoreGraphicsState()

    let archivo = carpeta.appendingPathComponent("mini.png")
    try rep.representation(using: .png, properties: [:])!.write(to: archivo)
    return archivo.path
  }

  /// Primera mitad: AppKit no debe liberar una ventana que ya tiene dueño.
  ///
  /// Una `NSWindow` creada a mano llega con `isReleasedWhenClosed = true`, y el
  /// `Viewer` la guarda con una referencia fuerte. Al cerrar, la liberaban los
  /// dos.
  func testLaVentanaNoLaLiberaAppKitAlCerrarla() throws {
    let visor = Viewer(path: try documento(), onClose: {})
    defer { visor.window.close() }

    XCTAssertFalse(
      visor.window.isReleasedWhenClosed,
      "el Viewer es el dueño de la ventana; si AppKit la libera además, es un release de más"
    )
  }

  /// Segunda mitad: el `Viewer` no puede morir dentro de `windowWillClose`.
  ///
  /// `onClose` lo saca del diccionario que lo sostiene, y con él se va la
  /// ventana. Hacerlo durante el cierre la destruye mientras AppKit todavía
  /// está usándola.
  func testCerrarNoDestruyeElViewerDuranteElPropioCierre() throws {
    var cerrado = false
    let visor = Viewer(path: try documento()) { cerrado = true }

    visor.windowWillClose(
      Notification(name: NSWindow.willCloseNotification, object: visor.window)
    )

    XCTAssertFalse(
      cerrado,
      "onClose corrió dentro de windowWillClose: eso suelta la ventana mientras AppKit la cierra"
    )

    let siguienteTurno = expectation(description: "onClose, un turno después")
    DispatchQueue.main.async { siguienteTurno.fulfill() }
    wait(for: [siguienteTurno], timeout: 2)

    XCTAssertTrue(cerrado, "pero tiene que correr: si no, la ventana no se olvida y no se reabre")
  }

  // MARK: - Cómo se ve la imagen dentro de la ventana

  func testSoloLasImagenesSeReencuadran() {
    for imagen in ["captura.png", "foto.JPG", "animado.gif", "moderna.heic"] {
      XCTAssertTrue(Viewer.isImage("/tmp/\(imagen)"), "\(imagen) la abre WebKit como documento de imagen")
    }
    for otro in ["informe.html", "manual.pdf", "logo.svg", "notas.md"] {
      XCTAssertFalse(Viewer.isImage("/tmp/\(otro)"), "\(otro) trae su propia maquetación y no se toca")
    }
  }

  /// La queja era esta: una captura pequeña arriba a la izquierda de una
  /// ventana enorme, porque WebKit pinta una imagen suelta a tamaño natural.
  ///
  /// Se mide **lo pintado**, no la hoja de estilos: se espera a que la imagen
  /// esté en el DOM y se le pregunta al propio WebKit cuánto ocupa. Con 40×40
  /// de origen, sin reencuadre son 40 puntos.
  func testUnaImagenPequenaOcupaLaVentanaYNoUnaEsquina() throws {
    let visor = Viewer(path: try imagenPequena(), onClose: {})
    defer { visor.window.close() }

    guard let web = visor.window.contentView as? WKWebView else {
      return XCTFail("el contenido del visor debería ser el WKWebView")
    }

    let medida = try esperarMedidaDeLaImagen(en: web)
    XCTAssertGreaterThan(
      medida.width, 900,
      "una imagen de 40 px de ancho tiene que llenar la ventana, no quedarse en su tamaño"
    )
    XCTAssertGreaterThan(medida.height, 600, "y a lo alto igual")
  }

  /// Pregunta al DOM cada 100 ms hasta que la imagen exista y tenga tamaño.
  /// No vale un `didFinish` seco: la carga del archivo y la maquetación son dos
  /// momentos distintos, y medir en el primero da cero.
  private func esperarMedidaDeLaImagen(
    en web: WKWebView, timeout: TimeInterval = 15
  ) throws -> CGSize {
    var medida = CGSize.zero
    var resuelto = false
    let pintada = expectation(description: "la imagen, ya maquetada")

    func mirar() {
      web.evaluateJavaScript(
        """
        (function () {
          var i = document.images[0];
          if (!i) { return null; }
          var r = i.getBoundingClientRect();
          return [r.width, r.height];
        })()
        """
      ) { valor, _ in
        if let par = valor as? [Double], par[0] > 0, !resuelto {
          medida = CGSize(width: par[0], height: par[1])
          resuelto = true
          pintada.fulfill()
          return
        }
        guard !resuelto else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: mirar)
      }
    }
    mirar()

    wait(for: [pintada], timeout: timeout)
    return medida
  }

  /// El color de fondo en CSS se deriva del `NSColor`, así que no pueden
  /// separarse. Esta prueba es lo que sostiene esa afirmación.
  func testElFondoDelVisorEsElVoidDelTemaElegido() {
    let antes = NexusAppearance.isDark
    defer { NexusAppearance.apply(dark: antes) }

    NexusAppearance.apply(dark: true)
    XCTAssertEqual(NexusAppearance.voidCSS, "#04070D")

    NexusAppearance.apply(dark: false)
    XCTAssertEqual(NexusAppearance.voidCSS, "#E9EEF5")
  }
}

/// El icono de la barra de estado: que **diga en qué anda**, que era el punto.
///
/// Presencia sola no aportaba nada que no dijera el Dock. Lo que hacía falta es
/// distinguir «sigue trabajando» sin ir a buscar la ventana, porque un encargo
/// de Claude dura minutos.
final class BarraDeEstadoTests: XCTestCase {
  func testLosEstadosDelOrbeSeTraducenATresAspectos() {
    // Cuatro estados lógicos, tres aspectos: a 16 px no caben cuatro
    // diferencias legibles, y «hablando» y «escuchando» son lo mismo para quien
    // mira de reojo — los dos son «está contigo».
    XCTAssertEqual(NexusStatusItem.Presence.from("sleep"), .asleep)
    XCTAssertEqual(NexusStatusItem.Presence.from("listen"), .active)
    XCTAssertEqual(NexusStatusItem.Presence.from("speak"), .active)
    XCTAssertEqual(NexusStatusItem.Presence.from("think"), .working)
  }

  func testLoQueNoSeConoceSeDaPorDormido() {
    // El nombre viaja como cadena desde Dart. Si algún día se añade un estado
    // allí y no aquí, lo seguro es enseñar el icono en reposo y no romper.
    XCTAssertEqual(NexusStatusItem.Presence.from("loQueSea"), .asleep)
    XCTAssertEqual(NexusStatusItem.Presence.from(""), .asleep)
  }

  func testDormidoEsPlantillaYActivoNo() throws {
    // Dormido lo tiñe el sistema, así que se ve en barra clara y oscura. Activo
    // **no** puede ser plantilla: ahí el color es la información, y teñirlo
    // dejaría «escuchando» idéntico a «dormido».
    let dormido = try imagen(.asleep)
    let activo = try imagen(.active)

    XCTAssertTrue(dormido.isTemplate)
    XCTAssertFalse(activo.isTemplate)
  }

  func testCadaAspectoSeVeDistinto() throws {
    // Que existan tres estados no sirve de nada si pintan lo mismo. Se comparan
    // los mapas de bits: trabajando lleva el punto central.
    let activo = try datos(.active)
    let trabajando = try datos(.working)
    let dormido = try datos(.asleep)

    XCTAssertNotEqual(activo, trabajando, "«trabajando» se pinta igual que «activo»")
    XCTAssertNotEqual(activo, dormido)
  }

  private func imagen(_ p: NexusStatusItem.Presence) throws -> NSImage {
    NexusStatusItem.show(p)
    return try XCTUnwrap(NexusStatusItem.currentImage, "no hay icono en la barra")
  }

  private func datos(_ p: NexusStatusItem.Presence) throws -> Data {
    let img = try imagen(p)
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: 16, height: 16))
    NSGraphicsContext.restoreGraphicsState()
    return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
  }
}
