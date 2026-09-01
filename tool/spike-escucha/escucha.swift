// Spike, parte B: ¿aguanta escuchando indefinidamente, y qué cuesta?
//
// Se le da audio de verdad desde el micrófono y se anota: cuánto dura la sesión
// antes de que el reconocedor la corte, con qué error, y cuánta CPU consume.
// Eso es lo que decide si la escucha continua se puede ofrecer o si hay que
// reiniciar la sesión cada N segundos — y si reiniciar deja huecos sordos.
import AVFoundation
import Foundation
import Speech

let idioma = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "es-MX"
let palabra = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "nexus"
let segundos = CommandLine.arguments.count > 3 ? Double(CommandLine.arguments[3])! : 90

let arranque = Date()
func t() -> String { String(format: "t+%.1fs", Date().timeIntervalSince(arranque)) }

// Con `open` no hay salida estándar que leer, así que se escribe a un archivo.
let registro = URL(fileURLWithPath: "/private/tmp/claude-502/-Users-diego-hoyos-Workspace-front-mobile-b2c/fa10526c-a336-4d5d-92d6-88a140455f00/scratchpad/spike/escucha.log")
func anota(_ linea: String) {
  FileHandle(forWritingAtPath: registro.path).map { h in
    h.seekToEndOfFile(); h.write((linea + "\n").data(using: .utf8)!); h.closeFile()
  }
  print(linea)
}

SFSpeechRecognizer.requestAuthorization { estado in
  guard estado == .authorized else {
    anota("\(t()) · SIN AUTORIZACIÓN (estado \(estado.rawValue)) — hace falta permiso de voz")
    exit(2)
  }
  DispatchQueue.main.async { arrancar() }
}

var motor: AVAudioEngine?
var tarea: SFSpeechRecognitionTask?
var peticion: SFSpeechAudioBufferRecognitionRequest?
var reinicios = 0
var aciertos = 0
var ultimo = ""

func arrancar() {
  guard let rec = SFSpeechRecognizer(locale: Locale(identifier: idioma)) else {
    anota("\(t()) · no hay reconocedor para \(idioma)"); exit(3)
  }
  guard rec.supportsOnDeviceRecognition else {
    anota("\(t()) · \(idioma) NO reconoce en local — se descarta"); exit(4)
  }
  anota("\(t()) · reconocedor \(idioma) listo · onDevice sí · buscando «\(palabra)»")

  let e = AVAudioEngine()
  motor = e
  let req = SFSpeechAudioBufferRecognitionRequest()
  req.requiresOnDeviceRecognition = true
  req.shouldReportPartialResults = true
  req.contextualStrings = [palabra]
  peticion = req

  tarea = rec.recognitionTask(with: req) { resultado, error in
    if let r = resultado {
      let dicho = r.bestTranscription.formattedString.lowercased()
      // 🔴 Se anota **todo lo que transcribe**, no solo lo que acierta. Si se
      // dice «Nexus» y el reconocedor oye «nexos» o «next», eso es la diferencia
      // entre «no funciona» y «hay que comparar con más holgura» — y sin verlo
      // no se puede saber cuál de las dos es.
      if dicho != ultimo {
        ultimo = dicho
        let cierra = r.isFinal ? " [final]" : ""
        anota("\(t()) · oye: «\(r.bestTranscription.formattedString)»\(cierra)")
      }
      if dicho.contains(palabra.lowercased()) {
        aciertos += 1
        anota("\(t()) · ¡ACIERTO nº \(aciertos)! en «\(r.bestTranscription.formattedString)»")
      }
    }
    if let err = error as NSError? {
      anota("\(t()) · CORTADO · dominio=\(err.domain) código=\(err.code) · \(err.localizedDescription)")
      reinicios += 1
      anota("\(t()) · reiniciando (reinicio nº \(reinicios))…")
      pararTodo()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { arrancar() }
    }
  }

  let entrada = e.inputNode
  let formato = entrada.outputFormat(forBus: 0)
  entrada.installTap(onBus: 0, bufferSize: 2048, format: formato) { buffer, _ in
    req.append(buffer)
  }
  e.prepare()
  do { try e.start() } catch {
    anota("\(t()) · el motor de audio no arrancó: \(error)"); exit(5)
  }
  anota("\(t()) · micrófono abierto a \(Int(formato.sampleRate)) Hz")
}

func pararTodo() {
  motor?.inputNode.removeTap(onBus: 0)
  motor?.stop()
  peticion?.endAudio()
  tarea?.cancel()
}

DispatchQueue.main.asyncAfter(deadline: .now() + segundos) {
  pararTodo()
  anota("=== resumen ===")
  anota("duración de la prueba: \(Int(segundos)) s")
  anota("veces que el reconocedor cortó la sesión: \(reinicios)")
  anota("veces que oyó la palabra: \(aciertos)")
  exit(0)
}
RunLoop.main.run()
