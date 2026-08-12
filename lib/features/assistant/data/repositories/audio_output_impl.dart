import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:nexus/features/assistant/data/datasources/pcm_player_data_source.dart';
import 'package:nexus/features/assistant/domain/repositories/audio_output.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_gateway.dart';

/// Reproduce el audio de la respuesta manteniendo **la cola en Dart**, no en
/// el paquete.
///
/// Podría entregarse cada trozo al altavoz según llega —es más corto— pero
/// entonces la cola viviría entera del lado nativo, y el paquete no ofrece
/// forma de vaciarla. Y esta conversación se interrumpe: cuando el usuario
/// habla encima, lo que queda por sonar hay que tirarlo. Con la cola aquí,
/// [discard] la vacía de golpe y lo único que se sigue oyendo es lo ya
/// entregado, que por eso se mantiene corto a propósito.
class AudioOutputImpl implements AudioOutput {
  AudioOutputImpl(this._player);

  /// Cuánto audio se le deja al sistema antes de que pida más. Es el
  /// compromiso de esta clase: subirlo protege de tirones de red, y alarga
  /// la coleta que se sigue oyendo al interrumpir. 150 ms aguanta de sobra el
  /// viaje de ida y vuelta por el canal de plataforma, que va en milisegundos.
  static const _feedThresholdFrames = 3600;

  /// Tope de lo que se entrega de una tacada cuando pide más: 300 ms.
  static const _burstFrames = 7200;

  static const _bytesPerFrame = 2; // 16 bits, mono

  final PcmPlayerDataSource _player;
  final _pending = Queue<Uint8List>();
  bool _started = false;
  bool _feeding = false;

  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _player.configure(
      sampleRate: VoiceSessionFormat.outputSampleRate,
      channels: VoiceSessionFormat.channels,
      feedThresholdFrames: _feedThresholdFrames,
      onNeedsMore: (_) => unawaited(_feed()),
    );
    _player.prime();
  }

  @override
  void enqueue(Uint8List pcm) {
    if (!_started || pcm.isEmpty) return;
    _pending.add(pcm);
    unawaited(_feed());
  }

  @override
  Future<void> discard() async {
    _pending.clear();
  }

  @override
  Future<void> stop() async {
    _pending.clear();
    if (!_started) return;
    _started = false;
    await _player.release();
  }

  /// Entrega hasta [_burstFrames] y para. El paquete vuelve a llamar cuando
  /// baje del umbral, así que el goteo se sostiene solo mientras haya cola.
  Future<void> _feed() async {
    if (_feeding) return;
    _feeding = true;
    try {
      var frames = 0;
      while (_started && _pending.isNotEmpty && frames < _burstFrames) {
        final chunk = _pending.removeFirst();
        await _player.feed(chunk);
        frames += chunk.lengthInBytes ~/ _bytesPerFrame;
      }
    } finally {
      _feeding = false;
    }
  }
}
