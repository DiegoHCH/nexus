import 'package:flutter/services.dart';

/// Avisar de que un encargo terminó.
///
/// **Aquí no se decide si avisar**: eso lo resuelve el lado nativo, que es quien
/// sabe si la app está delante. Flutter solo conoce el foco de sus propios
/// widgets, así que con la ventana detrás y el campo de texto «enfocado» creería
/// que la estás mirando.
abstract final class NotificationsChannel {
  static const _channel = MethodChannel('com.katanalabs.nexus/notify');

  static Future<void> notify({
    required String title,
    required String body,
  }) async {
    try {
      await _channel.invokeMethod<bool>('notify', {
        'title': title,
        'body': body,
      });
    } on PlatformException {
      // Un aviso que no sale no puede tumbar nada: el trabajo ya está hecho.
    } on MissingPluginException {
      // Sin canal —en pruebas, o en otra plataforma— no hay nada que avisar.
    }
  }
}
