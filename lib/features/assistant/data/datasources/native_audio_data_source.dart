import 'dart:async';

import 'package:flutter/services.dart';

/// El motor de audio nativo: un solo `AVAudioEngine` que escucha y habla a la
/// vez, con cancelación de eco. Ver `macos/Runner/NexusAudioEngine.swift`.
///
/// Escuchar y reproducir comparten motor por necesidad, no por comodidad: el
/// cancelador de eco de Apple solo puede restar del micrófono lo que reproduce
/// **su propio** motor. Por eso esta clase lleva la cuenta de quién lo está
/// usando: el micrófono y el altavoz lo piden por separado, y el motor se
/// apaga cuando lo suelta el último — si cada uno pudiera pararlo, cerrar el
/// altavoz dejaría sordo al micrófono.
class NativeAudioDataSource {
  NativeAudioDataSource();

  static const _methods = MethodChannel('nexus/audio');
  static const _frames = EventChannel('nexus/audio/frames');

  int _users = 0;
  Stream<Uint8List>? _frameStream;

  /// `true` si hay permiso de micrófono. La primera vez abre el diálogo del
  /// sistema y espera la respuesta.
  Future<bool> hasPermission() async {
    final granted = await _methods.invokeMethod<bool>('hasPermission');
    return granted ?? false;
  }

  Future<void> acquire() async {
    _users++;
    if (_users == 1) await _methods.invokeMethod<void>('start');
  }

  Future<void> release() async {
    if (_users == 0) return;
    _users--;
    if (_users == 0) await _methods.invokeMethod<void>('stop');
  }

  /// Los aparatos por los que puede sonar la respuesta.
  Future<List<Map<String, dynamic>>> outputDevices() async {
    final devices = await _methods.invokeListMethod<dynamic>('outputDevices');
    return [
      for (final device in devices ?? const [])
        if (device is Map) Map<String, dynamic>.from(device),
    ];
  }

  /// Fija por dónde suena, o `null` para seguir al sistema.
  ///
  /// Desmonta el motor: el aparato se fija al construir el grafo de audio y no
  /// se puede cambiar en marcha. La siguiente vez que hables se monta con el
  /// elegido.
  Future<void> setOutputDevice(int? id) =>
      _methods.invokeMethod<void>('setOutputDevice', {'id': id});

  /// Trozos de micrófono: PCM 16 bits, 16 kHz, mono.
  Stream<Uint8List> get frames {
    return _frameStream ??= _frames.receiveBroadcastStream().map(
      (dynamic frame) => frame as Uint8List,
    );
  }

  /// Encola PCM de 16 bits a 24 kHz para que suene.
  Future<void> play(Uint8List pcm) {
    return _methods.invokeMethod<void>('play', {'pcm': pcm});
  }

  /// Tira lo que quede por sonar, de inmediato.
  Future<void> clearPlayback() => _methods.invokeMethod<void>('clearPlayback');

  /// Cuánto audio queda por sonar. El servicio entrega la respuesta más rápido
  /// que en tiempo real, así que "dejó de llegar audio" no significa "dejó de
  /// hablar" — esto es la diferencia entre las dos cosas.
  Future<Duration> pendingPlayback() async {
    final ms = await _methods.invokeMethod<int>('pendingPlaybackMs');
    return Duration(milliseconds: ms ?? 0);
  }
}
