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
  AudioOutputImpl(this._audio);

  final NativeAudioDataSource _audio;
  bool _started = false;

  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _audio.acquire();
  }

  @override
  void enqueue(Uint8List pcm) {
    if (!_started || pcm.isEmpty) return;
    _audio.play(pcm);
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
    await _audio.release();
  }
}
