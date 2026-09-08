import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nexus/features/run/domain/usecases/el_error_que_pinta_la_app.dart';

/// El socket al VM service de una corrida, abierto solo para oír sus errores.
///
/// **Un `WebSocket` pelado y no el paquete `vm_service`.** De todo el protocolo
/// aquí se usan dos cosas —apuntarse a un canal y leer sus eventos—, y el
/// paquete trae un cliente generado entero, con su propio modelo de objetos,
/// para no usar nada de eso. Es la misma decisión que ya se tomó con el daemon:
/// el idioma vive en [ElErrorQuePintaLaApp], que es puro y se prueba con líneas
/// de verdad, y aquí solo está el cable.
///
/// La URL la dice el propio `flutter run` en `app.debugPort` —`wsUri`—, así que
/// tampoco se adivina ni se compone.
class ElCanalDelVmService {
  ElCanalDelVmService._(this._socket);

  final WebSocket _socket;

  /// Se conecta y se apunta al canal. Devuelve `null` si no se pudo: **no es un
  /// fallo de la corrida**, que sigue corriendo igual de bien sin que nadie oiga
  /// sus errores. Se anota y se sigue.
  static Future<ElCanalDelVmService?> abrir(
    String wsUri, {
    required void Function(String error) alOirUnError,
  }) async {
    final WebSocket socket;
    try {
      socket = await WebSocket.connect(wsUri);
    } on Object catch (e) {
      debugPrint('corrida · no se pudo oír los errores de la app: $e');
      return null;
    }

    socket.add(ElErrorQuePintaLaApp.peticionDeEscucha(1));
    final canal = ElCanalDelVmService._(socket);
    socket.listen(
      (mensaje) {
        if (mensaje is! String) return;
        if (ElErrorQuePintaLaApp.loQueDice(mensaje) case final error?) {
          alOirUnError(error);
        }
      },
      // Que se caiga es lo normal al cerrarse la app: no hay nada que decir.
      onError: (Object _) {},
      cancelOnError: true,
    );
    return canal;
  }

  Future<void> cerrar() async {
    try {
      await _socket.close();
    } on Object {
      // Ya estaba cerrado, que es el caso de siempre: la app se fue primero.
    }
  }
}
