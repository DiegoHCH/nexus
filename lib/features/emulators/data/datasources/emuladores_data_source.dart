import 'dart:io';

import 'package:nexus/core/platform/claude_environment.dart';
import 'package:nexus/core/platform/herramienta_externa.dart';
import 'package:nexus/features/emulators/domain/entities/emulador.dart';
import 'package:nexus/features/emulators/domain/usecases/comando_de_emuladores.dart';

/// Lo que dicen las herramientas de la máquina sobre los emuladores.
///
/// Tres binarios y no uno, y no es por gusto: `flutter emulators` da el catálogo
/// y sabe arrancarlos, pero **no dice cuál está arriba**. Eso lo sabe `adb` en
/// Android y `simctl` en iOS, y no hay identificador común entre un emulador y el
/// dispositivo que resulta de arrancarlo — así que hay que cruzarlo a mano.
class EmuladoresDataSource {
  const EmuladoresDataSource();

  /// El catálogo de emuladores con su estado.
  ///
  /// **Separado de [listarDispositivos] por una razón medida**: pedir las dos
  /// cosas juntas costaba 8 segundos y 7 eran de los teléfonos. Los tiempos, en
  /// esta máquina:
  ///
  /// | | |
  /// |---|---|
  /// | `flutter devices --machine` | **7048 ms** |
  /// | `flutter emulators` | 902 ms |
  /// | `simctl list --json` | 271 ms |
  /// | `adb devices` | 14 ms |
  ///
  /// `flutter devices` tarda porque sondea cada aparato de verdad —incluido
  /// despertar un iPhone por la red— y eso no se puede acelerar. Lo que sí se
  /// puede es no hacer esperar por ello a lo que la pantalla viene a enseñar: así
  /// los emuladores están en ~1,2 s y los teléfonos aparecen detrás.
  Future<({List<Emulador> emuladores, String? error})> listar() async {
    final flutter = await _flutter();
    if (flutter == null) {
      return (
        emuladores: const <Emulador>[],
        error:
            'No se encontró Flutter. Se buscó en el PATH de la app, en las rutas '
            'de siempre y en tu shell de login.',
      );
    }

    final catalogoBruto = await _correr(flutter, ['emulators']);
    if (catalogoBruto == null) {
      return (
        emuladores: const <Emulador>[],
        error: 'Flutter no contestó al pedirle los emuladores',
      );
    }

    final catalogo = ComandoDeEmuladores.leerTabla(catalogoBruto.salida);
    // Estos dos sí en paralelo: son de plataformas distintas y no comparten
    // ningún lock. El de Android son varios procesos cortos y el de iOS uno.
    final (avds, ios) = await (_avdsArriba(), _hayIosArriba()).wait;

    return (
      emuladores: ComandoDeEmuladores.conEstado(
        catalogo,
        avdsArriba: avds,
        iosArriba: ios,
      ),
      error: null,
    );
  }

  /// Los teléfonos de verdad enchufados. **Los 7 segundos viven aquí.**
  ///
  /// Se queda con `flutter devices --machine` a pesar del coste, y no con
  /// `adb devices` más `devicectl` —que juntos son 130 ms— por el identificador:
  /// `devicectl` devuelve el UUID de CoreDevice
  /// (`5B1BD75F-2EC3-…`) y no el UDID que pide `-d`
  /// (`00008030-000C390C1AC0C02E`). Enseñar un id que no sirve para lo que se
  /// dice que sirve es peor que tardar.
  Future<List<DispositivoConectado>> listarDispositivos() async {
    final flutter = await _flutter();
    if (flutter == null) return const [];

    final bruto = await _correr(flutter, ['devices', '--machine']);
    if (bruto == null) return const [];

    // **Solo `stdout`.** Pegarle el `stderr` detrás es lo que rompía esto.
    return _conNombresDeVerdad(
      ComandoDeEmuladores.leerDispositivos(bruto.salida),
    );
  }

  /// Cambia los nombres que reporta Flutter por los que entiende una persona.
  ///
  /// **Porque los de Flutter no sirven para elegir.** Un Android sale con su
  /// código de modelo —`24069PC21G`— y todos los iPhone salen llamados «iPhone»,
  /// así que con dos aparatos enchufados no hay forma de saber cuál es cuál. Se
  /// reportó tal cual: «aparecen así y no sé cuál es cuál».
  ///
  /// Cada plataforma lo sabe por su lado y las dos son rápidas: `getprop
  /// ro.product.marketname` da «POCO F6» en 72 ms, y `devicectl` da «iPhone 11»
  /// en 116. Si alguna no contesta se queda el nombre de antes: un nombre pobre
  /// es mejor que ninguno.
  Future<List<DispositivoConectado>> _conNombresDeVerdad(
    List<DispositivoConectado> dispositivos,
  ) async {
    if (dispositivos.isEmpty) return dispositivos;

    final nombresIos = dispositivos.any(
          (d) => d.plataforma == PlataformaEmulador.ios,
        )
        ? await _nombresDeIos()
        : const <String, String>{};

    final adb = dispositivos.any((d) => d.plataforma == PlataformaEmulador.android)
        ? await _adb()
        : null;

    return [
      for (final d in dispositivos)
        DispositivoConectado(
          id: d.id,
          nombre: switch (d.plataforma) {
            PlataformaEmulador.ios => nombresIos[d.id] ?? d.nombre,
            PlataformaEmulador.android =>
              await _nombreAndroid(adb, d.id) ?? d.nombre,
          },
          plataforma: d.plataforma,
        ),
    ];
  }

  Future<String?> _nombreAndroid(String? adb, String id) async {
    if (adb == null) return null;
    final salida = await _correr(adb, [
      '-s',
      id,
      'shell',
      'getprop',
      'ro.product.marketname',
    ]);
    final nombre = salida?.salida.trim();
    return nombre == null || nombre.isEmpty ? null : nombre;
  }

  Future<Map<String, String>> _nombresDeIos() async {
    // `devicectl` escribe el JSON en un archivo y no por stdout, así que hay que
    // darle uno temporal y leerlo.
    final destino =
        '${Directory.systemTemp.path}/nexus-devicectl-'
        '${DateTime.now().microsecondsSinceEpoch}.json';
    final r = await _correr('/usr/bin/xcrun', [
      'devicectl',
      'list',
      'devices',
      '--json-output',
      destino,
    ]);
    if (r == null) return const {};

    final archivo = File(destino);
    if (!archivo.existsSync()) return const {};
    try {
      return ComandoDeEmuladores.nombresDeIos(archivo.readAsStringSync());
    } on FileSystemException {
      return const {};
    } finally {
      try {
        archivo.deleteSync();
      } on FileSystemException {
        // Un temporal que no se puede borrar no es motivo para no dar nombres.
      }
    }
  }

  /// **El comando dispara y vuelve en ~1 s, pero el emulador tarda ~20 s en
  /// existir**, así que después de lanzarlo hay que esperar a que aparezca. Sin
  /// esto la pantalla refrescaba la lista justo al volver el comando —cuando el
  /// emulador todavía no estaba arriba— y la fila volvía a decir «Arrancar» con
  /// el emulador abriéndose delante de tus ojos. Visto en vivo, y es la clase de
  /// fallo que hace desconfiar de la pantalla entera.
  ///
  /// Se espera aquí y no en el widget a propósito: así el indicador de la fila
  /// cubre el arranque de verdad —está girando porque *está* arrancando— y las
  /// pruebas de la pantalla no heredan ningún plazo, porque sustituyen esto.
  ///
  /// Lo que **no** se hace es sostener el proceso: el emulador es hijo del
  /// toolchain y sobrevive a cerrar la app. Cerrar Nexus no puede costarte la
  /// sesión de pruebas.
  Future<String?> lanzar(
    Emulador emulador, {
    bool frio = false,
    Duration cada = const Duration(seconds: 2),
    int intentos = 45,
  }) async {
    final flutter = await _flutter();
    if (flutter == null) return 'No se encontró Flutter';

    final salida = await _correr(
      flutter,
      ComandoDeEmuladores.argumentosDeLanzar(emulador, frio: frio),
      // Un arranque en frío de Android tarda de verdad; el comando vuelve antes,
      // pero si el toolchain se atasca no queremos colgar la pantalla.
      tope: const Duration(minutes: 3),
    );
    if (salida == null) return 'Flutter no contestó al lanzar el emulador';

    // Aquí sí van los dos juntos: el veredicto se lee por líneas y el motivo
    // puede llegar por cualquiera de las dos. Es lo contrario del JSON.
    final veredicto = ComandoDeEmuladores.resultadoDeLanzar(
      '${salida.salida}\n${salida.error}',
    );
    if (veredicto.error != null) return veredicto.error;

    // Se comprueba **antes** de esperar: uno que ya estaba arriba no cuesta ni
    // un plazo.
    for (var intento = 0; intento < intentos; intento++) {
      if (await _estaArriba(emulador)) return null;
      await Future<void>.delayed(cada);
    }

    // Noventa segundos y no aparece. No es un fallo del lanzamiento —puede
    // seguir arrancando— así que se dice eso y no «no se pudo».
    return 'Se lanzó, pero todavía no aparece arrancado';
  }

  /// Si un emulador concreto ya está arriba.
  ///
  /// Pregunta solo por su plataforma: esperar a un simulador de iOS no tiene por
  /// qué costar los `adb` de Android ni al revés.
  Future<bool> _estaArriba(Emulador emulador) async {
    if (emulador.plataforma == PlataformaEmulador.ios) return _hayIosArriba();

    final avds = await _avdsArriba();
    return avds.keys.any(
      (avd) => avd == emulador.id || avd == emulador.nombre,
    );
  }

  /// Cierra uno. `null` si salió bien.
  ///
  /// Cada plataforma por su lado, y en iOS son **dos pasos**: apagar el
  /// simulador y además cerrar la app. Sin lo segundo queda la ventana abierta en
  /// negro, que se lee como que sigue arrancado.
  Future<String?> cerrar(Emulador emulador) async {
    if (emulador.plataforma == PlataformaEmulador.ios) {
      final apagado = await _correr('/usr/bin/xcrun', [
        'simctl',
        'shutdown',
        'all',
      ]);
      if (apagado == null) return 'No se pudo apagar el simulador';
      // Si esto falla no es un fallo del cierre: el simulador ya está apagado y
      // lo único que queda es una ventana. Se ignora a propósito.
      await _correr('/usr/bin/osascript', ['-e', 'quit app "Simulator"']);
      return null;
    }

    final deviceId = emulador.deviceId;
    if (deviceId == null) return 'No se supo qué emulador cerrar';

    final adb = await _adb();
    if (adb == null) return 'No se encontró adb para cerrar el emulador';

    final salida = await _correr(
      adb,
      ComandoDeEmuladores.argumentosDeCerrarAndroid(deviceId),
    );
    return salida == null ? 'adb no contestó al cerrar el emulador' : null;
  }

  // ── Lo de dentro ───────────────────────────────────────────────────────────

  Future<String?> _flutter() => HerramientaExterna.donde(
    'flutter',
    candidatos: HerramientaExterna.candidatosDeFlutter(
      Platform.environment['HOME'] ?? '',
    ),
  );

  Future<String?> _adb() => HerramientaExterna.donde(
    'adb',
    candidatos: HerramientaExterna.candidatosDeAdb(
      Platform.environment['HOME'] ?? '',
    ),
  );

  /// Del nombre del AVD al dispositivo con el que se cierra.
  ///
  /// Dos pasos porque no hay uno: `adb devices` da `emulator-5554` y hay que
  /// preguntarle a cada uno **su** nombre de AVD. Es una llamada por emulador
  /// arriba, que en la práctica son uno o dos.
  Future<Map<String, String>> _avdsArriba() async {
    final adb = await _adb();
    if (adb == null) return const {};

    final devices = await _correr(adb, ['devices']);
    if (devices == null) return const {};

    final arriba = <String, String>{};
    for (final id in ComandoDeEmuladores.idsDeEmuladorEnAdb(devices.salida)) {
      final nombre = await _correr(adb, ['-s', id, 'emu', 'avd', 'name']);
      if (nombre == null) continue;
      // Contesta el nombre y luego un `OK`: solo vale la primera línea.
      final limpio = nombre.salida.trim().split('\n').first.trim();
      if (limpio.isNotEmpty) arriba[limpio] = id;
    }
    return arriba;
  }

  Future<bool> _hayIosArriba() async {
    final salida = await _correr('/usr/bin/xcrun', [
      'simctl',
      'list',
      'devices',
      'booted',
      '--json',
    ]);
    return salida == null
        ? false
        : ComandoDeEmuladores.hayIosArriba(salida.salida);
  }

  /// `null` cuando el proceso no llegó a contestar. Un código de salida distinto
  /// de cero **no** es `null`: `flutter emulators` puede salir mal y haber
  /// impreso algo útil, y ese texto es lo que se le enseña al usuario.
  ///
  /// **Las dos salidas separadas y no pegadas**, y esto costó un fallo real:
  /// juntarlas mete el «Waiting for another flutter command…» de stderr detrás
  /// del JSON de stdout, y entonces no hay JSON. Quien parsea decide qué mira —
  /// el JSON solo stdout, un veredicto por líneas las dos.
  Future<({String salida, String error})?> _correr(
    String binario,
    List<String> argumentos, {
    Duration tope = const Duration(seconds: 90),
  }) async {
    try {
      final resultado = await Process.run(
        binario,
        argumentos,
        environment: ClaudeEnvironment.forTools(),
        includeParentEnvironment: false,
      ).timeout(tope);
      return (salida: '${resultado.stdout}', error: '${resultado.stderr}');
    } on ProcessException {
      return null;
    } on Exception {
      // El `timeout` lanza `TimeoutException`, que no es una `ProcessException`.
      // Un emulador que tarda tres minutos no puede dejar la pantalla colgada.
      return null;
    }
  }
}
