import 'dart:convert';

/// Los errores del framework, que **no salen por donde sale todo lo demás**.
///
/// 🔴 **Reportado desde el repo del trabajo, y medido aquí:** «el error en
/// debug, desde Nexus no saltó, y al lanzarlo desde VS Code sí salió». No era
/// que se perdiera una línea: es que esa línea no existe.
///
/// Se corrió una app de juguete que revienta pintando, con el mismo comando que
/// usa Nexus —`flutter run --machine`— y capturando las dos salidas. Lo que se
/// vio:
///
/// - el `print` de la app: **sale** por stdout (`flutter: …`);
/// - una excepción asíncrona sin dueño: **sale** por stdout, con su traza
///   (`[ERROR:flutter/runtime/dart_vm_initializer.cc(40)] Unhandled
///   Exception: …`);
/// - **la excepción del framework al pintar** —la de la pantalla roja, la que
///   empieza por `EXCEPTION CAUGHT BY WIDGETS LIBRARY`—: **no sale**. Ni en
///   stdout ni en stderr. Nada.
///
/// Y no es un descuido de nadie, está escrito en las dos partes:
///
/// - En modo debug el framework enciende `flutter.inspector.structuredErrors`
///   por defecto y con eso `FlutterError.presentError` deja de imprimir en la
///   consola: manda un evento `Flutter.Error` por el **VM service**
///   (`widget_inspector.dart`, `postEvent('Flutter.Error', …)`).
/// - Y `flutter run` los imprime al recibirlos… salvo en modo máquina:
///   `if (event.extensionKind == 'Flutter.Error' && !machine)`
///   (`resident_runner.dart:1247`). En modo máquina se calla a propósito,
///   porque el protocolo da por hecho que quien escucha es un IDE — y VS Code
///   los escucha ahí, con su propio formateador.
///
/// Nexus habla el protocolo de máquina —es lo que hace que una recarga
/// **conteste** si funcionó— pero no se había asomado al VM service. Así que la
/// mitad de los errores que se ven mientras se desarrolla no llegaban.
///
/// Aquí vive solo el idioma: entra texto, sale el error. El socket lo abre el
/// data source, igual que con el daemon.
abstract final class ElErrorQuePintaLaApp {
  /// El nombre del canal de eventos donde viajan. `Extension` es el stream de
  /// los eventos que publica la app; `Flutter.Error` es uno de ellos.
  static const canal = 'Extension';

  /// La clase de evento que interesa de ese canal.
  static const clase = 'Flutter.Error';

  /// Si por esta URL se puede oír a la app.
  ///
  /// Del mismo campo de la corrida salen dos cosas: el `wsUri` del depurador
  /// —`app.debugPort`— y la URL http con la que se abre una corrida de **web**
  /// —`app.webLaunchUrl`—. La segunda no es un VM service al que apuntarse, y
  /// enchufar un `WebSocket` ahí solo conseguiría un error en el registro cada
  /// vez que alguien corra en Chrome.
  static bool sePuedeOir(String? url) => url != null && url.startsWith('ws');

  /// Apuntarse al canal. Sin esto el VM service no manda nada: hay que pedirlo.
  static String peticionDeEscucha(int id) => jsonEncode({
    'jsonrpc': '2.0',
    'id': id,
    'method': 'streamListen',
    'params': {'streamId': canal},
  });

  /// El error que trae esta línea, ya redactado, o `null` si la línea es otra
  /// cosa.
  ///
  /// **El texto lo redacta el framework**, no Nexus: viene en
  /// `renderedErrorText`, que es exactamente el bloque que se ve en una
  /// terminal. Rearmarlo desde el árbol de diagnósticos sería reescribir peor
  /// lo que ya viene hecho.
  ///
  /// A partir del segundo error sin recargar, el framework manda una sola línea
  /// —«Another exception was thrown: …»—, y así se deja: es lo que hace también
  /// una terminal, y repetir el bloque entero por cada frame roto llena el
  /// registro con lo mismo.
  static String? loQueDice(String linea) {
    final Object? leido;
    try {
      leido = jsonDecode(linea);
    } on FormatException {
      return null;
    }
    if (leido is! Map) return null;

    // 🔴 **`streamNotify`, y está medido.** El nombre que se lee en la
    // documentación del protocolo es «streamNotification»; lo que manda el VM
    // service de verdad es `streamNotify`. Se capturó el evento crudo de una app
    // que revienta pintando para verlo: con el nombre de la documentación se
    // descartaba **todo**.
    //
    // Las respuestas a lo que pedimos —el `streamListen`— llegan con `id` y sin
    // `method`: no son eventos y aquí no cuentan.
    if (leido['method'] != 'streamNotify') return null;

    final params = leido['params'];
    if (params is! Map) return null;
    final evento = params['event'];
    if (evento is! Map) return null;
    if (evento['extensionKind'] != clase) return null;

    final datos = evento['extensionData'];
    if (datos is! Map) return null;
    final texto = datos['renderedErrorText'];
    if (texto is! String || texto.trim().isEmpty) return null;
    return texto.trimRight();
  }

  /// Cuántos errores hay en este trozo de registro.
  ///
  /// **Por líneas y no por trozo**, porque lo que llega no viene en líneas: el
  /// stdout de un proceso llega en pedazos del tamaño que decida el sistema, y
  /// dos errores pueden venir pegados. Y de un bloque de varias líneas solo su
  /// **primera** se lee como error —la de `EXCEPTION CAUGHT BY`, la de
  /// `[ERROR:…`—, así que las de la traza no vuelven a contar: si contaran, un
  /// solo fallo con veinte líneas de pila se anunciaría como veinte.
  static int cuantosErrores(String trozo) =>
      trozo.split('\n').where(pintaMal).length;

  /// Si esta línea del registro se lee como un error.
  ///
  /// Sirve para pintarla, y por eso no distingue de dónde vino: valen las tres
  /// formas que llegan de verdad —el bloque del framework, la excepción sin
  /// dueño del motor y lo que el propio `flutter run` marca como error—. Las dos
  /// últimas ya llegaban antes de esto y se leían del mismo gris que todo lo
  /// demás.
  static bool pintaMal(String linea) {
    final texto = linea.trimLeft();
    return texto.startsWith('[ERROR:') ||
        texto.contains('EXCEPTION CAUGHT BY') ||
        texto.startsWith('Unhandled Exception:') ||
        texto.startsWith('Another exception was thrown:');
  }
}
