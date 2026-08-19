import 'package:flutter/services.dart';

/// Lo que Nexus enseña en la barra de estado del Mac.
///
/// Los nombres viajan como el `name` del estado del orbe —`sleep`, `listen`,
/// `think`, `speak`— y es el lado nativo quien decide cuántos aspectos
/// distintos caben: a 16 px no son cuatro. Traducirlos aquí obligaría a que los
/// dos lados se pusieran de acuerdo en una tabla, y a mantenerla.
abstract final class StatusItemChannel {
  static const _channel = MethodChannel('com.katanalabs.nexus/status');

  static Future<void> show(String orbState) async {
    try {
      await _channel.invokeMethod<void>('setState', {'state': orbState});
    } on PlatformException {
      // Que la barra no se entere no puede tumbar una conversación.
    } on MissingPluginException {
      // Sin canal —en pruebas, o en otra plataforma— no hay barra que pintar.
    }
  }
}
