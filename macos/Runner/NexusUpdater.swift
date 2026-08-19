import Cocoa
import FlutterMacOS
import Foundation
import Sparkle
import os

/// Actualizarse: el motor es de Sparkle, la cara es de Nexus.
///
/// Sparkle trae su propio diálogo y aquí **no se usa**. Lo que se usa es su
/// motor, que es la parte que no se debe escribir a mano: esperar a que el
/// proceso cierre, cambiar el paquete de la app en el disco, relanzarla y saber
/// deshacerlo si algo falla a mitad. Eso lleva veinte años depurándose y un
/// fallo ahí deja la instalación partida.
///
/// La interfaz sí es nuestra, a través de un `SPUUserDriver` propio: cada método
/// del protocolo reenvía a Dart por el canal y Dart pinta la modal en el HUD, en
/// el idioma de la app. Las respuestas vuelven por `answer`.
final class NexusUpdater: NSObject {
  private static let log = Logger(subsystem: "com.katanalabs.nexus", category: "actualizar")

  /// Referencias fuertes: si se sueltan, el actualizador se apaga a mitad de una
  /// descarga y la modal se queda esperando un progreso que ya no llega.
  private static var updater: SPUUpdater?
  private static var driver: Driver?

  /// Si esta copia de la app **puede** actualizarse, y si no, por qué.
  ///
  /// Existe porque el caso malo es silencioso: una app abierta desde Descargas
  /// sin arrastrarla la ejecuta macOS desde una copia de solo lectura con ruta
  /// aleatoria —traslocación de Gatekeeper—, y ahí no hay nada que reemplazar.
  /// Sin esta comprobación, la modal ofrecería actualizar y el fallo aparecería
  /// al final, después de descargar 23 MB.
  enum Installability: String {
    /// Se puede.
    case ok
    /// Corre desde la copia de solo lectura de Gatekeeper: hay que arrastrarla
    /// a Aplicaciones primero.
    case translocated
    /// Está en un sitio donde no podemos escribir.
    case readOnly

    var razon: String { rawValue }
  }

  /// Separado del sistema de archivos a propósito, para poder probarlo: el caso
  /// que importa —la ruta traslocada— no se puede montar en una prueba.
  static func installability(bundlePath: String, writable: Bool) -> Installability {
    // macOS monta la copia en `…/AppTranslocation/<uuid>/d/Nexus.app`. Es el
    // único indicio fiable: la ruta ni siquiera está en `/Applications`, y el
    // paquete parece intacto por dentro.
    if bundlePath.contains("/AppTranslocation/") { return .translocated }
    return writable ? .ok : .readOnly
  }

  static func currentInstallability() -> Installability {
    let ruta = Bundle.main.bundlePath
    return installability(
      bundlePath: ruta,
      // El padre y no el paquete: reemplazar la app es escribir en la carpeta
      // que la contiene, no dentro de ella.
      writable: FileManager.default.isWritableFile(atPath: (ruta as NSString).deletingLastPathComponent)
    )
  }

  /// `@MainActor` porque lo es Sparkle: `SPUUpdater` y `SPUUserDriver` vienen
  /// marcados `NS_SWIFT_UI_ACTOR` en sus cabeceras, así que el compilador exige
  /// que todo esto viva en el hilo principal. No es una precaución nuestra.
  @MainActor
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.katanalabs.nexus/updates",
      binaryMessenger: registrar.messenger
    )

    let conductor = Driver(channel: channel)
    driver = conductor

    let motor = SPUUpdater(
      hostBundle: .main,
      applicationBundle: .main,
      userDriver: conductor,
      delegate: nil
    )
    // Nada se descarga a la espalda de nadie: la modal pregunta antes.
    motor.automaticallyDownloadsUpdates = false
    updater = motor

    // El salto al hilo principal es obligatorio y no decorativo: el bloque que
    // instala Flutter no está marcado, y todo lo de Sparkle sí. `Task { @MainActor }`
    // y no `MainActor.assumeIsolated`, que pide macOS 14 y aquí el mínimo es 12.
    channel.setMethodCallHandler { call, result in
      Task { @MainActor in
        switch call.method {
        case "installability":
          result(currentInstallability().razon)

        // Dos comprobaciones y no una: la de fondo calla si no hay nada, y la que
        // pides tú tiene que decir «estás al día» — un botón que no contesta se
        // lee como roto.
        case "check":
          let mia = (call.arguments as? [String: Any])?["manual"] as? Bool ?? false
          if mia { motor.checkForUpdates() } else { motor.checkForUpdatesInBackground() }
          result(nil)

        case "answer":
          let cual = (call.arguments as? [String: Any])?["choice"] as? String ?? "later"
          conductor.answer(cual)
          result(nil)

        case "cancel":
          conductor.cancel()
          result(nil)

        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    do {
      try motor.start()
      log.info("actualizador en marcha (\(currentInstallability().razon, privacy: .public))")
    } catch {
      // Que no arranque no puede tumbar la app: se pierde el actualizador, no
      // el asistente. Dart lo verá porque `installability` seguirá contestando
      // y la comprobación no devolverá nada.
      log.error("el actualizador no arrancó: \(error.localizedDescription, privacy: .public)")
    }
  }

  /// La interfaz de Sparkle, reenviada a Dart.
  ///
  /// Los `reply` no se contestan aquí: se guardan y se contestan cuando la
  /// persona pulsa en la modal. De ahí que haya estado guardado — es la espera.
  @MainActor
  private final class Driver: NSObject, SPUUserDriver {
    private let channel: FlutterMethodChannel
    private var responder: ((SPUUserUpdateChoice) -> Void)?
    private var cancelar: (() -> Void)?
    private var esperado: UInt64 = 0
    private var recibido: UInt64 = 0

    init(channel: FlutterMethodChannel) {
      self.channel = channel
      super.init()
    }

    func answer(_ cual: String) {
      let eleccion: SPUUserUpdateChoice = switch cual {
      case "install": .install
      case "skip": .skip
      default: .dismiss
      }
      let contestar = responder
      responder = nil
      contestar?(eleccion)
    }

    func cancel() {
      let parar = cancelar
      cancelar = nil
      parar?()
    }

    private func avisar(_ metodo: String, _ datos: [String: Any?] = [:]) {
      channel.invokeMethod(metodo, arguments: datos)
    }

    // MARK: - SPUUserDriver

    /// El permiso para comprobar actualizaciones, que **no se pregunta**.
    ///
    /// Sparkle enseña aquí su diálogo de «¿quieres que busque actualizaciones
    /// automáticamente?» la primera vez. Nexus ya lo tiene decidido en el
    /// `Info.plist` —comprueba cada dos horas y no descarga nada sin permiso—,
    /// así que sacar la pregunta sería pedir una decisión que ya está tomada.
    ///
    /// El perfil del sistema va a `false`: es lo que manda a Apple… no, a quien
    /// sirva el feed, un resumen de tu Mac. No hace falta para nada de esto.
    /// Se llama `show(_:reply:)` y no `showUpdatePermissionRequest`: Swift lo
    /// reescribe así al importarlo, y con el nombre del header no compila.
    func show(
      _ request: SPUUpdatePermissionRequest,
      reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
      reply(
        SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false)
      )
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
      cancelar = cancellation
      avisar("checking")
    }

    func showUpdateFound(
      with appcastItem: SUAppcastItem,
      state: SPUUserUpdateState,
      reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
      responder = reply

      // Si ya venía descargada de una vuelta anterior, no hay nada que bajar y
      // la modal tiene que ofrecer «reiniciar», no «descargar». Sin distinguirlo
      // la barra de progreso saldría y se quedaría a cero para siempre.
      let yaEsta = state.stage == .installing || state.stage == .downloaded

      avisar("found", [
        "version": appcastItem.displayVersionString,
        "build": appcastItem.versionString,
        "notes": appcastItem.itemDescription,
        "bytes": appcastItem.contentLength > 0 ? Int(appcastItem.contentLength) : nil,
        "downloaded": yaEsta,
        "userInitiated": state.userInitiated,
      ])
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
      // Las notas viajan dentro del propio feed (`<description>`), así que esto
      // solo salta si algún día se usa `sparkle:releaseNotesLink`. Se reenvía
      // por si acaso en vez de quedar en silencio.
      guard let texto = String(data: downloadData.data, encoding: .utf8) else { return }
      avisar("notes", ["notes": texto])
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
      // No es un fallo de la actualización: se puede instalar igual sin las
      // notas, así que la modal no se entera.
      NexusUpdater.log.info("no se pudieron bajar las notas: \(error.localizedDescription, privacy: .public)")
    }

    // Estos tres llegan a Swift como `async` y sin su bloque de confirmación:
    // las cabeceras los marcan `NS_SWIFT_ASYNC(2)`, así que el propio runtime
    // avisa a Sparkle cuando la función vuelve. Escribirlos con `acknowledgement`
    // —como parecería por el header en C— no compila.
    func showUpdateNotFoundWithError(_ error: any Error) async {
      avisar("none")
    }

    func showUpdaterError(_ error: any Error) async {
      avisar("failed", ["message": error.localizedDescription])
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
      cancelar = cancellation
      esperado = 0
      recibido = 0
      avisar("downloading", ["received": 0, "total": nil])
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
      esperado = expectedContentLength
      avisar("downloading", ["received": Int(recibido), "total": Int(esperado)])
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
      // Sparkle manda **el trozo**, no el total: hay que acumular. Reenviar
      // `length` tal cual haría una barra que se queda pegada al principio.
      recibido += length
      avisar("downloading", [
        "received": Int(recibido),
        "total": esperado > 0 ? Int(esperado) : nil,
      ])
    }

    func showDownloadDidStartExtractingUpdate() {
      avisar("extracting", ["progress": 0.0])
    }

    func showExtractionReceivedProgress(_ progress: Double) {
      avisar("extracting", ["progress": progress])
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
      responder = reply
      avisar("ready")
    }

    func showInstallingUpdate(
      withApplicationTerminated applicationTerminated: Bool,
      retryTerminatingApplication: @escaping () -> Void
    ) {
      avisar("installing")
      // Si la app todavía no ha cerrado, Sparkle pide que se reintente: sin esto
      // la instalación se queda esperando a un proceso que nadie va a cerrar.
      if !applicationTerminated { retryTerminatingApplication() }
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool) async {
      avisar("installed", ["relaunched": relaunched])
    }

    func showUpdateInFocus() {
      NSApp.activate(ignoringOtherApps: true)
      NSApp.windows.first { NexusAppearance.isOurs($0) }?.makeKeyAndOrderFront(nil)
    }

    func dismissUpdateInstallation() {
      responder = nil
      cancelar = nil
      avisar("closed")
    }
  }
}
