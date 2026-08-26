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

  /// El catálogo con su estado, **y los teléfonos que haya enchufados**.
  ///
  /// Los dos en una sola llamada porque se enseñan juntos: dos providers harían
  /// que «Comprobar» refrescara media pantalla, y un físico que se desenchufa
  /// mientras un emulador arranca dejaría la lista contándose una historia
  /// distinta en cada mitad.
  ///
  /// El estado de cada plataforma se pide **en paralelo y tolerando el fallo de
  /// una**: con el SDK de Android a medio instalar, `adb` revienta mientras
  /// `simctl` contesta bien, y quedarse sin lista entera por eso sería peor que
  /// enseñar los de iOS.
  Future<
    ({
      List<Emulador> emuladores,
      List<DispositivoConectado> dispositivos,
      String? error,
    })
  >
  listar() async {
    final flutter = await _flutter();
    if (flutter == null) {
      return (
        emuladores: const <Emulador>[],
        dispositivos: const <DispositivoConectado>[],
        error:
            'No se encontró Flutter. Se buscó en el PATH de la app, en las rutas '
            'de siempre y en tu shell de login.',
      );
    }

    // **En serie y no en paralelo**, aunque en paralelo parezca más listo: dos
    // `flutter` a la vez se pelean por el lock del SDK y el segundo imprime
    // «Waiting for another flutter command to release the startup lock…». No
    // falla —espera y contesta— pero no se gana nada, porque el trabajo se
    // serializa igual dentro del propio Flutter. Y sí se pierde: ese aviso en
    // stderr fue lo que rompió el parseo del JSON la primera vez.
    final catalogoBruto = await _correr(flutter, ['emulators']);
    final dispositivosBruto = await _correr(flutter, ['devices', '--machine']);

    if (catalogoBruto == null) {
      return (
        emuladores: const <Emulador>[],
        dispositivos: dispositivosBruto == null
            ? const <DispositivoConectado>[]
            // **Solo `stdout`.** El JSON está ahí, y pegarle el `stderr` detrás
            // es exactamente lo que rompía esto.
            : ComandoDeEmuladores.leerDispositivos(dispositivosBruto.salida),
        error: 'Flutter no contestó al pedirle los emuladores',
      );
    }

    final catalogo = ComandoDeEmuladores.leerTabla(catalogoBruto.salida);
    // Los dos a la vez: el de Android son varios procesos y el de iOS uno lento.
    final (avds, ios) = await (_avdsArriba(), _hayIosArriba()).wait;

    return (
      emuladores: ComandoDeEmuladores.conEstado(
        catalogo,
        avdsArriba: avds,
        iosArriba: ios,
      ),
      dispositivos: dispositivosBruto == null
          ? const <DispositivoConectado>[]
          : ComandoDeEmuladores.leerDispositivos(dispositivosBruto.salida),
      error: null,
    );
  }

  /// Arranca uno. `null` si salió bien; el motivo si no.
  ///
  /// **El veredicto sale de la salida y no del código de salida**, porque
  /// `flutter emulators --launch` sale con 0 aunque no encuentre el emulador. Ver
  /// [ComandoDeEmuladores.resultadoDeLanzar].
  ///
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
