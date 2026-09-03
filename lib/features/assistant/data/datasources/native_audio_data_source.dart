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
/// Para qué se pide el motor.
///
/// 🔴 **Existe porque montar el grafo entero para decir una frase enciende el
/// micrófono.** Un aviso de agenda solo habla, y abría la captura, el
/// cancelador de eco y el dispositivo agregado — con el indicador naranja de
/// macOS encendido toda la frase, sin nada que lo justificara.
enum ParaQue {
  /// Solo salida. No se toca la entrada al otro lado.
  hablar,

  /// Escuchar y hablar a la vez, con cancelación de eco.
  conversar,
}

class NativeAudioDataSource {
  NativeAudioDataSource();

  static const _methods = MethodChannel('nexus/audio');
  static const _frames = EventChannel('nexus/audio/frames');

  /// Cuántos lo tienen cogido, por lo que vinieron a hacer.
  ///
  /// Dos cuentas y no una porque **el propósito es el máximo de lo que se le
  /// pide**, no lo que pidió el último: con el altavoz de un aviso dentro y una
  /// conversación abriéndose encima, hace falta el grafo entero.
  final _users = <ParaQue, int>{ParaQue.hablar: 0, ParaQue.conversar: 0};
  ParaQue? _montado;
  Stream<Uint8List>? _frameStream;

  /// Lo que hace falta ahora mismo, o `null` si no lo tiene cogido nadie.
  ParaQue? get _loQueHaceFalta {
    if (_users[ParaQue.conversar]! > 0) return ParaQue.conversar;
    if (_users[ParaQue.hablar]! > 0) return ParaQue.hablar;
    return null;
  }

  /// `true` si hay permiso de micrófono. La primera vez abre el diálogo del
  /// sistema y espera la respuesta.
  Future<bool> hasPermission() async {
    final granted = await _methods.invokeMethod<bool>('hasPermission');
    return granted ?? false;
  }

  Future<void> acquire({ParaQue para = ParaQue.conversar}) async {
    _users[para] = _users[para]! + 1;
    final hace = _loQueHaceFalta;
    if (hace == null) return;
    // Solo se llama al nativo cuando **cambia** lo que hace falta: con el motor
    // ya montado para conversar, un aviso que quiere hablar no monta nada.
    if (_montado == hace) return;
    _montado = hace;
    await _methods.invokeMethod<void>('start', {'para': hace.name});
  }

  Future<void> release({ParaQue para = ParaQue.conversar}) async {
    if (_users[para]! == 0) return;
    _users[para] = _users[para]! - 1;
    final hace = _loQueHaceFalta;
    if (hace != null) {
      // 🔴 **No se degrada en caliente, a propósito.** Al soltar la conversación
      // con un aviso todavía sonando, bajar a solo salida obligaría a rehacer el
      // grafo con audio en vuelo: se oiría el corte. Sale más barato quedarse
      // con el grafo de más hasta que lo suelte el último.
      return;
    }
    _montado = null;
    await _methods.invokeMethod<void>('stop');
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
