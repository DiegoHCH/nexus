// Spike, parte C: qué nombre acierta mejor como palabra de activación.
//
// Varios candidatos en una sola sesión. Se anota **cada transcripción** y, por
// candidato, cuántas veces apareció exacto. Lo que se busca no es solo quién
// gana: es ver los casi-aciertos, porque ahí está el problema real —«Nexus» se
// oye «nexos», que es una palabra española normal, así que con holgura despierta
// solo y sin holgura pierde llamadas.
import AVFoundation
import Foundation
import Speech

let candidatos = ["hestia", "patricia", "orión"]
let segundos = CommandLine.arguments.count > 1 ? Double(CommandLine.arguments[1])! : 120

let registro = URL(fileURLWithPath: "/private/tmp/claude-502/-Users-diego-hoyos-Workspace-front-mobile-b2c/fa10526c-a336-4d5d-92d6-88a140455f00/scratchpad/spike/nombres.log")
let arranque = Date()
var aciertos: [String: Int] = [:]
var vistas = Set<String>()
var motor: AVAudioEngine?
var tarea: SFSpeechRecognitionTask?
var peticion: SFSpeechAudioBufferRecognitionRequest?

func anota(_ l: String) {
  FileHandle(forWritingAtPath: registro.path).map { h in
    h.seekToEndOfFile(); h.write((l + "\n").data(using: .utf8)!); h.closeFile()
  }
}
func t() -> String { String(format: "t+%.1fs", Date().timeIntervalSince(arranque)) }

SFSpeechRecognizer.requestAuthorization { estado in
  guard estado == .authorized else { anota("SIN AUTORIZACIÓN"); exit(2) }
  DispatchQueue.main.async { arrancar() }
}

func arrancar() {
  guard let rec = SFSpeechRecognizer(locale: Locale(identifier: "es-MX")),
        rec.supportsOnDeviceRecognition else { anota("sin reconocedor local"); exit(3) }

  let e = AVAudioEngine(); motor = e
  let req = SFSpeechAudioBufferRecognitionRequest()
  req.requiresOnDeviceRecognition = true
  req.shouldReportPartialResults = true
  // Todos los candidatos sesgados a la vez. En producción sería solo el elegido,
  // así que esto **reparte** el sesgo y da una medida algo pesimista — lo cual
  // está bien: un nombre que gana aquí gana más aún cuando es el único.
  req.contextualStrings = candidatos
  peticion = req

  tarea = rec.recognitionTask(with: req) { resultado, error in
    if let r = resultado {
      let dicho = r.bestTranscription.formattedString.lowercased()
      // Solo la última palabra nueva, para no repetir la transcripción entera.
      let palabras = dicho.split(separator: " ").map(String.init)
      if let ultima = palabras.last, !vistas.contains(dicho) {
        vistas.insert(dicho)
        var marca = ""
        for c in candidatos where ultima.contains(c) || c.contains(ultima) {
          if ultima == c { aciertos[c, default: 0] += 1; marca = " ← ACIERTA «\(c)»" }
          else { marca = " ← casi «\(c)»" }
        }
        anota("\(t()) · «\(ultima)»\(marca)")
      }
    }
    if let err = error as NSError? {
      anota("\(t()) · sesión cortada (código \(err.code)) · reiniciando")
      motor?.inputNode.removeTap(onBus: 0); motor?.stop()
      peticion?.endAudio(); tarea?.cancel()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { arrancar() }
    }
  }

  let entrada = e.inputNode
  entrada.installTap(onBus: 0, bufferSize: 2048, format: entrada.outputFormat(forBus: 0)) { b, _ in
    req.append(b)
  }
  e.prepare()
  try? e.start()
  anota("\(t()) · escuchando · candidatos: \(candidatos.joined(separator: ", "))")
}

DispatchQueue.main.asyncAfter(deadline: .now() + segundos) {
  motor?.inputNode.removeTap(onBus: 0); motor?.stop(); peticion?.endAudio(); tarea?.cancel()
  anota("\n=== marcador ===")
  for c in candidatos {
    anota("  \(c.padding(toLength: 10, withPad: " ", startingAt: 0)) \(aciertos[c] ?? 0) aciertos exactos")
  }
  exit(0)
}
RunLoop.main.run()
