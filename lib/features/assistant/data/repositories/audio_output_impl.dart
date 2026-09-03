import 'dart:typed_data';

import 'package:nexus/features/assistant/data/datasources/native_audio_data_source.dart';
import 'package:nexus/features/assistant/domain/repositories/audio_output.dart';

/// Reproduce el audio de la respuesta por el motor nativo.
///
/// Ya no hay cola en Dart. La había porque el paquete anterior no sabía vaciar
/// la suya, así que había que mantenerla de este lado para poder tirarla al
/// interrumpir — a cambio de una coleta audible de ~150 ms, lo ya entregado al
/// sistema. El nodo reproductor nativo descarta sus propios buffers
/// programados, así que la cola sobra y el corte es inmediato.
class AudioOutputImpl implements AudioOutput {
  AudioOutputImpl(this._audio, {required this.para});

  /// A qué viene quien va a hablar por aquí.
  ///
  /// 🔴 **Obligatorio y no con valor por defecto**, y no por gusto: en una
  /// conversación **el altavoz se pide antes que el micrófono**
  /// —`hold_voice_conversation.dart`, el `(_output.start(), _gateway.connect())`
  /// en paralelo— así que un `hablar` por defecto montaría el grafo de solo
  /// salida y el micrófono lo tiraría abajo un instante después para rehacerlo
  /// entero. Serían 1,3 s del dispositivo agregado en cada conversación, y el
  /// que los paga no es quien elige el valor por defecto.
  ///
  /// Con dos sitios que lo construyen, obligar a decirlo cuesta dos palabras y
  /// ahorra ese fallo.
  final ParaQue para;

  /// Milisegundos que se retiene el audio, a propósito, para reproducir una
  /// red mala sin depender de tener una.
  ///
  /// Vale 0 salvo que se compile con `--dart-define=NEXUS_PLAYBACK_STALL_MS=…`,
  /// y siendo constante el compilador se lleva por delante todo lo de abajo en
  /// una compilación normal. Existe porque la deuda b3 estaba esperando a que
  /// tocara una conexión mala —«hasta medirlo no se toca»— y esperar a tener
  /// mala suerte no es un plan: así el corte se provoca cuando uno quiere y se
  /// mide con el contador de huecos que ya lleva el motor.
  static const _stallMs = int.fromEnvironment('NEXUS_PLAYBACK_STALL_MS');

  /// Cada cuántos trozos se provoca ese parón. Uno de cada diez son unos dos
  /// segundos de respuesta entre tirón y tirón.
  static const _stallEvery = int.fromEnvironment(
    'NEXUS_PLAYBACK_STALL_EVERY',
    defaultValue: 10,
  );

  final NativeAudioDataSource _audio;
  bool _started = false;
  int _chunks = 0;

  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _audio.acquire(para: para);
  }

  @override
  void enqueue(Uint8List pcm) {
    if (!_started || pcm.isEmpty) return;
    // Camino normal: el trozo va al altavoz en cuanto llega.
    if (_stallMs <= 0) {
      _audio.play(pcm);
      return;
    }
    // Camino de medición: cada tantos trozos, este llega tarde. No se pierde
    // ninguno —una red mala retrasa, no borra— y el orden se conserva, que es
    // justo lo que hace que el hueco se oiga como un corte y no como un
    // gallo.
    _chunks++;
    if (_chunks % _stallEvery != 0) {
      _audio.play(pcm);
      return;
    }
    Future<void>.delayed(
      Duration(milliseconds: _stallMs),
      () => _started ? _audio.play(pcm) : null,
    );
  }

  @override
  Future<void> discard() async {
    if (!_started) return;
    await _audio.clearPlayback();
  }

  @override
  Future<Duration> pending() async {
    if (!_started) return Duration.zero;
    return _audio.pendingPlayback();
  }

  @override
  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    await _audio.clearPlayback();
    await _audio.release(para: para);
  }
}
