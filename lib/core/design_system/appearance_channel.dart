import 'package:flutter/services.dart';

/// Le dice al marco de la ventana qué tema toca.
///
/// Existe porque la barra de título y el fondo de la ventana **no son
/// Flutter**: son AppKit, y no se enteran del `ThemeMode`. Sin esto, elegir el
/// tema claro dejaba el contenido claro dentro de una barra de título negra.
abstract final class AppearanceChannel {
  static const _channel = MethodChannel('com.katanalabs.nexus/appearance');

  /// Falla en silencio a propósito: si el canal no contesta —una versión sin
  /// el lado nativo, una prueba— lo que se pierde es el color de un marco, y
  /// tumbar la app por eso sería peor que la molestia que evita.
  static Future<void> apply({required bool dark}) async {
    try {
      await _channel.invokeMethod<void>('apply', {'dark': dark});
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }
}
