import 'dart:convert';

import 'package:nexus/features/emulators/domain/entities/emulador.dart';

/// Cómo se le habla a las herramientas de emuladores y cómo se lee lo que
/// contestan.
///
/// Se arma aquí y no en el data source por lo mismo que [McpCommand]: un
/// argumento mal puesto no falla, hace algo distinto, y eso no se ve mirándolo.
/// Aquí encima hay dos cosas que **no se adivinan** y que serían un fallo
/// silencioso cada una:
///
/// 1. `flutter emulators --launch` **sale con 0 aunque falle**.
/// 2. `flutter emulators` **no admite `--machine`**: solo esa tabla.
///
/// Las dos vienen medidas de `la-oficina` —`electron/lib/core.js:424` y su
/// prueba en `core.test.js:235`—, donde este mismo problema ya se pagó.
abstract final class ComandoDeEmuladores {
  /// Lo que hay, leído de la tabla de `flutter emulators`.
  ///
  /// **Se parsea una tabla porque no hay JSON.** `flutter devices` acepta
  /// `--machine` y devuelve JSON; `flutter emulators` no lo admite, así que esto
  /// es lo único que da. La tabla real, comprobada hoy:
  ///
  /// ```
  /// 3 available emulators:
  ///
  /// Id                    • Name                  • Manufacturer • Platform
  ///
  /// apple_ios_simulator   • iOS Simulator         • Apple        • ios
  /// Medium_Phone_API_36.1 • Medium Phone API 36.1 • Generic      • android
  /// Small_Phone           • Small Phone           • Generic      • android
  ///
  /// To run an emulator, run 'flutter emulators --launch <emulator id>'.
  /// ```
  ///
  /// Se ignora todo lo que no traiga cuatro columnas separadas por `•`: la
  /// cabecera, el recuento de arriba y los dos consejos del final. Y la fila de
  /// cabecera se descarta por su primera celda —`Id`— porque sí trae cuatro.
  static List<Emulador> leerTabla(String salida) {
    final emuladores = <Emulador>[];

    for (final linea in salida.split('\n')) {
      if (!linea.contains('•')) continue;
      final celdas = linea.split('•').map((c) => c.trim()).toList();
      if (celdas.length < 4) continue;

      final id = celdas[0];
      if (id.isEmpty || id.toLowerCase() == 'id') continue;

      final plataforma = PlataformaEmulador.desde(celdas[3]);
      // Una plataforma que no conocemos se descarta en vez de colarse como
      // Android: ofrecer un botón que no sabemos cerrar es peor que no ofrecerlo.
      if (plataforma == null) continue;

      emuladores.add(
        Emulador(
          id: id,
          nombre: celdas[1].isEmpty ? id : celdas[1],
          fabricante: celdas[2],
          plataforma: plataforma,
        ),
      );
    }
    return emuladores;
  }

  /// Los argumentos de `flutter emulators --launch`.
  ///
  /// [frio] es `--cold`, y **solo existe en Android**: pasárselo a un simulador
  /// de iOS es un argumento que no entiende. Se filtra aquí y no en la pantalla
  /// para que no haya dos sitios que tengan que saberlo.
  static List<String> argumentosDeLanzar(
    Emulador emulador, {
    bool frio = false,
  }) => [
    'emulators',
    '--launch',
    emulador.id,
    if (frio && emulador.plataforma == PlataformaEmulador.android) '--cold',
  ];

  /// El veredicto de un lanzamiento, sacado de **la salida y no del código**.
  ///
  /// Porque `flutter emulators --launch <id>` sale con **0 aunque falle**: con un
  /// id que no existe imprime «No emulator found that matches …» y devuelve 0
  /// igual. Mirando el código de salida, la app diría que lanzó algo que nunca
  /// arrancó — y el usuario se queda mirando una pantalla que no cambia.
  ///
  /// En el camino bueno no imprime nada y vuelve en ~1 s, sin esperar el
  /// arranque. Eso es lo que hace que Nexus no tenga que sostener el proceso.
  static ({bool ok, String? error}) resultadoDeLanzar(String salida) {
    final texto = salida.trim();

    if (RegExp(
      'no emulator found that matches',
      caseSensitive: false,
    ).hasMatch(texto)) {
      return (ok: false, error: 'No se encontró ese emulador');
    }

    final problema = RegExp(
      r'^(error|exception)\b|error:|failed to|could not|unable to',
      caseSensitive: false,
    );
    for (final linea in texto.split('\n')) {
      if (problema.hasMatch(linea.trim())) {
        return (ok: false, error: linea.trim());
      }
    }
    return (ok: true, error: null);
  }

  /// Los emuladores de Android que ve `adb devices`.
  ///
  /// Solo los que empiezan por `emulator-`: un móvil enchufado sale en la misma
  /// lista con su número de serie —`36c56d94`— y no es un emulador.
  ///
  /// Se ignora todo lo que no esté en estado `device`: `offline` es un emulador
  /// que está arrancando, y darlo por arriba haría que el botón dijera «cerrar»
  /// sobre algo que aún no se puede usar. Medido: durante el arranque, `adb
  /// devices` lo lista como `emulator-5554  offline` casi veinte segundos.
  static List<String> idsDeEmuladorEnAdb(String salida) => [
    for (final linea in salida.split('\n'))
      if (linea.trim() case final l when l.startsWith('emulator-'))
        if (l.split(RegExp(r'\s+')) case final partes
            when partes.length >= 2 && partes[1] == 'device')
          partes[0],
  ];

  /// Si hay algún simulador de iOS arrancado, según
  /// `xcrun simctl list devices booted --json`.
  ///
  /// **Un booleano y no una lista**, y no es pereza: en iOS se apagan todos de
  /// una vez (`simctl shutdown all`), así que saber cuál está arriba no cambia
  /// nada de lo que se puede hacer. Y `flutter emulators` ofrece **un solo**
  /// `apple_ios_simulator` para todos los modelos, así que no hay a quién
  /// atribuirlo.
  static bool hayIosArriba(String json) {
    try {
      final leido = jsonDecode(json);
      if (leido is! Map) return false;
      final porRuntime = leido['devices'];
      if (porRuntime is! Map) return false;

      for (final lista in porRuntime.values) {
        if (lista is! List) continue;
        for (final dispositivo in lista) {
          if (dispositivo is Map && dispositivo['state'] == 'Booted') {
            return true;
          }
        }
      }
    } on FormatException {
      // Sin Xcode, `simctl` no contesta JSON. Que no se sepa el estado de iOS no
      // puede tirar la lista de Android.
      return false;
    }
    return false;
  }

  /// La lista con su estado, cruzando el catálogo con lo que está arriba.
  ///
  /// [avdsArriba] va del **nombre del AVD** al dispositivo con el que se cierra,
  /// porque es el único puente que hay: `adb devices` da `emulator-5554` y hace
  /// falta preguntarle a cada uno su `emu avd name` para saber cuál es.
  ///
  /// El emparejamiento admite el `id` **o** el `nombre` porque los dos aparecen
  /// según cómo se creara el AVD: `Small_Phone` es el id y `Small Phone` el
  /// nombre, y `adb` puede contestar cualquiera de los dos.
  static List<Emulador> conEstado(
    List<Emulador> catalogo, {
    required Map<String, String> avdsArriba,
    required bool iosArriba,
  }) => [
    for (final emulador in catalogo)
      if (emulador.plataforma == PlataformaEmulador.ios)
        emulador.conEstado(corriendo: iosArriba)
      else
        _conEstadoAndroid(emulador, avdsArriba),
  ];

  static Emulador _conEstadoAndroid(
    Emulador emulador,
    Map<String, String> avdsArriba,
  ) {
    for (final entrada in avdsArriba.entries) {
      if (entrada.key == emulador.id || entrada.key == emulador.nombre) {
        return emulador.conEstado(corriendo: true, deviceId: entrada.value);
      }
    }
    return emulador.conEstado(corriendo: false);
  }

  /// Los teléfonos de verdad que hay enchufados, de `flutter devices --machine`.
  ///
  /// Se filtra por **dos** condiciones y las dos hacen falta:
  ///
  /// - `emulator: false`, que descarta el emulador que ya sale en la otra lista.
  /// - la plataforma, que descarta `darwin` y `web-javascript`. `flutter devices`
  ///   ofrece macOS y Chrome como dispositivos —lo son, para Flutter— y en una
  ///   lista de teléfonos no pintan nada.
  ///
  /// El JSON se recorta **entre el primer `[` y el último `]`**, y las dos
  /// puntas hacen falta:
  ///
  /// - Por delante, porque Flutter puede escupir un aviso antes del JSON.
  /// - Por detrás, porque puede escupirlo **después**. Ahí se fue un rato: con
  ///   dos `flutter` a la vez, uno imprime «Waiting for another flutter command
  ///   to release the startup lock…» y si eso queda pegado al JSON, `jsonDecode`
  ///   lanza y la lista sale vacía sin decir por qué. Se ve como «no reconoce
  ///   los dispositivos físicos», que no se parece a un problema de parseo.
  static List<DispositivoConectado> leerDispositivos(String salida) {
    final desde = salida.indexOf('[');
    final hasta = salida.lastIndexOf(']');
    if (desde < 0 || hasta < desde) return const [];

    try {
      final leido = jsonDecode(salida.substring(desde, hasta + 1));
      if (leido is! List) return const [];

      return [
        for (final entrada in leido)
          if (entrada is Map)
            if (entrada['emulator'] != true)
              if (PlataformaEmulador.desdeObjetivo('${entrada['targetPlatform']}')
                  case final plataforma?)
                DispositivoConectado(
                  id: '${entrada['id']}',
                  nombre: '${entrada['name'] ?? entrada['id']}',
                  plataforma: plataforma,
                ),
      ];
    } on FormatException {
      return const [];
    }
  }

  /// Cómo se cierra uno de Android: por su dispositivo, no por su nombre.
  static List<String> argumentosDeCerrarAndroid(String deviceId) => [
    '-s',
    deviceId,
    'emu',
    'kill',
  ];
}
