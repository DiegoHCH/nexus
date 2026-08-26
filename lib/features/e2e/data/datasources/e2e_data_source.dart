import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:nexus/core/platform/claude_environment.dart';
import 'package:nexus/core/platform/herramienta_externa.dart';
import 'package:nexus/features/e2e/domain/entities/corrida_de_prueba.dart';
import 'package:nexus/features/e2e/domain/usecases/donde_viven_las_corridas.dart';
import 'package:nexus/features/e2e/domain/usecases/la_corrida_como_html.dart';
import 'package:nexus/features/e2e/domain/usecases/pasos_de_una_prueba.dart';
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

  /// Deja constancia de una corrida, en un archivo nuestro.
  ///
  /// **Existe porque no se puede depender de que Maestro escriba la suya.** Se
  /// midió: dentro de la app, la carpeta del flow con su `commands.json` no
  /// aparece —el log queda completo, idéntico al de una corrida que sí la
  /// escribe, y esa carpeta se crea después de la última línea, al salir el
  /// proceso—. La misma llamada desde una shell y desde una prueba la escribe
  /// siempre. No se dio con el motivo.
  ///
  /// Lo que sí se sabe con certeza es lo que pasó, porque Nexus lo ha leído paso
  /// a paso de la salida mientras corría. Así que se anota aquí y el historial
  /// deja de depender de un archivo ajeno que a veces no llega.
  ///
  /// **La ruta del proyecto va dentro del registro**, no solo en el nombre de la
  /// carpeta: esa lleva el nombre legible de la app y dos proyectos pueden
  /// llamarse igual. La atribución sale del dato.
  Future<void> anotaLaCorrida({
    required String raiz,
    required String perfil,
    required String proyecto,
    required Map<String, Object?> corrida,
  }) async {
    final dir = Directory(
      DondeVivenLasCorridas.de(raiz: raiz, proyecto: proyecto),
    );
    try {
      dir.createSync(recursive: true);
      final cuando =
          DateTime.tryParse('${corrida['cuando'] ?? ''}') ?? DateTime.now();
      final nombre = DondeVivenLasCorridas.nombreDelRegistro(
        flow: '${corrida['flow'] ?? 'prueba'}',
        cuando: cuando,
      );
      File('${dir.path}/$nombre.json').writeAsStringSync(
        jsonEncode({...corrida, 'proyecto': proyecto, 'perfil': perfil}),
      );
    } on FileSystemException {
      // Sin poder anotar, la corrida ya pasó igual: se pierde del historial y no
      // se pierde nada más.
    }
  }

  /// Las corridas que lanzó Nexus, de los registros que dejó.
  ///
  /// Un nivel de carpetas —una por app— y los registros dentro. El proyecto sale
  /// **del registro** y no de la carpeta, por lo dicho en [anotaLaCorrida].
  Future<List<CorridaDePrueba>> propias(String raiz) async {
    final base = Directory(raiz);
    if (!base.existsSync()) return const [];

    final corridas = <CorridaDePrueba>[];
    for (final app in _carpetas(base)) {
      // La casa de Maestro dentro de una app es su ruido, no una corrida nuestra.
      if (app.path.split('/').last.startsWith('.')) continue;

      for (final archivo in _archivosJson(app)) {
        if (LectorDeCorridas.leerRegistro(
              archivo.readAsStringSync(),
              carpeta: archivo.path,
            )
            case final corrida?) {
          corridas.add(corrida);
        }
      }
    }
    return corridas;
  }

  List<File> _archivosJson(Directory dir) {
    try {
      return [
        for (final e in dir.listSync(followLinks: false))
          if (e is File && e.path.endsWith('.json')) e,
      ];
    } on FileSystemException {
      return const [];
    }
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
    required String raizDeLaVentana,
  }) async {
    // **Carpeta propia y no el temporal del sistema**, y esto era un fallo de
    // verdad: el visor vigila la *carpeta* del archivo, y en `/var/folders/…/T/`
    // escriben decenas de procesos. Cada evento ajeno cancelaba y reprogramaba su
    // recarga —el aplazamiento es de 0,25 s y se reinicia con cada evento— así que
    // se posponía casi indefinidamente. Se veía exactamente así: los pasos
    // congelados en el segundo, todos en visto de golpe al final, y la etiqueta
    // diciendo «Corriendo» medio minuto después de acabar.
    //
    // Con una carpeta que solo escribimos nosotros, cada escritura es un evento y
    // la recarga llega en su cuarto de segundo.
    // Oculta y aparte: es un archivo de trabajo, no algo que mirar en el Finder.
    // Y su propia carpeta arregla la recarga —ver el comentario de arriba—.
    final carpeta = Directory('$raizDeLaVentana/.ventana');
    try {
      carpeta.createSync(recursive: true);
    } on FileSystemException {
      return;
    }
    final ruta = '${carpeta.path}/$flow.html';
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

  /// Abre el informe de una corrida que ya acabó, en la misma ventana aparte.
  ///
  /// Una corrida terminada es una en marcha quieta, así que se mira igual: se
  /// escribe su página al lado de su registro y se abre el visor. No hacía falta
  /// una segunda forma de enseñar lo mismo.
  Future<void> abreElInforme(String registro) async {
    final archivo = File(registro);
    if (!archivo.existsSync()) return;

    final Object? leido;
    try {
      leido = jsonDecode(archivo.readAsStringSync());
    } on FormatException {
      return;
    }
    if (leido is! Map) return;

    final flow = '${leido['flow'] ?? ''}';
    final terminados = (leido['terminados'] as num?)?.toInt() ?? 0;
    final fallo = leido['fallo'] == true;
    // **Dos formatos, porque los registros viejos existen.** Antes se guardaba
    // una lista de cadenas; ahora, objetos con su número de línea y su detalle. Un
    // registro viejo se lee igual y se queda sin número: enseñarlo a medias es
    // mejor que no enseñarlo.
    final pasos = <PasoDelFlow>[];
    var n = 0;
    for (final crudo in (leido['pasosDelFlow'] as List?) ?? const []) {
      n++;
      if (crudo is Map) {
        pasos.add(
          PasoDelFlow(
            linea: (crudo['n'] as num?)?.toInt() ?? n,
            texto: '${crudo['t'] ?? ''}',
            detalle: [for (final d in (crudo['d'] as List?) ?? const []) '$d'],
          ),
        );
      } else {
        pasos.add(PasoDelFlow(linea: n, texto: '$crudo'));
      }
    }
    final total = (leido['pasos'] as num?)?.toInt() ?? pasos.length;

    final html = LaCorridaComoHtml.escribe(
      flow: flow,
      pasos: pasos,
      // Los mismos estados que en vivo, calculados igual: una corrida terminada
      // es una en marcha quieta. Los registros de antes de guardar los nombres no
      // traen pasos, y entonces se enseña solo la salida — que sigue siendo verdad.
      estados: pasos.isEmpty
          ? null
          : PasosDeUnaPrueba.estados(
              cuantosPasos: pasos.length,
              terminados: terminados,
              viva: false,
              fallo: fallo,
            ),
      lineas: [
        for (final l in (leido['lineas'] as List?) ?? const []) '$l',
      ],
      terminados: terminados,
      total: total,
      viva: false,
      fallo: fallo,
    );

    // El nombre del archivo es **el título de la ventana**, así que lleva el flow
    // y la hora en vez del sello de tiempo entero: «welcome_to_login 09-35» dice
    // qué es de un vistazo y `2026-08-26T09-35-40.375012` no.
    final hora = registro.split('/').last.replaceAll(RegExp(r'\.json$'), '');
    final corta = RegExp(r'T(\d{2})-(\d{2})').firstMatch(hora);
    final pagina =
        '${registro.substring(0, registro.lastIndexOf('/'))}/'
        // Con guion y no con dos puntos: en macOS un `:` en un nombre de archivo
        // se le enseña al usuario como `/`, así que «09:35» aparecería como
        // «09/35» y parecería otra carpeta.
        '$flow ${corta == null ? hora : '${corta.group(1)}h${corta.group(2)}'}.html';
    try {
      File(pagina).writeAsStringSync(html);
    } on FileSystemException {
      return;
    }
    try {
      await _visor.invokeMethod<bool>('open', {
        'path': pagina,
        'width': 440.0,
        'height': 900.0,
      });
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
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
