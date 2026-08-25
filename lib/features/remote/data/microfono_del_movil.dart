import 'dart:typed_data';

import 'package:record/record.dart';

/// El micrófono del teléfono, troceado en PCM.
///
/// **El mismo formato que pide la Live API** —16 bits, 16 kHz, mono— y no uno cualquiera
/// que luego haya que convertir: convertir en medio significaría remuestrear en el Mac
/// o en el teléfono, y las dos opciones son código de audio escrito a mano para arreglar
/// una decisión que se puede tomar bien aquí, en una línea de configuración.
///
/// Detrás de una interfaz para poder probar sin micrófono: lo que hay que ejercitar es
/// **cuándo se abre, cuándo se cierra y qué se hace con los trozos**, y eso no necesita
/// una sala con alguien hablando.
abstract class Microfono {
  Future<bool> tienePermiso();

  /// Abre el micrófono. Cerrarlo es explícito —[cerrar]— y no por cancelar el stream:
  /// el paquete de captura devuelve el suyo tras un `await`, así que el gancho de cierre
  /// no puede colgar de la suscripción.
  Future<Stream<Uint8List>> escuchar();

  Future<void> cerrar();
}

class MicrofonoDelMovil implements Microfono {
  MicrofonoDelMovil([AudioRecorder? grabadora])
    : _grabadora = grabadora ?? AudioRecorder();

  final AudioRecorder _grabadora;

  @override
  Future<bool> tienePermiso() => _grabadora.hasPermission();

  @override
  Future<Stream<Uint8List>> escuchar() => _grabadora.startStream(
    const RecordConfig(
      // PCM crudo: cualquier codec —AAC, opus— habría que decodificarlo en el Mac
      // antes de dárselo a la Live API, y eso es latencia y una dependencia más para
      // ahorrar unos KB/s en una red local.
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
      // El eco del propio altavoz fuera: Nexus contesta en voz alta por el Mac, y si
      // el teléfono está cerca se oiría a sí mismo y lo mandaría de vuelta.
      echoCancel: true,
      noiseSuppress: true,
    ),
  );

  @override
  Future<void> cerrar() async {
    if (await _grabadora.isRecording()) await _grabadora.stop();
  }
}
