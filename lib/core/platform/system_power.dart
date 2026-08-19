import 'package:flutter/services.dart';

/// Lo que el sistema deja decidir sobre dormirse.
abstract final class SystemPower {
  static const _channel = MethodChannel('com.katanalabs.nexus/power');

  /// Pide que el Mac no se suspenda solo. [reason] sale literal en
  /// `pmset -g assertions`, así que se escribe para quien vaya a mirar por qué
  /// su Mac sigue despierto.
  ///
  /// Devuelve `false` si el sistema dijo que no. Es información, no un fallo:
  /// el encargo sigue igual, solo que sin la red.
  static Future<bool> keepAwake(String reason) async {
    try {
      final ok = await _channel.invokeMethod<bool>('keepAwake', {
        'reason': reason,
      });
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> allowSleep() async {
    try {
      await _channel.invokeMethod<void>('allowSleep');
    } on PlatformException {
      // Nada que hacer: si no se pudo soltar, insistir tampoco ayuda.
    } on MissingPluginException {
      // En pruebas y en otras plataformas no hay nadie al otro lado.
    }
  }
}
