import 'package:flutter/services.dart';

/// Una ventana de Nexus con **una dirección dentro**, no con un archivo.
///
/// 🔴 **Es la única pieza que faltaba para traer la consola de la app dentro.**
/// [VentanaDelVisor] abre lo que se le escriba en disco, y eso vale para un
/// documento o para un registro que pintamos nosotros; la consola de
/// depuración la sirve la propia app corriendo, así que lo que hay que enseñar
/// es una URL.
///
/// Va aparte del visor y no como un parámetro suyo a propósito: el visor nace
/// **sin scripts y con la red cortada** porque lo que enseña lo escribió un
/// modelo, y una consola sin scripts ni red no enseña nada. Darle al visor un
/// modo «déjalo todo pasar» sería quitarle la mitad de su razón de existir.
abstract final class VentanaDeLaConsola {
  static const _canal = MethodChannel('com.katanalabs.nexus/artifacts');

  /// Abre [url] en su ventana, o trae al frente la que ya la tenía.
  ///
  /// Devuelve si se pudo. `false` es «no hay ventana», y quien llama sigue
  /// igual: la consola es una forma de mirar la app, no la app.
  static Future<bool> abre({
    required String url,
    String? titulo,
    double ancho = 1100,
    double alto = 760,
  }) async {
    try {
      return await _canal.invokeMethod<bool>('consola', {
            'url': url,
            'titulo': titulo,
            'width': ancho,
            'height': alto,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // En pruebas no hay nadie al otro lado.
      return false;
    }
  }
}
