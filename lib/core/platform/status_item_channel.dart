import 'package:flutter/services.dart';

/// Lo que Nexus enseña —y ofrece— en la barra de estado del Mac.
///
/// Los estados viajan como el `name` del estado del orbe —`sleep`, `listen`,
/// `think`, `speak`— y es el lado nativo quien decide cuántos aspectos distintos
/// caben: a 16 px no son cuatro. Traducirlos aquí obligaría a mantener una tabla
/// en los dos lados.
abstract final class StatusItemChannel {
  static const _channel = MethodChannel('com.katanalabs.nexus/status');

  /// [pending] es «hay una versión nueva sin instalar», y pinta un punto rojo en
  /// el icono. Va junto al estado y no en su propio método porque el lado nativo
  /// redibuja el icono entero: dos llamadas serían dos dibujos, y la segunda
  /// borraría lo que dijo la primera.
  /// [accent] en `#RRGGBB`: el color con el que se pinta la marca. Se manda desde
  /// aquí porque se elige en Ajustes, y un icono clavado en cian mientras la app
  /// entera es violeta sería el único sitio que no obedece.
  static Future<void> show(String orbState, {bool? pending, String? accent}) =>
      _llamar('setState', {
        'state': orbState,
        'pending': ?pending,
        'accent': ?accent,
      });

  /// Los rótulos del menú, en el idioma **de la app**.
  ///
  /// Se mandan desde aquí y no se escriben en Swift porque el idioma se elige en
  /// Ajustes y puede no ser el del sistema. Un menú en un idioma y la ventana en
  /// otro es de las cosas que no se ven hasta que le pasa a alguien.
  static Future<void> setMenu({
    required String talk,
    required String show,
    required String settings,
    required String quit,
    String? update,
  }) => _llamar('setMenu', {
    'talk': talk,
    'show': show,
    'settings': settings,
    'quit': quit,
    // Va solo cuando hay algo que anunciar: el lado nativo se salta la fila si
    // llega vacío, y así el menú no tiene un hueco muerto el 99 % del tiempo.
    'update': ?update,
  });

  /// Lo que el menú pide de vuelta: hablar y abrir ajustes son estado de la app,
  /// así que los resuelve Dart. Abrir la ventana y salir los hace el sistema.
  static void onAction({
    required void Function() talk,
    required void Function() settings,
    required void Function() update,
  }) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'talk':
          talk();
        case 'settings':
          settings();
        // Antes esta fila abría la página de la release en el navegador, y lo
        // hacía el lado nativo con la URL. Ahora la actualización se instala
        // dentro, así que lo que abre es la modal — y eso solo lo sabe Dart.
        case 'update':
          update();
      }
      return null;
    });
  }

  static Future<void> _llamar(String metodo, Map<String, Object?> args) async {
    try {
      await _channel.invokeMethod<void>(metodo, args);
    } on PlatformException {
      // Que la barra no se entere no puede tumbar una conversación.
    } on MissingPluginException {
      // Sin canal —en pruebas, o en otra plataforma— no hay barra que pintar.
    }
  }
}
