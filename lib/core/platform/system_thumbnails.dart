import 'package:flutter/services.dart';

/// La miniatura que enseña el Finder, pedida al sistema.
abstract final class SystemThumbnails {
  static const _channel = MethodChannel('com.katanalabs.nexus/thumbnails');

  /// `null` si no hubo forma de sacar ninguna. Quien la pide dibuja entonces
  /// lo suyo: una miniatura ausente no es un error que contar, es un archivo
  /// que se enseña por su nombre.
  static Future<Uint8List?> of(String path, {double size = 40}) async {
    try {
      return await _channel.invokeMethod<Uint8List>('thumbnail', {
        'path': path,
        'size': size,
        // La pantalla es Retina: pedirla al doble y encogerla evita el borde
        // pastoso de escalar una imagen de 40 px a 40 puntos.
        'scale': 2.0,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
