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

  /// El catálogo con su estado. `null` si no se encuentra Flutter, que es lo
  /// único sin lo que aquí no hay nada que hacer.
  ///
  /// El estado de cada plataforma se pide **en paralelo y tolerando el fallo de
  /// una**: con el SDK de Android a medio instalar, `adb` revienta mientras
  /// `simctl` contesta bien, y quedarse sin lista entera por eso sería peor que
  /// enseñar los de iOS.
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

    final salida = await _correr(flutter, ['emulators']);
    if (salida == null) {
      return (
        emuladores: const <Emulador>[],
        error: 'Flutter no contestó al pedirle los emuladores',
      );
    }

    final catalogo = ComandoDeEmuladores.leerTabla(salida);
    // Los dos a la vez: el de Android son varios procesos y el de iOS uno lento.
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

  /// Arranca uno. `null` si salió bien; el motivo si no.
  ///
  /// **El veredicto sale de la salida y no del código de salida**, porque
  /// `flutter emulators --launch` sale con 0 aunque no encuentre el emulador. Ver
  /// [ComandoDeEmuladores.resultadoDeLanzar].
  ///
  /// No espera el arranque: el comando dispara y vuelve en ~1 s. Por eso Nexus no
  /// tiene que sostener ningún proceso, y por eso el emulador sobrevive a cerrar
  /// la app — que es lo que se quiere: cerrar Nexus no puede costarte la sesión
  /// de pruebas.
  Future<String?> lanzar(Emulador emulador, {bool frio = false}) async {
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

    return ComandoDeEmuladores.resultadoDeLanzar(salida).error;
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
    for (final id in ComandoDeEmuladores.idsDeEmuladorEnAdb(devices)) {
      final nombre = await _correr(adb, ['-s', id, 'emu', 'avd', 'name']);
      if (nombre == null) continue;
      // Contesta el nombre y luego un `OK`: solo vale la primera línea.
      final limpio = nombre.trim().split('\n').first.trim();
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
    return salida == null ? false : ComandoDeEmuladores.hayIosArriba(salida);
  }

  /// `null` cuando el proceso no llegó a contestar. Un código de salida distinto
  /// de cero **no** es `null`: `flutter emulators` puede salir mal y haber
  /// impreso algo útil, y ese texto es lo que se le enseña al usuario.
  Future<String?> _correr(
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
      final salida = '${resultado.stdout}${resultado.stderr}';
      return salida;
    } on ProcessException {
      return null;
    } on Exception {
      // El `timeout` lanza `TimeoutException`, que no es una `ProcessException`.
      // Un emulador que tarda tres minutos no puede dejar la pantalla colgada.
      return null;
    }
  }
}
