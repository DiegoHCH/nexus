import AppKit
import FlutterMacOS
import Foundation
import UserNotifications
import os

/// Avisar cuando un encargo termina, si no lo estás mirando.
///
/// Un encargo de Claude dura minutos, así que lo normal es irse a otra cosa. El
/// icono de la barra dice **que sigue trabajando**; esto dice **que ya terminó**,
/// que es la otra mitad y la que te devuelve a la ventana.
final class NexusNotifications: NSObject {
  private static let log = Logger(subsystem: "com.katanalabs.nexus", category: "avisos")

  private static var asked = false
  private static let delegate = TapHandler()

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.katanalabs.nexus/notify",
      binaryMessenger: registrar.messenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "notify" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let args = (call.arguments as? [String: Any]) ?? [:]
      notify(
        title: args["title"] as? String ?? "",
        body: args["body"] as? String ?? "",
        // Devuelve si se envió, para que quien llama pueda saberlo. En el camino
        // normal no se mira: no avisar **es** el comportamiento correcto.
        then: { result($0) }
      )
    }
    UNUserNotificationCenter.current().delegate = delegate
    log.info("canal de avisos registrado")
  }

  /// Si toca avisar.
  ///
  /// **La decisión vive aquí y no en Dart** porque la verdad está en AppKit:
  /// `NSApp.isActive` sabe si la app está delante, y Flutter solo conoce el foco
  /// de sus propios widgets — con la ventana detrás pero el campo de texto
  /// «enfocado», Dart creería que la estás mirando.
  ///
  /// Avisar de algo que tienes delante es ruido, y el ruido enseña a ignorar los
  /// avisos siguientes, que son los que sí importaban.
  static func shouldNotify(appIsActive: Bool) -> Bool { !appIsActive }

  static func notify(title: String, body: String, then: @escaping (Bool) -> Void) {
    guard shouldNotify(appIsActive: NSApp.isActive) else {
      then(false)
      return
    }

    let centro = UNUserNotificationCenter.current()
    // El permiso se pide **la primera vez que haría falta**, no al arrancar: así
    // el sistema pregunta cuando la frase «Nexus quiere enviarte notificaciones»
    // tiene un motivo delante, en vez de en mitad del primer arranque.
    if !asked {
      asked = true
      centro.requestAuthorization(options: [.alert, .sound]) { concedido, error in
        if let error { log.error("permiso de avisos: \(error.localizedDescription)") }
        if concedido { entregar(title: title, body: body, then: then) } else { then(false) }
      }
      return
    }
    entregar(title: title, body: body, then: then)
  }

  private static func entregar(
    title: String, body: String, then: @escaping (Bool) -> Void
  ) {
    let contenido = UNMutableNotificationContent()
    contenido.title = title
    contenido.body = body
    contenido.sound = .default

    // `trigger: nil` es «ya»: no es un recordatorio, es el final de algo que
    // estaba pasando.
    let peticion = UNNotificationRequest(
      identifier: UUID().uuidString, content: contenido, trigger: nil
    )
    UNUserNotificationCenter.current().add(peticion) { error in
      if let error { log.error("no se pudo avisar: \(error.localizedDescription)") }
      DispatchQueue.main.async { then(error == nil) }
    }
  }
}

/// Pulsar el aviso trae Nexus al frente.
///
/// Sin esto, el aviso te dice que terminó y te deja donde estabas: hay que ir a
/// buscar la ventana igual, que es justo el paso que este aviso viene a ahorrar.
private final class TapHandler: NSObject, UNUserNotificationCenterDelegate {
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.windows.first { $0.identifier == NexusAppearance.ourMark }?
      .makeKeyAndOrderFront(nil)
    completionHandler()
  }
}
