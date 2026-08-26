import 'dart:io';

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
