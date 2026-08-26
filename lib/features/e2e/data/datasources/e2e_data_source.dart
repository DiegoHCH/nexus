import 'dart:io';

import 'package:flutter/services.dart';

import 'package:nexus/core/platform/claude_environment.dart';
import 'package:nexus/core/platform/herramienta_externa.dart';
import 'package:nexus/features/e2e/domain/entities/corrida_de_prueba.dart';
import 'package:nexus/features/e2e/domain/usecases/donde_viven_las_corridas.dart';
import 'package:nexus/features/e2e/domain/usecases/lector_de_corridas.dart';
import 'package:path_provider/path_provider.dart';

/// Las pruebas de Maestro de un proyecto y lo que dejaron al correr.
class E2eDataSource {
  const E2eDataSource();

  /// La raíz donde Nexus guarda lo suyo.
  static Future<String> raiz() async {
    final soporte = await getApplicationSupportDirectory();
    return '${soporte.path}/pruebas';
  }

  /// Los `.yaml` del `.maestro/` de un proyecto.
  ///
  /// **Solo la carpeta `.maestro/` y sin bajar más.** Es la convención de Maestro
  /// y entrar más abajo metería en la lista los flows auxiliares que algunos
  /// proyectos guardan en subcarpetas para llamarlos con `runFlow` — no son
  /// pruebas que se lancen solas.
  Future<List<Prueba>> pruebasDe(String proyecto) async {
    final dir = Directory('$proyecto/.maestro');
    if (!dir.existsSync()) return const [];

    try {
      return [
        for (final e in dir.listSync(followLinks: false))
          if (e is File)
            if (e.path.endsWith('.yaml') || e.path.endsWith('.yml'))
              Prueba(
                ruta: e.path,
                nombre: e.path
                    .split('/')
                    .last
                    .replaceAll(RegExp(r'\.ya?ml$'), ''),
              ),
      ]..sort((a, b) => a.nombre.compareTo(b.nombre));
    } on FileSystemException {
      return const [];
    }
  }

  /// Las corridas que lanzó Nexus, sacadas de su propio árbol.
  ///
  /// Sabe de qué perfil y de qué proyecto son **porque están donde las pusimos**,
  /// sin interpretar nada. Es la misma técnica que la lista de documentos: se
  /// entra solo donde se sabe qué hay.
  Future<List<CorridaDePrueba>> propias(String raiz) async {
    final base = Directory(raiz);
    if (!base.existsSync()) return const [];

    final corridas = <CorridaDePrueba>[];
    for (final perfil in _carpetas(base)) {
      for (final proyecto in _carpetas(perfil)) {
        final donde = Directory(
          '${proyecto.path}/${DondeVivenLasCorridas.loQueAnadeMaestro}',
        );
        for (final fecha in _carpetas(donde)) {
          corridas.addAll(
            _corridasEn(
              fecha,
              perfil: perfil.path.split('/').last,
              proyecto: DondeVivenLasCorridas.proyectoDe(
                proyecto.path.split('/').last,
              ),
            ),
          );
        }
      }
    }
    return corridas;
  }

  /// Las que lanzó cualquier otro, de la casa de Maestro.
  ///
  /// **La red de seguridad.** La herramienta `run` del MCP la llama Claude, no
  /// Nexus, así que esas corridas no llevan nuestro `--debug-output` y aterrizan
  /// aquí. Sin esto desaparecerían del panel, y una lista que esconde la mitad de
  /// lo que pasó es peor que no tener lista.
  ///
  /// El proyecto se atribuye por el nombre del flow —ver
  /// [LectorDeCorridas.atribuyePorNombre]—, que es una heurística: coincidencia
  /// única se atribuye, varias se dejan sin atribuir.
  Future<List<CorridaDePrueba>> ajenas(
    Map<String, List<String>> pruebasPorProyecto,
  ) async {
    // La casa de Maestro, que es la misma estructura que él añade a cualquier
    // ruta que se le dé: `~/.maestro/tests`.
    final casa = Directory(
      '${Platform.environment['HOME']}/'
      '${DondeVivenLasCorridas.loQueAnadeMaestro}',
    );
    if (!casa.existsSync()) return const [];

    final corridas = <CorridaDePrueba>[];
    for (final fecha in _carpetas(casa)) {
      for (final corrida in _corridasEn(fecha)) {
        final quien = LectorDeCorridas.atribuyePorNombre(
          corrida.flow,
          pruebasPorProyecto,
        );
        corridas.add(
          CorridaDePrueba(
            carpeta: corrida.carpeta,
            flow: corrida.flow,
            cuando: corrida.cuando,
            comoAcabo: corrida.comoAcabo,
            proyecto: quien.proyecto,
            dispositivo: corrida.dispositivo,
            pasos: corrida.pasos,
            pasosBien: corrida.pasosBien,
            capturas: corrida.capturas,
          ),
        );
      }
    }
    return corridas;
  }

  /// Lanza una prueba, **diciéndole dónde escribir**.
  ///
  /// `--no-ansi` no es opcional: sin él la salida es un redibujado de terminal y
  /// no líneas, y de esas líneas vive la vista en vivo.
  Future<Process?> lanzar({
    required String flow,
    required String proyecto,
    required String deviceId,
    required String salida,
  }) async {
    final maestro = await HerramientaExterna.donde(
      'maestro',
      candidatos: HerramientaExterna.candidatosDeMaestro(
        Platform.environment['HOME'] ?? '',
      ),
    );
    if (maestro == null) return null;

    try {
      return await Process.start(
        maestro,
        [
          '--device',
          deviceId,
          'test',
          '--no-ansi',
          '--debug-output',
          salida,
          flow,
        ],
        workingDirectory: proyecto,
        environment: ClaudeEnvironment.forTools(),
        includeParentEnvironment: false,
      );
    } on ProcessException {
      return null;
    }
  }

  /// Borra lo que dejó una corrida.
  ///
  /// **Solo artefactos, nunca el `.yaml`.** Lo que se borra aquí es reproducible;
  /// el flow es código del usuario y vive en git.
  Future<String?> borrar(String carpeta) async {
    final dir = Directory(carpeta);
    if (!dir.existsSync()) return null;
    try {
      dir.deleteSync(recursive: true);
      return null;
    } on FileSystemException catch (e) {
      return e.message;
    }
  }

  /// ¿Está la app instalada en ese dispositivo?
  ///
  /// `null` cuando no se puede saber —un iPhone, o sin `adb`— y entonces **no se
  /// bloquea nada**: no saber no es lo mismo que saber que no está, y negarse por
  /// no saber sería peor que dejar fallar a Maestro.
  ///
  /// Existe porque Maestro no instala: sin la app, la prueba falla en el primer
  /// `launchApp` con «Package … is not installed», **saliendo con código 0**. Ese
  /// aviso llega tarde y encima disfrazado de éxito.
  Future<bool?> estaInstalada({
    required String deviceId,
    required String appId,
  }) async {
    // Solo Android: un `emulator-…` o un número de serie. Un UDID de iPhone se
    // reconoce por sus guiones y por ahí no se puede preguntar con adb.
    if (deviceId.contains('-') && !deviceId.startsWith('emulator-')) return null;

    final adb = await HerramientaExterna.donde(
      'adb',
      candidatos: HerramientaExterna.candidatosDeAdb(
        Platform.environment['HOME'] ?? '',
      ),
    );
    if (adb == null) return null;

    final salida = await _correr(adb, [
      '-s',
      deviceId,
      'shell',
      'pm',
      'list',
      'packages',
      appId,
    ]);
    if (salida == null) return null;
    // `pm list packages <filtro>` hace prefijo, así que se compara la línea
    // entera: `com.app.ci` no puede darse por instalada porque exista
    // `com.app.ci.debug`.
    return salida.salida
        .split('\n')
        .map((l) => l.trim())
        .contains('package:$appId');
  }

  /// Escribe la página de la corrida y **abre su ventana**, o la actualiza.
  ///
  /// **Se reusa el visor de documentos y no se escribe una ventana nueva.** Es una
  /// `NSWindow` con un `WKWebView` que ya vigila el archivo y se recarga cuando
  /// cambia, así que reescribir aquí en cada paso da exactamente lo que hacía
  /// falta: una ventana independiente que se actualiza sola, no bloquea la app y
  /// se puede dejar al lado mientras se trabaja.
  ///
  /// La ruta es **estable por corrida**, y eso importa: el visor lleva sus
  /// ventanas por archivo, así que reescribir la misma ruta actualiza la que ya
  /// está delante en vez de abrir otra en cada paso.
  ///
  /// Estrecha y alta —440 × 900— porque lo que se enseña es una columna de pasos.
  Future<void> pintaLaCorrida({
    required String flow,
    required String html,
    required bool primeraVez,
  }) async {
    final ruta = '${Directory.systemTemp.path}/nexus-prueba-$flow.html';
    try {
      File(ruta).writeAsStringSync(html);
    } on FileSystemException {
      return;
    }
    if (!primeraVez) return;

    try {
      await _visor.invokeMethod<bool>('open', {
        'path': ruta,
        'width': 440.0,
        'height': 900.0,
      });
    } on PlatformException {
      // Sin canal nativo —en una prueba, o si el visor no está— la corrida sigue
      // igual: la ventana es una forma de mirarla, no la corrida.
    } on MissingPluginException {
      return;
    }
  }

  /// El mismo canal que el visor de documentos: es literalmente el mismo visor.
  static const _visor = MethodChannel('com.katanalabs.nexus/artifacts');

  /// Borra **la prueba**: su archivo `.yaml` del repo.
  ///
  /// Distinto de [borrar], que se lleva artefactos reproducibles. Esto toca
  /// código del usuario, y se ofrece porque **está en git**: se recupera con un
  /// `git checkout` y quien lo borra desde aquí sabe lo que hace. Lo que no se
  /// hace es borrarlo sin decir eso primero — la pantalla lo avisa.
  ///
  /// Un flow que no está en git se pierde de verdad, y eso no lo puede saber esta
  /// función: quien la llama tiene la información del repo, no ella.
  Future<String?> borrarPrueba(String ruta) async {
    final archivo = File(ruta);
    if (!archivo.existsSync()) return null;
    try {
      archivo.deleteSync();
      return null;
    } on FileSystemException catch (e) {
      return e.message;
    }
  }

  /// Cuánto ocupa una carpeta, para poder decirlo antes de borrar.
  int bytesDe(String carpeta) {
    final dir = Directory(carpeta);
    if (!dir.existsSync()) return 0;
    var total = 0;
    try {
      for (final e in dir.listSync(recursive: true, followLinks: false)) {
        if (e is File) total += e.lengthSync();
      }
    } on FileSystemException {
      return total;
    }
    return total;
  }

  /// Lanzar un binario y quedarse con lo que dijo.
  ///
  /// Las dos salidas **separadas**, por lo aprendido con los emuladores: pegar el
  /// `stderr` detrás del `stdout` rompe cualquier parseo que dependa del formato,
  /// y ahí se fue un rato con un JSON.
  Future<({String salida, String error})?> _correr(
    String binario,
    List<String> argumentos, {
    Duration tope = const Duration(seconds: 30),
  }) async {
    try {
      final r = await Process.run(
        binario,
        argumentos,
        environment: ClaudeEnvironment.forTools(),
        includeParentEnvironment: false,
      ).timeout(tope);
      return (salida: '${r.stdout}', error: '${r.stderr}');
    } on ProcessException {
      return null;
    } on Exception {
      return null;
    }
  }

  // ── Lo de dentro ───────────────────────────────────────────────────────────

  List<Directory> _carpetas(Directory dir) {
    if (!dir.existsSync()) return const [];
    try {
      return [
        for (final e in dir.listSync(followLinks: false))
          if (e is Directory) e,
      ];
    } on FileSystemException {
      // Una carpeta que no se puede leer no invalida las otras: se enseña lo que
      // haya. Devolver vacío entero por un permiso suelto esconde todo lo demás.
      return const [];
    }
  }

  /// Las corridas dentro de una carpeta de fecha. Cada flow es una subcarpeta.
  List<CorridaDePrueba> _corridasEn(
    Directory fecha, {
    String? perfil,
    String? proyecto,
  }) {
    final cuando = LectorDeCorridas.cuandoDe(fecha.path.split('/').last);
    if (cuando == null) return const [];

    final corridas = <CorridaDePrueba>[];
    for (final flow in _carpetas(fecha)) {
      final nombre = flow.path.split('/').last;
      final commands = File('${flow.path}/commands.json');
      final leido = LectorDeCorridas.leer(
        commands.existsSync() ? commands.readAsStringSync() : '',
      );

      corridas.add(
        CorridaDePrueba(
          carpeta: flow.path,
          flow: nombre,
          cuando: cuando,
          comoAcabo: leido.como,
          perfil: perfil,
          proyecto: proyecto,
          dispositivo: leido.dispositivo,
          pasos: leido.pasos,
          pasosBien: leido.bien,
          capturas: _capturasEn('${flow.path}/takeScreenshot'),
        ),
      );
    }
    return corridas;
  }

  List<String> _capturasEn(String carpeta) {
    final dir = Directory(carpeta);
    if (!dir.existsSync()) return const [];
    try {
      return [
        for (final e in dir.listSync(followLinks: false))
          if (e is File && e.path.endsWith('.png')) e.path,
      ];
    } on FileSystemException {
      return const [];
    }
  }
}
