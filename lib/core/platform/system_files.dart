import 'package:flutter/services.dart';

/// Operaciones de archivos que el sistema no deja hacer desde Dart.
abstract final class SystemFiles {
  static const _channel = MethodChannel('com.katanalabs.nexus/files');

  /// Manda un archivo a la papelera.
  ///
  /// Pasa por el sistema y no por un `rename` a `~/.Trash` porque **macOS lo
  /// prohíbe**: comprobado en vivo, «Operation not permitted». Ese fallo era
  /// justo el que hacía que borrar una conversación funcionara unas veces sí y
  /// otras no — las que solo estaban en el historial de la app se borraban, y
  /// las que además tenían nota en el vault reventaban a mitad.
  ///
  /// Devuelve `false` si no se pudo. El archivo es del usuario y está en su
  /// carpeta: si el sistema dice que no, se dice, no se insiste borrándolo por
  /// las bravas.
  /// Lo enseña en el Finder, seleccionado.
  ///
  /// Se abre donde está en vez de leerlo dentro de la app: un registro se mira
  /// con un editor de verdad —buscando, saltando— y montar un visor aquí sería
  /// hacer peor lo que el sistema ya hace bien.
  static Future<bool> revelar(String path) async {
    try {
      final ok = await _channel.invokeMethod<bool>('reveal', {'path': path});
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> moveToTrash(String path) async {
    try {
      final ok = await _channel.invokeMethod<bool>('moveToTrash', {
        'path': path,
      });
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
