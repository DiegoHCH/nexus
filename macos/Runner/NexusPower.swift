import FlutterMacOS
import Foundation
import IOKit.pwr_mgt
import os

/// Impedir que el Mac se duerma solo mientras hay un encargo en curso.
///
/// Un encargo puede llevarse minutos sin que nadie toque el teclado —eso es
/// justamente para lo que sirve—, así que el contador de inactividad del
/// sistema corre entero. Si el Mac se suspende a mitad, el proceso de Claude se
/// congela y la sesión de voz se cae con él: al despertar no hay ni respuesta
/// ni error, solo un encargo que nunca volvió.
///
/// Se pide **solo** que no se suspenda el sistema, no que la pantalla siga
/// encendida. Que se apague la pantalla mientras trabaja es lo que uno espera;
/// mantenerla viva sería gastarle batería para enseñarle un orbe que no está
/// mirando.
///
/// Lo que esto **no** puede: cerrar la tapa duerme el Mac igual. Ninguna
/// aplicación puede impedirlo, así que no se promete.
final class NexusPower {
  private static let log = Logger(subsystem: "com.katanalabs.nexus", category: "energia")

  /// La que está viva ahora mismo, si hay alguna. Una sola: quién la pidió y
  /// cuántas veces se lleva en Dart, que es donde se sabe cuántos encargos
  /// corren a la vez.
  private static var assertion: IOPMAssertionID?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.katanalabs.nexus/power",
      binaryMessenger: registrar.messenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "keepAwake":
        let reason = (call.arguments as? [String: Any])?["reason"] as? String ?? "Nexus"
        result(keepAwake(reason: reason))
      case "allowSleep":
        allowSleep()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    log.info("canal de energía registrado")
  }

  /// Idempotente: pedirlo dos veces no crea dos, porque el recuento de quién la
  /// necesita vive en Dart y aquí solo interesa que exista mientras haga falta.
  private static func keepAwake(reason: String) -> Bool {
    if assertion != nil { return true }

    var id: IOPMAssertionID = IOPMAssertionID(0)
    // El nombre sale literal en `pmset -g assertions`, así que dice qué se está
    // haciendo y no «Nexus»: quien vaya a mirar por qué su Mac no se duerme
    // merece encontrar la respuesta ahí, no en el código.
    let status = IOPMAssertionCreateWithName(
      kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
      IOPMAssertionLevel(kIOPMAssertionLevelOn),
      reason as CFString,
      &id
    )
    guard status == kIOReturnSuccess else {
      log.error("no se pudo pedir · \(status)")
      return false
    }

    assertion = id
    log.info("despierto · \(reason, privacy: .public)")
    return true
  }

  private static func allowSleep() {
    guard let id = assertion else { return }
    IOPMAssertionRelease(id)
    assertion = nil
    log.info("puede dormirse")
  }
}
