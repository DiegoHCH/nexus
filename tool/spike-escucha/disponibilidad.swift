// Spike, parte A: ¿es viable reconocer en local, sin red y sin micrófono?
//
// Contesta tres cosas que deciden si la escucha continua se puede intentar:
//   1. ¿Existe el reconocedor para el idioma que hace falta?
//   2. ¿Soporta `requiresOnDeviceRecognition` — o sea, sin mandar nada a Apple?
//   3. ¿Acepta `contextualStrings` para sesgarlo hacia una palabra?
import Foundation
import Speech

let locales = ["es-ES", "es-CO", "es-MX", "en-US"]

print("=== reconocedores disponibles ===")
let soportados = SFSpeechRecognizer.supportedLocales().map(\.identifier)
print("total de idiomas soportados: \(soportados.count)")
for l in locales {
  let hay = soportados.contains(l)
  print("  \(l): \(hay ? "sí" : "no")")
}

print("\n=== ¿reconoce en el dispositivo, sin red? ===")
for l in locales where soportados.contains(l) {
  guard let r = SFSpeechRecognizer(locale: Locale(identifier: l)) else {
    print("  \(l): no se pudo crear")
    continue
  }
  print("  \(l): onDevice=\(r.supportsOnDeviceRecognition) disponible=\(r.isAvailable)")
}

print("\n=== autorización ===")
print("  estado actual: \(SFSpeechRecognizer.authorizationStatus().rawValue) "
      + "(0=noDeterminado 1=denegado 2=restringido 3=autorizado)")

print("\n=== la petición acepta sesgo por palabra ===")
let req = SFSpeechAudioBufferRecognitionRequest()
req.requiresOnDeviceRecognition = true
req.contextualStrings = ["Nexus", "Patricia"]
req.taskHint = .search
print("  requiresOnDeviceRecognition puesto: \(req.requiresOnDeviceRecognition)")
print("  contextualStrings: \(req.contextualStrings)")
print("  shouldReportPartialResults por defecto: \(req.shouldReportPartialResults)")
