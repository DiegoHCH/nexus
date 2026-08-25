import 'package:flutter/foundation.dart';
import 'package:nexus/features/assistant/domain/repositories/audio_output.dart';
import 'package:nexus/features/remote/domain/remote_audio_sink.dart';
import 'package:nexus/features/remote/domain/remote_voice_source.dart';

/// El altavoz de la sesión: **el del teléfono si la pregunta vino de ahí, y si no el del
/// Mac**.
///
/// El gemelo de `VoiceInputCompartido`. Aquel elige de qué micrófono escucha la sesión;
/// este elige por dónde sale la respuesta, y con la misma regla vista del otro lado: la
/// voz suena donde se preguntó.
///
/// **La regla no cuesta un dato nuevo.** El Mac ya sabe de qué micrófono está
/// escuchando —hizo falta para arreglar la voz remota— así que aquí solo se lee.
///
/// Y evita el motivo por el que la voz no bajaba: un teléfono que reproduce a la vez que
/// el Mac serían «dos bocas». Con esta regla nunca suenan los dos, porque solo hay un
/// destino elegido por sesión.
class AudioOutputCompartido implements AudioOutput {
  AudioOutputCompartido({
    required this.local,
    required this.remoto,
    required this.fuente,
  });

  final AudioOutput local;
  final RemoteAudioSink remoto;

  /// De dónde entra la voz. Es lo que decide por dónde sale.
  final RemoteVoiceSource fuente;

  /// El destino de **esta** sesión.
  ///
  /// Se elige una vez, al arrancar, y no en cada trozo: el micrófono del teléfono se
  /// cierra a mitad —se toca el botón para dejar de hablar— y con la decisión tomada por
  /// trozo la respuesta se mudaría a los altavoces del Mac justo cuando empieza a sonar.
  /// Elegir al arrancar es seguro porque para entonces la fuente ya está abierta: el
  /// `startVoice` la enciende **antes** de arrancar la sesión, precisamente para esto.
  AudioOutput? _destino;

  AudioOutput get _elegido => _destino ?? local;

  @override
  Future<void> start() async {
    _destino = fuente.activo ? remoto : local;
    debugPrint(
      'voz · esta respuesta suena en '
      '${_destino == remoto ? 'el teléfono' : 'este Mac'}',
    );
    await _elegido.start();
  }

  @override
  void enqueue(Uint8List pcm) => _elegido.enqueue(pcm);

  @override
  Future<void> discard() => _elegido.discard();

  @override
  Future<Duration> pending() => _elegido.pending();

  @override
  Future<void> stop() async {
    await _elegido.stop();
    _destino = null;
  }
}
