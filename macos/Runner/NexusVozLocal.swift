import AVFoundation
import FlutterMacOS
import Foundation
import Speech
import os

/// Oír y hablar **sin salir del Mac**.
///
/// La fase 1 del plan de la voz propia, y su prueba de fuego. Hoy hablar con
/// Nexus manda a Google dos cosas: tu micrófono y la respuesta de Claude, que
/// lleva dentro lo que Claude leyó del repositorio. El techo de caracteres
/// acotó lo segundo; esto es lo único que puede cerrar las dos.
///
/// **No promete calidad, promete una respuesta.** El plan dice que si el
/// reconocimiento del sistema no entiende un encargo técnico —«corre el flow de
/// login en el simulador», con nombres de archivo y palabras en inglés— el plan
/// entero muere aquí, y es mejor que muera en unos días que en un mes. Por eso
/// esto es lo primero que se escribe y no lo último.
///
/// Dos decisiones que no son de gusto:
///
/// - **`requiresOnDeviceRecognition` en `true`, siempre.** Sin eso,
///   `SFSpeechRecognizer` manda el audio a los servidores de Apple, que es
///   cambiar un tercero por otro: no habría cerrado nada. Si el dispositivo no
///   soporta el reconocimiento local, esto **falla en vez de degradar**.
/// - **Se pide permiso de reconocimiento aparte del de micrófono.** Son dos
///   permisos distintos del sistema y el de voz no lo cubre; pedirlo tarde
///   —cuando alguien ya está hablando— sería un diálogo encima de una frase a
///   medias.
final class NexusVozLocal: NSObject {
  private static let log = Logger(subsystem: "com.katanalabs.nexus", category: "voz-local")

  private static var instancia: NexusVozLocal?

  static func register(with registrar: FlutterPluginRegistrar) {
    let vozLocal = NexusVozLocal()
    instancia = vozLocal

    let canal = FlutterMethodChannel(
      name: "com.katanalabs.nexus/voz-local",
      binaryMessenger: registrar.messenger
    )
    canal.setMethodCallHandler { llamada, resultado in
      switch llamada.method {
      case "disponible":
        resultado(vozLocal.disponible())
      case "permiso":
        vozLocal.pedirPermiso { concedido in resultado(concedido) }
      case "escuchar":
        vozLocal.escuchar(resultado)
      case "parar":
        vozLocal.parar()
        resultado(nil)
      case "decir":
        let que = (llamada.arguments as? [String: Any])?["texto"] as? String ?? ""
        vozLocal.decir(que)
        resultado(nil)
      case "callar":
        vozLocal.callar()
        resultado(nil)
      default:
        resultado(FlutterMethodNotImplemented)
      }
    }
    log.info("canal de voz local registrado")
  }

  private let sintetizador = AVSpeechSynthesizer()
  private var reconocedor: SFSpeechRecognizer?
  private var peticion: SFSpeechAudioBufferRecognitionRequest?
  private var tarea: SFSpeechRecognitionTask?
  private let motor = AVAudioEngine()

  /// Si esta máquina puede reconocer sin salir a la red.
  ///
  /// **No es lo mismo que «hay reconocedor»**: casi cualquier Mac lo tiene, y
  /// casi todos lo resuelven en los servidores de Apple. Lo que se pregunta
  /// aquí es lo único que importa para esto.
  func disponible() -> Bool {
    guard let reconocedor = SFSpeechRecognizer() else { return false }
    return reconocedor.isAvailable && reconocedor.supportsOnDeviceRecognition
  }

  func pedirPermiso(_ terminado: @escaping (Bool) -> Void) {
    SFSpeechRecognizer.requestAuthorization { estado in
      DispatchQueue.main.async { terminado(estado == .authorized) }
    }
  }

  /// Escucha una frase y devuelve **una sola vez** lo que entendió.
  ///
  /// Una frase y no un flujo: la fase 1 no lleva turnos ni interrupciones, y
  /// añadirlos antes de saber si esto entiende algo sería construir sobre una
  /// pregunta sin contestar.
  func escuchar(_ terminado: @escaping FlutterResult) {
    parar()

    guard let reconocedor = SFSpeechRecognizer(), reconocedor.supportsOnDeviceRecognition else {
      terminado(FlutterError(
        code: "sin-reconocimiento-local",
        message: "Este Mac no reconoce voz sin salir a la red",
        details: nil
      ))
      return
    }
    self.reconocedor = reconocedor

    let peticion = SFSpeechAudioBufferRecognitionRequest()
    // Lo que hace que esto tenga sentido. Con `false` el audio viaja a Apple y
    // habríamos cambiado un tercero por otro.
    peticion.requiresOnDeviceRecognition = true
    peticion.shouldReportPartialResults = false
    self.peticion = peticion

    let entrada = motor.inputNode
    entrada.installTap(onBus: 0, bufferSize: 1024, format: entrada.outputFormat(forBus: 0)) { buffer, _ in
      peticion.append(buffer)
    }

    motor.prepare()
    do {
      try motor.start()
    } catch {
      parar()
      terminado(FlutterError(code: "microfono", message: "\(error)", details: nil))
      return
    }

    var contestado = false
    tarea = reconocedor.recognitionTask(with: peticion) { [weak self] resultado, error in
      guard !contestado else { return }
      if let resultado, resultado.isFinal {
        contestado = true
        self?.parar()
        terminado(resultado.bestTranscription.formattedString)
        return
      }
      if let error {
        contestado = true
        self?.parar()
        terminado(FlutterError(code: "reconocimiento", message: "\(error)", details: nil))
      }
    }
  }

  func parar() {
    if motor.isRunning {
      motor.stop()
      motor.inputNode.removeTap(onBus: 0)
    }
    peticion?.endAudio()
    tarea?.cancel()
    peticion = nil
    tarea = nil
  }

  /// Lee un texto en voz alta con la voz del sistema.
  ///
  /// Sin elegir voz a mano: `AVSpeechSynthesisVoice` resuelve por idioma la que
  /// el usuario tenga instalada, y en macOS moderno esa es mucho mejor que
  /// cualquiera que se pudiera fijar aquí — y además la puede cambiar él desde
  /// Ajustes del sistema, que es donde espera poder hacerlo.
  func decir(_ texto: String) {
    guard !texto.isEmpty else { return }
    callar()
    let frase = AVSpeechUtterance(string: texto)
    frase.voice = AVSpeechSynthesisVoice(language: Locale.preferredLanguages.first ?? "es-ES")
    sintetizador.speak(frase)
  }

  func callar() {
    if sintetizador.isSpeaking {
      sintetizador.stopSpeaking(at: .immediate)
    }
  }
}
