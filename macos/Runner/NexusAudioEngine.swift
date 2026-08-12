import AVFoundation
import FlutterMacOS
import os

/// Un solo `AVAudioEngine` para escuchar y hablar, con cancelación de eco.
///
/// Existe porque la separación en dos motores —`record` capturando en el suyo,
/// `flutter_pcm_sound` reproduciendo en otro— hace imposible cancelar el eco:
/// el *voice processing* de Apple exige que entrada y salida estén en el mismo
/// modo (activarlo en un nodo lo activa en el otro) y lo que cancela es la
/// salida **de su propio motor** hacia el micrófono. Con los motores separados,
/// el cancelador estaba restando el silencio de un motor que no reproducía
/// nada, mientras el altavoz del otro entraba limpio por el micro. El síntoma
/// era Gemini escuchándose a sí mismo, tomándolo por el usuario hablando
/// encima, e interrumpiéndose en bucle.
///
/// De paso resuelve lo que ese paquete costó dos veces: aquí sí se escucha
/// `AVAudioEngineConfigurationChange`, que es lo que para el motor en seco al
/// cambiar de dispositivo de audio.
final class NexusAudioEngine: NSObject, FlutterStreamHandler {
  /// Formato de captura hacia el servicio de voz: PCM 16 bits, 16 kHz, mono.
  private static let captureSampleRate = 16000.0

  /// Formato del audio que devuelve el servicio. No se negocia, siempre 24 kHz.
  private static let playbackSampleRate = 24000.0

  /// Con subsistema propio para poder filtrarlo en `log show`: el `NSLog` de una
  /// app de Flutter lanzada con `open` no aparece por ningún lado.
  private static let log = Logger(subsystem: "com.katanalabs.nexus", category: "audio")

  private let engine = AVAudioEngine()
  private let player = AVAudioPlayerNode()
  private var deliveredChunks = 0
  private var frameSink: FlutterEventSink?
  private var captureConverter: AVAudioConverter?
  private var captureMonoFormat: AVAudioFormat?
  private var playbackConverter: AVAudioConverter?

  /// Qué canal de la entrada lleva la voz ya procesada. Se descubre en los
  /// primeros bloques en vez de darlo por hecho: el agregado del cancelador
  /// coloca el micro en el canal 0 y las referencias detrás, pero el número de
  /// canales cambia de un arranque a otro.
  private var voiceChannel = 0
  private var channelProbed = false

  /// Frames entregados al altavoz que aún no han sonado. Lo toca el hilo de
  /// audio en el callback de fin de reproducción, de ahí el candado.
  private var pendingFrames: Int64 = 0
  private let pendingLock = NSLock()

  /// Cuándo arrancó el motor, para medir cuánto tarda en llegar el primer
  /// bloque de audio: es el retardo que se nota entre pulsar y poder hablar.
  private var startedAt: Date?

  /// Formato al que hay que llevar la respuesta antes de reproducirla: el del
  /// hardware, decidido al arrancar. No se puede imponer el nuestro.
  private var speakerFormat: AVAudioFormat?
  private var running = false

  private let captureFormat = AVAudioFormat(
    commonFormat: .pcmFormatInt16,
    sampleRate: NexusAudioEngine.captureSampleRate,
    channels: 1,
    interleaved: true
  )!

  /// Lo que llega del servicio de voz: PCM 16 bits, 24 kHz, mono.
  private let replyFormat = AVAudioFormat(
    commonFormat: .pcmFormatInt16,
    sampleRate: NexusAudioEngine.playbackSampleRate,
    channels: 1,
    interleaved: true
  )!

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = NexusAudioEngine()
    let methods = FlutterMethodChannel(
      name: "nexus/audio",
      binaryMessenger: registrar.messenger
    )
    methods.setMethodCallHandler { call, result in
      instance.handle(call, result: result)
    }
    let frames = FlutterEventChannel(
      name: "nexus/audio/frames",
      binaryMessenger: registrar.messenger
    )
    frames.setStreamHandler(instance)
  }

  // MARK: - Canal

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "hasPermission":
      requestPermission(result: result)
    case "start":
      do {
        try start()
        result(true)
      } catch {
        result(FlutterError(code: "start_failed", message: "\(error)", details: nil))
      }
    case "stop":
      stop()
      result(nil)
    case "play":
      guard let data = (call.arguments as? [String: Any])?["pcm"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "bad_args", message: "Falta el PCM", details: nil))
        return
      }
      enqueue(data.data)
      result(nil)
    case "clearPlayback":
      clearPlayback()
      result(nil)
    case "pendingPlaybackMs":
      result(pendingPlaybackMilliseconds())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    frameSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    frameSink = nil
    return nil
  }

  // MARK: - Permiso

  private func requestPermission(result: @escaping FlutterResult) {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      result(true)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .audio) { granted in
        DispatchQueue.main.async { result(granted) }
      }
    default:
      result(false)
    }
  }

  // MARK: - ¿Hay eco que cancelar?

  /// `true` si la salida por defecto es el **altavoz interno** del Mac.
  ///
  /// No basta con mirar el tipo de conexión: unos auriculares en el jack siguen
  /// siendo el dispositivo «integrado», y lo que cambia es la *fuente* de datos
  /// —`ispk` (altavoz) frente a `hdpn` (auriculares)—. Por eso se mira también
  /// esa fuente, o los auriculares de cable pasarían por altavoces.
  private func outputIsBuiltInSpeaker() -> Bool {
    var device = AudioDeviceID(0)
    var deviceSize = UInt32(MemoryLayout<AudioDeviceID>.size)
    var deviceAddress = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    guard AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &deviceAddress, 0, nil, &deviceSize, &device
    ) == noErr else { return false }

    var transport = UInt32(0)
    var transportSize = UInt32(MemoryLayout<UInt32>.size)
    var transportAddress = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyTransportType,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    guard AudioObjectGetPropertyData(
      device, &transportAddress, 0, nil, &transportSize, &transport
    ) == noErr, transport == kAudioDeviceTransportTypeBuiltIn else { return false }

    var source = UInt32(0)
    var sourceSize = UInt32(MemoryLayout<UInt32>.size)
    var sourceAddress = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyDataSource,
      mScope: kAudioObjectPropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain
    )
    guard AudioObjectGetPropertyData(
      device, &sourceAddress, 0, nil, &sourceSize, &source
    ) == noErr else {
      // Integrado y sin fuente declarada: es el altavoz.
      return true
    }

    // 'ispk' = altavoz interno. Cualquier otra cosa ('hdpn' y demás) sale por
    // algo enchufado, así que no hay eco.
    let internalSpeaker: UInt32 = 0x6973_706B
    return source == internalSpeaker
  }

  // MARK: - Motor

  private func start() throws {
    if running { return }
    let begin = Date()

    // El cancelador solo se enciende si la respuesta va a salir por los
    // altavoces del Mac, porque solo entonces hay eco físico que cancelar. Con
    // auriculares no existe esa fuga, y encenderlo igual **rompe la captura**:
    // medido, la entrada llega ~100 veces más baja (picos de 8 sobre 32768
    // frente a 2400 con el micro interno) porque el cancelador resta contra una
    // referencia que ya no corresponde a lo que se oye.
    let cancelEcho = outputIsBuiltInSpeaker()
    try engine.inputNode.setVoiceProcessingEnabled(cancelEcho)
    Self.log.info("""
      t+\(Int(Date().timeIntervalSince(begin) * 1000), privacy: .public) ms · \
      cancelación de eco \(cancelEcho ? "activada" : "desactivada (salida no es el altavoz interno)", privacy: .public)
      """)

    // El cancelador de eco exige que **el formato de cliente de entrada y el de
    // salida coincidan** —lo dice literalmente al fallar: «client-side input and
    // output formats do not match (err=-10875)»—. Y el hardware de un portátil
    // es micrófono mono contra altavoces estéreo, así que por defecto nunca
    // coinciden: 1 canal contra 2.
    //
    // La salida no se puede cambiar en el dispositivo, pero sí el formato con
    // el que se le habla: forzando **mono en toda la cadena interna**, los dos
    // lados del cancelador cuadran y el propio nodo de salida se encarga de
    // repartir ese mono en los dos altavoces.
    let inputFormat = engine.inputNode.outputFormat(forBus: 0)
    let voiceFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: inputFormat.sampleRate > 0 ? inputFormat.sampleRate : 48000,
      channels: 1,
      interleaved: false
    )!

    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: voiceFormat)
    engine.connect(engine.mainMixerNode, to: engine.outputNode, format: voiceFormat)

    speakerFormat = voiceFormat
    playbackConverter = AVAudioConverter(from: replyFormat, to: voiceFormat)

    // El conversor se crea desde **mono** al ritmo de la entrada, no desde el
    // formato del nodo. Con el cancelador activo ese formato trae varios
    // canales —9 en un arranque, 3 en el siguiente: micro procesado más
    // referencias— y pedirle a `AVAudioConverter` que mezcle 9 en 1 devolvía
    // silencio absoluto. El canal se extrae a mano antes de convertir, así que
    // aquí solo queda el cambio de ritmo, que no depende de cuántos canales
    // decida exponer el agregado esta vez.
    let monoInput = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: inputFormat.sampleRate > 0 ? inputFormat.sampleRate : 48000,
      channels: 1,
      interleaved: false
    )!
    captureMonoFormat = monoInput
    captureConverter = AVAudioConverter(from: monoInput, to: captureFormat)
    Self.log.info("""
      arranque · entrada \(inputFormat.sampleRate, privacy: .public) Hz \
      \(inputFormat.channelCount, privacy: .public) ch · voz \
      \(voiceFormat.sampleRate, privacy: .public) Hz \
      \(voiceFormat.channelCount, privacy: .public) ch
      """)

    engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
      self?.deliver(buffer)
    }

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(configurationChanged),
      name: .AVAudioEngineConfigurationChange,
      object: engine
    )

    engine.prepare()
    Self.log.info("t+\(Int(Date().timeIntervalSince(begin) * 1000), privacy: .public) ms · grafo preparado")
    try engine.start()
    player.play()
    running = true
    startedAt = Date()
    Self.log.info("t+\(Int(Date().timeIntervalSince(begin) * 1000), privacy: .public) ms · motor en marcha")
  }

  private func stop() {
    guard running else { return }
    running = false

    NotificationCenter.default.removeObserver(
      self,
      name: .AVAudioEngineConfigurationChange,
      object: engine
    )
    player.stop()
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    engine.detach(player)
    captureConverter = nil
    captureMonoFormat = nil
    playbackConverter = nil
    speakerFormat = nil
    // El agregado se reconstruye al arrancar y puede colocar la voz en otro
    // canal, así que la medición no se hereda.
    channelProbed = false
    voiceChannel = 0

    // Se apaga el voice processing al cerrar: si se queda encendido, el
    // dispositivo agregado sigue montado y otras apps notan el cambio de
    // ganancia sin motivo. También hace que el siguiente arranque vuelva a
    // decidir si hace falta, que es lo que permite cambiar de auriculares a
    // altavoces sin reiniciar la app.
    try? engine.inputNode.setVoiceProcessingEnabled(false)
  }

  /// El motor se para solo cuando cambia la configuración del IO unit —unos
  /// AirPods a media conversación, cambiar de salida—. Sin esto, la captura
  /// enmudece para siempre sin lanzar un solo error: es el fallo que en Dart
  /// había que adivinar por ausencia de audio.
  @objc private func configurationChanged(_ notification: Notification) {
    guard running else { return }
    stop()
    do {
      try start()
    } catch {
      frameSink?(FlutterError(
        code: "engine_restart_failed",
        message: "El motor de audio no volvió tras el cambio de configuración: \(error)",
        details: nil
      ))
    }
  }

  // MARK: - Captura

  private func deliver(_ buffer: AVAudioPCMBuffer) {
    guard let sink = frameSink,
          let converter = captureConverter,
          let monoFormat = captureMonoFormat,
          let channels = buffer.floatChannelData else { return }

    let channelCount = Int(buffer.format.channelCount)
    let frames = Int(buffer.frameLength)
    guard frames > 0, channelCount > 0 else { return }

    // ¿Dónde viene la voz? Se mide una vez, sobre un bloque con señal, y se
    // deja fijado. Sin esto habría que confiar en que el canal 0 del agregado
    // es siempre el micro procesado, y el propio recuento de canales ya
    // demostró que este agregado no es de fiar.
    if !channelProbed {
      var loudest = 0
      var loudestPeak: Float = 0
      var peaks: [String] = []
      for channel in 0..<channelCount {
        var peak: Float = 0
        for index in 0..<frames {
          let magnitude = abs(channels[channel][index])
          if magnitude > peak { peak = magnitude }
        }
        peaks.append(String(format: "%d:%.3f", channel, peak))
        if peak > loudestPeak {
          loudestPeak = peak
          loudest = channel
        }
      }
      if loudestPeak > 0.001 {
        voiceChannel = loudest
        channelProbed = true
        Self.log.info("canal de voz = \(loudest, privacy: .public) · picos \(peaks.joined(separator: " "), privacy: .public)")
      }
    }

    let channel = min(voiceChannel, channelCount - 1)

    // El bloque multicanal se reduce a mono copiando el canal que lleva la voz.
    guard let mono = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: buffer.frameLength),
          let monoData = mono.floatChannelData else { return }
    mono.frameLength = buffer.frameLength
    monoData[0].update(from: channels[channel], count: frames)

    let ratio = captureFormat.sampleRate / monoFormat.sampleRate
    let capacity = AVAudioFrameCount((Double(frames) * ratio).rounded(.up)) + 1
    guard let converted = AVAudioPCMBuffer(pcmFormat: captureFormat, frameCapacity: capacity) else { return }

    var consumed = false
    var error: NSError?
    converter.convert(to: converted, error: &error) { _, status in
      // El conversor pide de a poco: se le entrega este bloque una sola vez y
      // después se le dice que no hay más, o se queda pidiendo en bucle.
      if consumed {
        status.pointee = .noDataNow
        return nil
      }
      consumed = true
      status.pointee = .haveData
      return mono
    }

    if let error {
      Self.log.error("conversión de captura falló: \(error.localizedDescription, privacy: .public)")
      return
    }
    guard let channel = converted.int16ChannelData else {
      Self.log.error("el buffer convertido no trae canal Int16")
      return
    }
    let byteCount = Int(converted.frameLength) * 2
    guard byteCount > 0 else {
      Self.log.error("conversión de captura devolvió 0 frames (entrada \(buffer.frameLength, privacy: .public))")
      return
    }

    // Un pico por bloque, una vez por segundo: distingue "no llega audio" de
    // "llega silencio", que se parecen mucho desde fuera y se arreglan distinto.
    deliveredChunks += 1
    if let startedAt {
      Self.log.info("t+\(Int(Date().timeIntervalSince(startedAt) * 1000), privacy: .public) ms · primer bloque de audio")
      self.startedAt = nil
    }
    if deliveredChunks % 15 == 0 {
      var peak: Int16 = 0
      for index in 0..<Int(converted.frameLength) {
        let value = channel[0][index]
        let magnitude = value == Int16.min ? Int16.max : abs(value)
        if magnitude > peak { peak = magnitude }
      }
      Self.log.info("captura · \(self.deliveredChunks, privacy: .public) bloques, pico \(peak, privacy: .public)")
    }

    let data = Data(bytes: channel[0], count: byteCount)
    DispatchQueue.main.async { sink(FlutterStandardTypedData(bytes: data)) }
  }

  // MARK: - Reproducción

  /// Encola PCM de 16 bits a 24 kHz, resampleado al ritmo del altavoz.
  private func enqueue(_ pcm: Data) {
    guard running, pcm.count >= 2,
          let converter = playbackConverter,
          let speaker = speakerFormat else { return }

    let frames = AVAudioFrameCount(pcm.count / 2)
    guard let source = AVAudioPCMBuffer(pcmFormat: replyFormat, frameCapacity: frames),
          let target = source.int16ChannelData else { return }
    source.frameLength = frames

    pcm.withUnsafeBytes { raw in
      // Sin asumir alineación: el bloque puede venir de una vista con offset
      // impar y `load(as: Int16.self)` reventaría. Se leen los dos bytes y se
      // arma la muestra a mano, little-endian, como manda el formato.
      let bytes = raw.bindMemory(to: UInt8.self)
      for index in 0..<Int(frames) {
        let low = UInt16(bytes[index * 2])
        let high = UInt16(bytes[index * 2 + 1])
        target[0][index] = Int16(bitPattern: low | (high << 8))
      }
    }

    let ratio = speaker.sampleRate / replyFormat.sampleRate
    let capacity = AVAudioFrameCount((Double(frames) * ratio).rounded(.up)) + 1
    guard let converted = AVAudioPCMBuffer(pcmFormat: speaker, frameCapacity: capacity) else { return }

    var consumed = false
    var error: NSError?
    converter.convert(to: converted, error: &error) { _, status in
      if consumed {
        status.pointee = .noDataNow
        return nil
      }
      consumed = true
      status.pointee = .haveData
      return source
    }
    if error != nil || converted.frameLength == 0 { return }

    // Se lleva la cuenta de lo que queda por sonar porque el servicio entrega
    // el audio más rápido que en tiempo real: cuando deja de llegar, el
    // altavoz todavía tiene frases enteras en la cola. Sin este dato, quien
    // decide cuándo cerrar la sesión creería que ya no pasa nada.
    let frameCount = Int64(converted.frameLength)
    pendingLock.lock()
    pendingFrames += frameCount
    pendingLock.unlock()

    player.scheduleBuffer(converted, completionCallbackType: .dataPlayedBack) { [weak self] _ in
      guard let self else { return }
      self.pendingLock.lock()
      self.pendingFrames = max(0, self.pendingFrames - frameCount)
      self.pendingLock.unlock()
    }
    if !player.isPlaying { player.play() }
  }

  /// Cuánto audio queda por sonar, en milisegundos.
  private func pendingPlaybackMilliseconds() -> Int {
    guard let speaker = speakerFormat, speaker.sampleRate > 0 else { return 0 }
    pendingLock.lock()
    let frames = pendingFrames
    pendingLock.unlock()
    return Int((Double(frames) / speaker.sampleRate) * 1000)
  }

  /// Tira lo que quede por sonar. A diferencia de una cola en Dart, aquí el
  /// corte es inmediato: `stop()` descarta los buffers ya programados, así que
  /// interrumpir no deja coleta audible.
  private func clearPlayback() {
    guard running else { return }
    player.stop()
    pendingLock.lock()
    pendingFrames = 0
    pendingLock.unlock()
    player.play()
  }
}
