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

  /// Cuándo se quedó la cola del altavoz a cero teniendo aún respuesta por
  /// delante. Es la medida que falta para decidir el tamaño del colchón: con
  /// buena conexión no ocurre nunca, y con mala es exactamente el corte que se
  /// oye. Se anota aquí porque el dato solo existe en una sesión real —no hay
  /// forma de fabricarlo— y sin él, cambiar el número sería adivinar.
  private var starvedAt: Date?

  private var gapCount = 0
  private var worstGapMs = 0
  private var playedAnything = false

  /// El motor sigue montado, pero la conversación terminó: **no se entrega ni
  /// un bloque de audio a nadie**. Es la diferencia entre tener el micrófono
  /// abierto en local y estar escuchando.
  private var listening = false

  /// Lo que desmonta el motor cuando se cumple el minuto de espera. Se guarda
  /// para poder cancelarlo si vuelves a hablarle antes.
  private var teardownWork: DispatchWorkItem?

  /// Cuánto se queda el motor caliente después de colgar.
  ///
  /// Montar el dispositivo agregado del cancelador de eco cuesta ~1,3 s de los
  /// 1,76 s que tardaba en poder hablar, y solo se ahorra teniéndolo ya
  /// montado. Un minuto cubre el caso real —seguir hablándole— sin dejar el
  /// micrófono abierto toda la sesión. Decisión del usuario, no técnica: las
  /// tres opciones estaban sobre la mesa y esta es la elegida.
  private static let warmSeconds = 60.0

  /// Por dónde suena la respuesta, si el usuario eligió un aparato concreto.
  ///
  /// `nil` es «el que diga el sistema», que es lo correcto por defecto: cambiar
  /// de auriculares en macOS ya cambia la salida de todo, y una app que se
  /// empeña en la suya es la que se queda sonando por el altavoz cuando te
  /// pones los cascos.
  private var preferredOutput: AudioDeviceID?

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
    // Consultar **sin preguntar**, que es lo que `hasPermission` no puede hacer:
    // ese pide acceso cuando nadie lo ha decidido todavía, y eso está bien en la
    // pantalla de configuración —donde el usuario acaba de pulsar «Solicitar»—
    // pero no para mirar el estado antes de abrir la voz. Además hacen falta los
    // tres estados: «denegado» se arregla en Ajustes del sistema y «sin decidir»
    // se arregla preguntando, y decir lo mismo en los dos casos manda a la gente
    // al sitio equivocado.
    case "permissionStatus":
      result(permissionStatus())
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
    case "outputDevices":
      result(outputDevices())
    case "setOutputDevice":
      let id = (call.arguments as? [String: Any])?["id"] as? Int
      preferredOutput = id.map(AudioDeviceID.init)
      // Se desmonta para que el siguiente arranque use el aparato nuevo: el
      // dispositivo se fija al construir el grafo, no se puede cambiar con el
      // motor en marcha.
      teardown()
      result(nil)
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

  /// El estado del permiso, sin provocar el diálogo del sistema.
  private func permissionStatus() -> String {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized: return "granted"
    case .notDetermined: return "notAsked"
    // `restricted` cae aquí a propósito: lo pone una política del dispositivo y
    // desde la app no se puede cambiar, así que para quien mira es lo mismo que
    // denegado — hay que ir a otro sitio.
    default: return "denied"
    }
  }

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
    // Con un aparato elegido a mano, la pregunta es sobre **ese**: si suena por
    // unos altavoces USB no hay eco del altavoz interno que cancelar, y
    // encender el cancelador contra la referencia equivocada rompe la captura
    // —medido: la entrada llega ~100 veces más baja—.
    isBuiltInSpeaker(preferredOutput ?? defaultOutputDevice())
  }

  private func isBuiltInSpeaker(_ device: AudioDeviceID) -> Bool {
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

  /// Los aparatos por los que se puede sacar sonido, con su nombre.
  ///
  /// Se filtran los que **no tienen canales de salida**: en el sistema hay
  /// dispositivos de solo entrada —el micrófono, el agregado del cancelador— y
  /// ofrecerlos como altavoz sería ofrecer algo que no puede sonar.
  private func outputDevices() -> [[String: Any]] {
    var size = UInt32(0)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    guard AudioObjectGetPropertyDataSize(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
    ) == noErr else { return [] }

    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var ids = [AudioDeviceID](repeating: 0, count: count)
    guard AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
    ) == noErr else { return [] }

    let byDefault = defaultOutputDevice()
    return ids.compactMap { id in
      guard hasOutput(id), let name = deviceName(id) else { return nil }
      return [
        "id": Int(id),
        "name": name,
        "isDefault": id == byDefault,
      ]
    }
  }

  private func hasOutput(_ device: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreamConfiguration,
      mScope: kAudioDevicePropertyScopeOutput,
      mElement: kAudioObjectPropertyElementMain
    )
    var size = UInt32(0)
    guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr,
          size > 0
    else { return false }

    let buffer = UnsafeMutableRawPointer.allocate(
      byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment
    )
    defer { buffer.deallocate() }
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, buffer) == noErr
    else { return false }

    let list = UnsafeMutableAudioBufferListPointer(
      buffer.assumingMemoryBound(to: AudioBufferList.self)
    )
    return list.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
  }

  private func deviceName(_ device: AudioDeviceID) -> String? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioObjectPropertyName,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var name: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr
    else { return nil }
    return name as String
  }

  private func defaultOutputDevice() -> AudioDeviceID {
    var device = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
    )
    return device
  }

  // MARK: - Motor

  private func start() throws {
    // Vuelve a hablar antes de que se cumpla el minuto: el motor ya está
    // montado y solo hay que volver a escuchar. Es el atajo entero — sin esto,
    // aquí empezaría otra vez el 1,3 s del dispositivo agregado.
    teardownWork?.cancel()
    teardownWork = nil
    if running {
      listening = true
      startedAt = Date()
      Self.log.info("motor caliente reutilizado · sin montar el agregado")
      return
    }
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
    // El aparato elegido se fija **antes** de tocar el grafo: cambiarlo con el
    // motor montado no vale, y por eso elegir otro desmonta el motor.
    if let preferred = preferredOutput {
      do {
        try engine.outputNode.auAudioUnit.setDeviceID(preferred)
        Self.log.info("salida fijada al aparato \(preferred, privacy: .public)")
      } catch {
        Self.log.error(
          "no se pudo usar el aparato elegido: \(error.localizedDescription, privacy: .public)"
        )
      }
    }

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

    // **Se quita cualquier tap antes de poner el nuevo.** AVFAudio exige que no haya
    // ninguno —`required condition is false: nullptr == Tap()`— y **mata la app** si lo
    // hay: no lanza un error que se pueda atrapar en Swift, tira una NSException que
    // termina el proceso. Quitarlo cuando no hay ninguno es inofensivo, así que esta
    // línea convierte un cierre de la app en nada.
    //
    // Pasó de verdad: hablando desde el teléfono, los ciclos de abrir y cerrar el
    // micrófono provocan avisos de cambio de configuración, y dos solapados dejaban un
    // tap puesto y otro instalándose.
    engine.inputNode.removeTap(onBus: 0)
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
    listening = true
    startedAt = Date()
    Self.log.info("t+\(Int(Date().timeIntervalSince(begin) * 1000), privacy: .public) ms · motor en marcha")
  }

  /// Colgar: se deja de escuchar **ya**, y el motor se desmonta al cabo de un
  /// minuto por si vuelves a hablarle.
  ///
  /// La distinción es la que importa: desde este instante no sale ni un bloque
  /// de audio de la máquina —ni al servicio de voz ni a ninguna parte—. Lo que
  /// sigue montado un rato es el aparato local, y eso macOS lo enseña con su
  /// indicador de micrófono encendido: es honesto que se vea, porque el
  /// micrófono está efectivamente abierto.
  private func stop() {
    guard running, listening else { return }
    listening = false
    player.stop()

    // El resumen de la sesión, aunque sea para decir que no hubo cortes: «cero
    // huecos con buena conexión» es justo el dato de referencia contra el que
    // se lee una sesión mala.
    pendingLock.lock()
    let gaps = gapCount
    let worst = worstGapMs
    gapCount = 0
    worstGapMs = 0
    starvedAt = nil
    playedAnything = false
    pendingFrames = 0
    pendingLock.unlock()
    Self.log.info(
      "reproducción · \(gaps, privacy: .public) huecos, el peor de \(worst, privacy: .public) ms"
    )

    let work = DispatchWorkItem { [weak self] in self?.teardown() }
    teardownWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.warmSeconds, execute: work)
  }

  /// Desmontar de verdad. Ocurre al cumplirse el minuto sin que vuelvas a
  /// hablar, no al colgar.
  /// Si ya se está reiniciando por un cambio de configuración.
  ///
  /// Dos reinicios solapados terminaban el proceso, y el aviso llega por una cola de
  /// despacho: puede repetirse antes de que el primero acabe.
  private var restarting = false

  private func teardown() {
    guard running else { return }
    running = false
    listening = false
    teardownWork = nil
    Self.log.info("motor desmontado tras \(Int(Self.warmSeconds), privacy: .public) s sin uso")

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
    // **Uno a la vez, y en el hilo principal.** El aviso llega desde una cola de
    // despacho, así que dos pueden solaparse: los dos pasan el `guard running`, el
    // primero desmonta —y con eso `running` ya es falso— así que el segundo no
    // desmonta nada, y los dos llaman a `start()`. El segundo se encontraba el tap del
    // primero y AVFAudio terminaba el proceso.
    if !Thread.isMainThread {
      DispatchQueue.main.async { [weak self] in
        self?.configurationChanged(notification)
      }
      return
    }
    guard !restarting else {
      Self.log.info("cambio de configuración mientras ya se reiniciaba: se ignora")
      return
    }
    guard running else { return }
    restarting = true
    defer { restarting = false }
    // Se desmonta de verdad, no se deja caliente: cambió el aparato, así que
    // el grafo entero —formatos, canal de voz, cancelador— hay que rehacerlo.
    // Reutilizarlo sería quedarse hablándole al dispositivo que ya no está.
    let wasListening = listening
    teardown()
    guard wasListening else { return }
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
    // Con el motor caliente pero la conversación colgada, el bloque se
    // descarta aquí mismo: ni se convierte ni se mira. El micrófono está
    // abierto en el aparato; lo que no hay es nadie escuchando.
    guard listening else { return }
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
    // Colgado no se reproduce nada, aunque el motor siga montado: una frase
    // que llegara tarde sonaría después de haber cerrado la conversación.
    guard running, listening, pcm.count >= 2,
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
    // Si la cola se había vaciado y ya sonaba una respuesta, esto que llega
    // llega tarde: el altavoz estuvo callado en medio de una frase.
    if let gap = HuecoDeReproduccion.mide(
      vaciaDesde: starvedAt, ahora: Date(), yaSono: playedAnything
    ) {
      gapCount += 1
      worstGapMs = max(worstGapMs, gap)
      Self.log.info("playback gap \(gap, privacy: .public) ms (\(self.gapCount, privacy: .public) en esta sesión)")
    }
    starvedAt = nil
    pendingFrames += frameCount
    playedAnything = true
    pendingLock.unlock()

    player.scheduleBuffer(converted, completionCallbackType: .dataPlayedBack) { [weak self] _ in
      guard let self else { return }
      self.pendingLock.lock()
      self.pendingFrames = max(0, self.pendingFrames - frameCount)
      if self.pendingFrames == 0 { self.starvedAt = Date() }
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
    // Interrumpir vacía la cola a propósito: eso no es un hueco de red y
    // contarlo como tal estropearía la medida justo en las sesiones con más
    // interrupciones.
    starvedAt = nil
    playedAnything = false
    pendingLock.unlock()
    player.play()
  }
}

/// Cuándo un bloque que llega tarde es **un corte a media frase** y cuándo es
/// simplemente el rato entre dos respuestas.
///
/// Vive fuera del motor porque es la única parte de todo esto que no necesita
/// hardware: recibe dos fechas y un booleano. Y necesita estar fuera porque es
/// la que puede empezar a contar basura sin que nadie lo note — el número que
/// produce es el que decide el tamaño del colchón, y un número sucio ensucia
/// justo la conclusión que se quiere sacar.
enum HuecoDeReproduccion {
  /// Por encima de esto ya no es un corte: es que la respuesta se acabó. Dos
  /// segundos porque ninguna frase hablada deja ese silencio dentro.
  ///
  /// El número sale de una medición, no de una intuición: sin el tope, la
  /// primera apuntó un «hueco» de 9,5 s que era el rato entre una respuesta y
  /// la siguiente.
  static let maxMs = 2000

  /// Los milisegundos del corte, o `nil` si esto no cuenta como corte.
  ///
  /// - `vaciaDesde` a `nil`: la cola nunca llegó a vaciarse, así que no hubo
  ///   silencio que medir.
  /// - `yaSono` en `false`: es el primer bloque de la sesión. El silencio de
  ///   antes de empezar a hablar no es un corte, es esperar.
  static func mide(vaciaDesde: Date?, ahora: Date, yaSono: Bool) -> Int? {
    guard let vaciaDesde, yaSono else { return nil }
    let ms = Int(ahora.timeIntervalSince(vaciaDesde) * 1000)
    return ms < maxMs ? ms : nil
  }
}
