import 'package:flutter/services.dart';

/// Lo que Nexus enseña —y ofrece— en la barra de estado del Mac.
///
/// Los estados viajan como el `name` del estado del orbe —`sleep`, `listen`,
/// `think`, `speak`— y es el lado nativo quien decide cuántos aspectos distintos
/// caben: a 16 px no son cuatro. Traducirlos aquí obligaría a mantener una tabla
/// en los dos lados.
abstract final class StatusItemChannel {
  static const _channel = MethodChannel('com.katanalabs.nexus/status');

  static Future<void> show(String orbState) =>
      _llamar('setState', {'state': orbState});

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
    String? updateUrl,
  }) => _llamar('setMenu', {
    'talk': talk,
    'show': show,
    'settings': settings,
    'quit': quit,
    // Van solo cuando hay algo que anunciar: el lado nativo se salta la fila si
    // llegan vacíos, y así el menú no tiene un hueco muerto el 99 % del tiempo.
    'update': ?update,
    'updateUrl': ?updateUrl,
  });

  /// Lo que el menú pide de vuelta: hablar y abrir ajustes son estado de la app,
  /// así que los resuelve Dart. Abrir la ventana y salir los hace el sistema.
  static void onAction({
    required void Function() talk,
    required void Function() settings,
  }) {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'talk':
          talk();
        case 'settings':
          settings();
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
