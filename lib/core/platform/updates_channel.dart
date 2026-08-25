import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Lo que el actualizador cuenta y lo que se le pide.
///
/// Al otro lado está Sparkle (ver `macos/Runner/NexusUpdater.swift`): él baja el
/// paquete, comprueba la firma, cambia la app y la relanza. Aquí solo viajan el
/// relato de lo que va pasando y las respuestas de quien mira.
///
/// El reparto es a propósito: la parte que puede dejar una instalación partida
/// —reemplazar el paquete de una app que está corriendo— no la escribimos
/// nosotros. La parte que se ve, sí.
abstract final class UpdatesChannel {
  static const _channel = MethodChannel('com.katanalabs.nexus/updates');

  /// Lo que llega del actualizador, ya nombrado.
  ///
  /// `broadcast` porque hay dos que escuchan —la modal y la fila del menú de la
  /// barra— y ninguno de los dos debe robarle los eventos al otro.
  static final _eventos = StreamController<UpdateEvent>.broadcast();

  static Stream<UpdateEvent> get events => _eventos.stream;

  /// Empieza a escuchar. Se llama una vez, al montar la app.
  static void listen() {
    _channel.setMethodCallHandler((call) async {
      final datos =
          (call.arguments as Map?)?.cast<String, Object?>() ?? const {};
      _eventos.add(UpdateEvent(name: call.method, data: datos));
      return null;
    });
  }

  /// Si esta copia puede actualizarse, y si no, por qué.
  ///
  /// Se pregunta **antes** de ofrecer nada. El caso malo es silencioso: una app
  /// abierta desde Descargas sin arrastrarla corre desde una copia de solo
  /// lectura, y ahí no hay nada que reemplazar. Sin esto, la modal ofrecería
  /// actualizar y el fallo saldría al final, tras bajar 23 MB.
  static Future<Installability> installability() async {
    final razon = await _pedir<String>('installability');
    return switch (razon) {
      'ok' => Installability.ok,
      'translocated' => Installability.translocated,
      'readOnly' => Installability.readOnly,
      // Sin canal —en pruebas, o en otra plataforma— no se puede saber, y eso no
      // es «se puede»: ver `Installability.unknown`.
      _ => Installability.unknown,
    };
  }

  /// [manual] cuando lo pide una persona: entonces el actualizador **sí** dice
  /// «estás al día». La de fondo calla si no hay nada.
  static Future<void> check({bool manual = false}) =>
      _pedir<void>('check', {'manual': manual});

  static Future<void> answer(UpdateChoice choice) =>
      _pedir<void>('answer', {'choice': choice.name});

  static Future<void> cancel() => _pedir<void>('cancel');

  static Future<T?> _pedir<T>(
    String metodo, [
    Map<String, Object?>? args,
  ]) async {
    try {
      return await _channel.invokeMethod<T>(metodo, args);
    } on PlatformException catch (error) {
      debugPrint('actualizaciones · $metodo falló: ${error.message}');
      return null;
    } on MissingPluginException {
      // Sin canal no hay actualizador. No es un fallo que deba verse: la app
      // funciona igual, simplemente no se actualiza sola.
      return null;
    }
  }

  /// Para las pruebas: empujar un evento sin canal nativo al otro lado.
  @visibleForTesting
  static void emitForTesting(
    String name, [
    Map<String, Object?> data = const {},
  ]) => _eventos.add(UpdateEvent(name: name, data: data));
}

/// Un aviso del actualizador, tal como llega.
@immutable
class UpdateEvent {
  const UpdateEvent({required this.name, required this.data});

  final String name;
  final Map<String, Object?> data;

  T? get<T>(String clave) => data[clave] as T?;
}

/// Qué se contesta a la modal.
enum UpdateChoice { install, later, skip }

/// Si esta copia de la app puede reemplazarse a sí misma.
enum Installability {
  ok,

  /// Corre desde la copia de solo lectura que macOS monta para las apps en
  /// cuarentena que se abren sin moverlas. Se arregla arrastrándola a
  /// Aplicaciones, y solo así.
  translocated,

  /// Está en un sitio donde no se puede escribir.
  readOnly,

  /// No se pudo preguntar. **No** es lo mismo que «se puede»: ante la duda no se
  /// ofrece instalar, por lo mismo que un `null` en la comprobación de arranque
  /// no significa que Claude esté listo.
  unknown;

  bool get canInstall => this == Installability.ok;
}
