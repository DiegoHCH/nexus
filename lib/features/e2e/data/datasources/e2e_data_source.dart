import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:nexus/core/platform/claude_environment.dart';
import 'package:nexus/core/platform/herramienta_externa.dart';
import 'package:nexus/features/e2e/domain/entities/pasada_de_prueba.dart';
import 'package:nexus/features/e2e/domain/usecases/donde_viven_las_pasadas.dart';
import 'package:nexus/features/e2e/domain/usecases/la_pasada_como_html.dart';
import 'package:nexus/features/e2e/domain/usecases/las_variables_del_proyecto.dart';
import 'package:nexus/features/e2e/domain/usecases/pasos_de_una_prueba.dart';
import 'package:nexus/features/e2e/domain/usecases/por_que_se_cayo.dart';
import 'package:nexus/features/e2e/domain/usecases/lector_de_pasadas.dart';
import 'package:path_provider/path_provider.dart';

/// Las pruebas de Maestro de un proyecto y lo que dejaron al correr.
class E2eDataSource {
  const E2eDataSource();

  /// La raíz donde Nexus guarda lo suyo.
  static Future<String> raiz() async {
    final soporte = await getApplicationSupportDirectory();
    return '${soporte.path}/pruebas';
  }

  /// Los `.yaml` de la carpeta de pruebas, que ya llega resuelta.
  ///
  /// **Plano y sin bajar, venga de donde venga.** Entrar más abajo metería en la lista los
  /// flows auxiliares que casi todo proyecto guarda en un subdirectorio para llamarlos con
  /// `runFlow` —`commons/`, `auth/`— y esos no se lanzan solos. Medido en un repo de
  /// verdad: de sus 57 YAML, 38 son pruebas y 19 son piezas.
  ///
  /// Que la carpeta llegue decidida y no se componga aquí es lo que permite que las
  /// pruebas vivan fuera del repo sin que este archivo sepa nada de proyectos.
  Future<List<Prueba>> pruebasDe(String carpetaDePruebas) async {
    final dir = Directory(carpetaDePruebas);
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

  /// Deja constancia de una pasada, en un archivo nuestro.
  ///
  /// **Existe porque el historial no debe depender de un archivo ajeno.** Lo que
  /// pasó lo sabe Nexus con certeza: lo ha leído paso a paso de la salida mientras
  /// corría, así que se anota aquí y punto.
  ///
  /// Aquí había antes un párrafo que decía, como hecho medido, que la carpeta del
  /// flow de Maestro «no aparece dentro de la app» y que «no se dio con el motivo».
  /// **Era falso**, y conviene que quede escrito porque un comentario así hace que
  /// nadie vuelva a mirar: la carpeta se escribe siempre. Lo que pasaba es que yo
  /// la buscaba en `~/.maestro/tests`, el sitio por defecto —el que deja de usarse
  /// justo porque le pasamos `--debug-output`—. Maestro añade `.maestro/tests`
  /// **dentro** de la ruta que se le da, y ahí estaban todas. Ver
  /// [carpetaDeArtefactos].
  ///
  /// **La ruta del proyecto va dentro del registro**, no solo en el nombre de la
  /// carpeta: esa lleva el nombre legible de la app y dos proyectos pueden
  /// llamarse igual. La atribución sale del dato.
  Future<void> anotaLaPasada({
    required String raiz,
    required String perfil,
    required String proyecto,
    required Map<String, Object?> pasada,
  }) async {
    final dir = Directory(
      DondeVivenLasPasadas.de(raiz: raiz, proyecto: proyecto),
    );
    try {
      dir.createSync(recursive: true);
      final cuando =
          DateTime.tryParse('${pasada['cuando'] ?? ''}') ?? DateTime.now();
      final nombre = DondeVivenLasPasadas.nombreDelRegistro(
        flow: '${pasada['flow'] ?? 'prueba'}',
        cuando: cuando,
      );
      File('${dir.path}/$nombre.json').writeAsStringSync(
        jsonEncode({...pasada, 'proyecto': proyecto, 'perfil': perfil}),
      );
    } on FileSystemException {
      // Sin poder anotar, la pasada ya pasó igual: se pierde del historial y no
      // se pierde nada más.
    }
  }

  /// Las pasadas que lanzó Nexus, de los registros que dejó.
  ///
  /// Un nivel de carpetas —una por app— y los registros dentro. El proyecto sale
  /// **del registro** y no de la carpeta, por lo dicho en [anotaLaPasada].
  Future<List<PasadaDePrueba>> propias(String raiz) async {
    final base = Directory(raiz);
    if (!base.existsSync()) return const [];

    final pasadas = <PasadaDePrueba>[];
    for (final app in _carpetas(base)) {
      // La casa de Maestro dentro de una app es su ruido, no una pasada nuestra.
      if (app.path.split('/').last.startsWith('.')) continue;

      for (final archivo in _archivosJson(app)) {
        if (LectorDePasadas.leerRegistro(
              archivo.readAsStringSync(),
              carpeta: archivo.path,
            )
            case final pasada?) {
          pasadas.add(pasada);
        }
      }
    }
    return pasadas;
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
  /// Nexus, así que esas pasadas no llevan nuestro `--debug-output` y aterrizan
  /// aquí. Sin esto desaparecerían del panel, y una lista que esconde la mitad de
  /// lo que pasó es peor que no tener lista.
  ///
  /// El proyecto se atribuye por el nombre del flow —ver
  /// [LectorDePasadas.atribuyePorNombre]—, que es una heurística: coincidencia
  /// única se atribuye, varias se dejan sin atribuir.
  Future<List<PasadaDePrueba>> ajenas(
    Map<String, List<String>> pruebasPorProyecto,
  ) async {
    // La casa de Maestro, que es la misma estructura que él añade a cualquier
    // ruta que se le dé: `~/.maestro/tests`.
    final casa = Directory(
      '${Platform.environment['HOME']}/'
      '${DondeVivenLasPasadas.loQueAnadeMaestro}',
    );
    if (!casa.existsSync()) return const [];

    final pasadas = <PasadaDePrueba>[];
    for (final fecha in _carpetas(casa)) {
      for (final pasada in _pasadasEn(fecha)) {
        final quien = LectorDePasadas.atribuyePorNombre(
          pasada.flow,
          pruebasPorProyecto,
        );
        pasadas.add(
          PasadaDePrueba(
            carpeta: pasada.carpeta,
            flow: pasada.flow,
            cuando: pasada.cuando,
            comoAcabo: pasada.comoAcabo,
            proyecto: quien.proyecto,
            dispositivo: pasada.dispositivo,
            pasos: pasada.pasos,
            pasosBien: pasada.pasosBien,
            capturas: pasada.capturas,
          ),
        );
      }
    }
    return pasadas;
  }

  /// Lanza una prueba, **diciéndole dónde escribir**.
  ///
  /// `--no-ansi` no es opcional: sin él la salida es un redibujado de terminal y
  /// no líneas, y de esas líneas vive la vista en vivo.
  /// Las variables del proyecto, de su `.env.local`.
  ///
  /// Se lee **en el momento de usarlas** y no se guarda en ningún estado de la app:
  /// un valor que no está en memoria más tiempo del necesario no puede acabar en un
  /// volcado ni en un mensaje de error por accidente.
  /// Las credenciales: **primero junto a las pruebas, y si no, en el proyecto**.
  ///
  /// El orden no es capricho. Cuando las pruebas viven fuera del repo —que es medio motivo
  /// para sacarlas— sus credenciales viven con ellas; obligar a dejar un `.env.local`
  /// dentro del repo del trabajo sería devolver justo lo que se quería quitar de ahí.
  /// Y con las pruebas dentro, las dos rutas son la misma y no cambia nada.
  Map<String, String> variablesDe(String proyecto, {String? carpetaDePruebas}) {
    for (final donde in <String>{
      if (carpetaDePruebas != null && carpetaDePruebas.isNotEmpty)
        carpetaDePruebas,
      proyecto,
    }) {
      final archivo = File('$donde/${LasVariablesDelProyecto.archivo}');
      if (!archivo.existsSync()) continue;
      try {
        return LasVariablesDelProyecto.leer(archivo.readAsStringSync());
      } on FileSystemException {
        continue;
      }
    }
    return const {};
  }

  Future<Process?> lanzar({
    required String flow,
    required String proyecto,
    required String deviceId,
    required String salida,
    Map<String, String> variables = const {},
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
        argumentosDe(
          deviceId: deviceId,
          salida: salida,
          flow: flow,
          variables: variables,
        ),
        workingDirectory: proyecto,
        environment: ClaudeEnvironment.forTools(),
        includeParentEnvironment: false,
      );
    } on ProcessException {
      return null;
    }
  }

  /// Dónde dejó Maestro los artefactos de la pasada que acaba de terminar.
  ///
  /// **Maestro añade `.maestro/tests/<fecha_hora>/` dentro de la ruta que se le
  /// da**, así que la carpeta exacta no se sabe al lanzar: la elige él. Se busca
  /// después, y es fiable porque solo corre una prueba a la vez —así que la más
  /// reciente que contenga este flow es la nuestra—.
  ///
  /// Se intentó primero leerla de la salida, que Maestro la imprime:
  /// `==== Debug output (logs & screenshots) ====`. No sirve: **solo la imprime
  /// cuando la pasada falla.** En una que pasa no aparece esa línea.
  String? carpetaDeArtefactos({required String salida, required String flow}) {
    final tests = Directory(
      '$salida/${DondeVivenLasPasadas.loQueAnadeMaestro}',
    );
    if (!tests.existsSync()) return null;

    Directory? masReciente;
    String? dentro;
    for (final fecha in _carpetas(tests)) {
      final elegida = _laDelFlow(fecha, flow);
      if (elegida == null) continue;
      // Por nombre y no por fecha en disco: el nombre es la hora que puso Maestro
      // y ordena igual, sin depender de qué toque los archivos después.
      if (masReciente == null ||
          fecha.path
                  .split('/')
                  .last
                  .compareTo(masReciente.path.split('/').last) >
              0) {
        masReciente = fecha;
        dentro = elegida;
      }
    }
    return dentro;
  }

  /// La carpeta de artefactos del flow dentro de una pasada de Maestro.
  ///
  /// 🔴 **Maestro la nombra con el `name:` del YAML, no con el del archivo.** Se
  /// midió: `01-login-error-flow.yaml` con `name: Login Error Flow` deja la
  /// carpeta `Login Error Flow`. Buscando por el nombre del archivo no se
  /// encontraba nada y las capturas no salían — invisible hasta ahora porque en
  /// las pruebas locales el archivo y el `name:` coincidían (`login` ↔ `login`).
  ///
  /// Se prefiere la coincidencia exacta, y si no la hay se coge **la única que
  /// haya**: Nexus lanza un flow por pasada, así que una sola carpeta ahí dentro
  /// es ese flow y no hay ambigüedad que resolver. Con varias y ninguna que case,
  /// se prefiere no adivinar.
  String? _laDelFlow(Directory fecha, String flow) {
    final hijas = _carpetas(fecha);
    for (final hija in hijas) {
      if (hija.path.split('/').last == flow) return hija.path;
    }
    return hijas.length == 1 ? hijas.single.path : null;
  }

  /// Las capturas de una pasada, **ya embebidas** para poder pintarlas.
  ///
  /// Devuelve `nombre -> data:` porque la página es autocontenida y el visor solo
  /// tiene permiso de lectura sobre la carpeta del propio archivo: una imagen
  /// referenciada fuera de ahí saldría como un hueco en blanco.
  ///
  /// La clave es el nombre sin extensión, que es **el mismo que dice el paso**
  /// —`Take screenshot login_form` ↔ `login_form.png`— y por eso cada captura
  /// puede pintarse debajo del paso que la tomó en vez de en un montón al final.
  Map<String, String> capturasDe(String? carpeta) {
    if (carpeta == null) return const {};

    final capturas = <String, String>{};
    for (final ruta in _capturasEn('$carpeta/takeScreenshot')) {
      final nombre = ruta
          .split('/')
          .last
          .replaceAll(RegExp(r'\.png$', caseSensitive: false), '');
      try {
        capturas[nombre] =
            'data:image/png;base64,${base64Encode(File(ruta).readAsBytesSync())}';
      } on FileSystemException {
        continue;
      }
    }
    return capturas;
  }

  /// La página que se le escribe a una pasada guardada, al lado de su registro.
  ///
  /// Derivada del registro y no inventada: así **quien borra la pasada sabe qué
  /// página se lleva con ella** sin tener que buscarla.
  static String paginaDe(String registro) =>
      '${registro.replaceAll(RegExp(r'\.json$'), '')}.html';

  /// Con qué se llama a Maestro.
  ///
  /// **Aparte para poder comprobarlo.** Lo que importa aquí no es el proceso sino
  /// el orden y, sobre todo, qué acaba en el `argv`: los valores de `-e` son
  /// visibles con `ps`, así que la prueba que dice «solo llegan las variables de
  /// esta prueba» tiene que poder existir.
  ///
  /// `--no-ansi` no es opcional: sin él la salida es un redibujado de terminal y no
  /// líneas, y de esas líneas vive la vista en vivo.
  static List<String> argumentosDe({
    required String deviceId,
    required String salida,
    required String flow,
    Map<String, String> variables = const {},
  }) => [
    '--device',
    deviceId,
    'test',
    '--no-ansi',
    // **`-e` y no el entorno del proceso**, porque no hay otra forma. Se midió: con
    // la variable puesta en el entorno del proceso, un
    // `assertTrue: \${SECRETO == "zanahoria"}` **falla**; con
    // `-e SECRETO=zanahoria` pasa. Maestro no lee el entorno.
    //
    // La consecuencia se asume: estos valores quedan en el `argv` y se ven con
    // `ps`. No ensancha el círculo de confianza —quien puede leer el `argv` puede
    // leer el `.env.local`— pero por eso llegan ya filtradas a las que este flow
    // usa, y no el archivo entero.
    for (final v in variables.entries) ...['-e', '${v.key}=${v.value}'],
    '--debug-output',
    salida,
    flow,
  ];

  /// Borra lo que dejó una pasada.
  ///
  /// **Solo artefactos, nunca el `.yaml`.** Lo que se borra aquí es reproducible;
  /// el flow es código del usuario y vive en git.
  ///
  /// **Dos formas, porque una pasada deja dos cosas distintas**: las nuestras son
  /// un registro `.json` suelto, las de Maestro una carpeta con su `commands.json`
  /// dentro. Esto solo sabía borrar carpetas, y `Directory(ruta).existsSync()` con
  /// un archivo da `false`: se salía por «no hay nada que borrar» devolviendo
  /// `null`, que quien llama lee como éxito. Resultado: **borrar una pasada
  /// lanzada por Nexus no hacía nada** y la fila volvía al refrescar la lista. No
  /// daba error en ningún sitio, que es lo que lo hizo durar.
  Future<String?> borrar(String ruta) async {
    try {
      final carpeta = Directory(ruta);
      if (carpeta.existsSync()) {
        carpeta.deleteSync(recursive: true);
        return null;
      }
      final registro = File(ruta);
      if (!registro.existsSync()) return null;
      registro.deleteSync();
      // Y su página, que es derivada del registro: sin él no lleva a ninguna
      // parte y quedaría ocupando sitio sin que nada la enseñe.
      final pagina = File(paginaDe(ruta));
      if (pagina.existsSync()) pagina.deleteSync();
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
    if (deviceId.contains('-') && !deviceId.startsWith('emulator-')) {
      return null;
    }

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

  /// Escribe la página de la pasada y **abre su ventana**, o la actualiza.
  ///
  /// **Se reusa el visor de documentos y no se escribe una ventana nueva.** Es una
  /// `NSWindow` con un `WKWebView` que ya vigila el archivo y se recarga cuando
  /// cambia, así que reescribir aquí en cada paso da exactamente lo que hacía
  /// falta: una ventana independiente que se actualiza sola, no bloquea la app y
  /// se puede dejar al lado mientras se trabaja.
  ///
  /// La ruta es **estable por pasada**, y eso importa: el visor lleva sus
  /// ventanas por archivo, así que reescribir la misma ruta actualiza la que ya
  /// está delante en vez de abrir otra en cada paso.
  ///
  /// Estrecha y alta —440 × 900— porque lo que se enseña es una columna de pasos.
  Future<void> pintaLaPasada({
    required String flow,
    required String html,
    required bool primeraVez,
    required String raizDeLaVentana,
  }) async {
    // Carpeta propia y oculta: es un archivo de trabajo, no algo que mirar en el
    // Finder, y así nadie más escribe donde el visor está vigilando.
    //
    // Aquí había antes un comentario que daba el temporal del sistema como *la*
    // causa de que la página se quedara congelada. Era falso y conviene que quede
    // escrito: la causa está unas líneas más abajo —sobrescribir un archivo que ya
    // existe no genera ningún evento de carpeta, y el visor vigila la carpeta—. Lo
    // que hacía el temporal era justo lo contrario, taparlo: el ruido de otros
    // procesos provocaba recargas de rebote, así que refrescaba a ratos y por
    // casualidad.
    final carpeta = Directory('$raizDeLaVentana/.ventana');
    try {
      carpeta.createSync(recursive: true);
    } on FileSystemException {
      return;
    }
    final ruta = '${carpeta.path}/$flow.html';
    try {
      // **Se escribe aparte y se renombra encima**, y esto no es prudencia: es lo
      // único que hace que la ventana se entere.
      //
      // El visor vigila el **directorio** con un `DispatchSource`, y eso avisa
      // cuando cambia el *contenido de la carpeta* —un archivo que aparece, se va
      // o se renombra—, **no cuando cambia un archivo que ya estaba dentro**.
      // Sobrescribiendo el mismo archivo no llegaba ningún evento y la página se
      // quedaba en el primer paso con el indicador girando por CSS, que es lo que
      // se veía.
      //
      // Y explica por qué antes refrescaba a ratos: estaba en el temporal del
      // sistema, donde el ruido de otros procesos generaba esos eventos. Se
      // refrescaba por casualidad. Un renombrado dentro de la misma carpeta es
      // atómico, así que además nadie lee la página a medio escribir.
      final aparte = File('$ruta.parte')..writeAsStringSync(html);
      aparte.renameSync(ruta);
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
      // Sin canal nativo —en una prueba, o si el visor no está— la pasada sigue
      // igual: la ventana es una forma de mirarla, no la pasada.
    } on MissingPluginException {
      return;
    }
  }

  /// El mismo canal que el visor de documentos: es literalmente el mismo visor.
  static const _visor = MethodChannel('com.katanalabs.nexus/artifacts');

  /// Abre el informe de una pasada que ya acabó, en la misma ventana aparte.
  ///
  /// Una pasada terminada es una en marcha quieta, así que se mira igual: se
  /// escribe su página al lado de su registro y se abre el visor. No hacía falta
  /// una segunda forma de enseñar lo mismo.
  /// [explica] traduce el motivo del fallo, si se reconoce.
  ///
  /// **Se recibe en vez de leerse**: un data source no lee proveedores, y los
  /// textos son del idioma elegido. Quien llama —una pantalla— sí tiene los dos, así
  /// que la traducción entra por la puerta en vez de que esto se salte una capa.
  Future<void> abreElInforme(
    String registro, {
    String Function(PorQueSeCayo)? explica,
  }) async {
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
    final total = (leido['pasos'] as num?)?.toInt() ?? 0;

    final crudas = [
      for (final l in (leido['ruido'] as List?) ?? const []) '$l',
    ];

    final List<PasoParaPintar> pasos;
    final List<String> lineas;

    if (leido['salida'] case final String salida when salida.isNotEmpty) {
      // **Lo nuevo: se guarda la salida y se relee.** Los pasos salen de ella con
      // la misma función que en vivo, así que el informe enseña exactamente lo que
      // se vio correr —y no una lista del YAML que podía diferir—.
      pasos = PasosDeUnaPrueba.deLaSalida(salida);
      lineas = [
        for (final l in salida.split('\n'))
          if (l.trim().isNotEmpty) l.trimRight(),
        ...crudas,
      ];
    } else {
      // **Los registros viejos siguen abriéndose.** Guardaban los pasos del YAML y
      // una cuenta, así que se reconstruyen como se hacía antes: emparejando por
      // posición, con su degradación incluida. Un informe de ayer que se abre a
      // medias es mejor que uno que no se abre.
      final delFlow = <PasoDelFlow>[];
      var n = 0;
      for (final crudo in (leido['pasosDelFlow'] as List?) ?? const []) {
        n++;
        if (crudo is Map) {
          delFlow.add(
            PasoDelFlow(
              linea: (crudo['n'] as num?)?.toInt() ?? n,
              texto: '${crudo['t'] ?? ''}',
              detalle: [
                for (final d in (crudo['d'] as List?) ?? const []) '$d',
              ],
            ),
          );
        } else {
          delFlow.add(PasoDelFlow(linea: n, texto: '$crudo'));
        }
      }

      final estados = PasosDeUnaPrueba.estados(
        cuantosPasos: delFlow.length,
        terminados: terminados,
        viva: false,
        fallo: fallo,
      );
      pasos = [
        for (final (i, paso) in delFlow.indexed)
          PasoParaPintar(
            texto: paso.texto,
            estado: estados?[i] ?? EstadoDePaso.pendiente,
            detalle: paso.detalle,
            linea: paso.linea,
          ),
      ];
      lineas = [
        for (final l in (leido['lineas'] as List?) ?? const []) '$l',
        ...crudas,
      ];
    }

    final html = LaPasadaComoHtml.escribe(
      flow: flow,
      pasos: pasos,
      lineas: lineas,
      terminados: terminados,
      total: total == 0 ? pasos.length : total,
      viva: false,
      fallo: fallo,
      // Las capturas de aquella pasada, si su carpeta sigue estando. Un registro
      // viejo no la guarda y entonces no hay imágenes: el informe se abre igual.
      capturas: capturasDe(leido['artefactos'] as String?),
      diagnostico: !fallo || explica == null
          ? null
          : switch (PorQueSeCayoLaPasada.de(lineas.join('\n'))) {
              final PorQueSeCayo por => explica(por),
              null => null,
            },
    );

    // El nombre del archivo es **el título de la ventana**, y el del registro ya
    // dice exactamente lo que hace falta: «welcome_to_login 2026-08-26 09h3507».
    // Así que la página es el mismo nombre con otra extensión.
    //
    // Antes esto recomponía el nombre buscando un `T09-35` con una expresión
    // regular, del formato de sello de tiempo anterior. Al pasar los registros a
    // un nombre legible ese patrón dejó de casar y la página salía con el flow
    // repetido: «welcome_to_login welcome_to_login 2026-08-26 09h3507.html».
    final pagina = paginaDe(registro);
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

  /// ¿Está ese archivo en git?
  ///
  /// **Es lo que decide si borrar una prueba se puede deshacer**, y por eso se
  /// pregunta en vez de suponerlo: el aviso del panel prometía «se recupera con
  /// git» siempre, y con un flow recién escrito y sin commitear eso es falso justo
  /// en el momento en que más importa.
  ///
  /// `null` es «no se pudo saber» —sin git, o fuera de un repositorio— y entonces
  /// el aviso no promete nada en ninguna dirección. Decir «no está en git» porque
  /// no hay git sería inventarse la respuesta.
  Future<bool?> estaEnGit(String ruta) async {
    final corte = ruta.lastIndexOf('/');
    if (corte < 0) return null;

    try {
      final r = await Process.run(
        'git',
        [
          '-C',
          ruta.substring(0, corte),
          'ls-files',
          '--error-unmatch',
          '--',
          ruta,
        ],
        runInShell: false,
        environment: ClaudeEnvironment.forTools(),
      );
      // 0 lo conoce, 1 no lo conoce, 128 no hay repositorio. Solo las dos
      // primeras son una respuesta.
      return switch (r.exitCode) {
        0 => true,
        1 => false,
        _ => null,
      };
    } on ProcessException {
      return null;
    }
  }

  /// Cuánto ocupa una pasada, para poder decirlo antes de borrar.
  ///
  /// Un registro nuestro o una carpeta de Maestro, por lo mismo que [borrar]: con
  /// un archivo, el `Directory` de antes daba `0`. Y un tamaño que sale `0`
  /// **cuando sí ocupa** es peor que no enseñarlo, porque se lee como «esto no
  /// pesa nada, bórralo tranquilo».
  int bytesDe(String ruta) {
    try {
      final registro = File(ruta);
      if (registro.existsSync()) {
        final pagina = File(paginaDe(ruta));
        return registro.lengthSync() +
            (pagina.existsSync() ? pagina.lengthSync() : 0);
      }

      final dir = Directory(ruta);
      if (!dir.existsSync()) return 0;
      var total = 0;
      for (final e in dir.listSync(recursive: true, followLinks: false)) {
        if (e is File) total += e.lengthSync();
      }
      return total;
    } on FileSystemException {
      return 0;
    }
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

  /// Las pasadas dentro de una carpeta de fecha. Cada flow es una subcarpeta.
  List<PasadaDePrueba> _pasadasEn(
    Directory fecha, {
    String? perfil,
    String? proyecto,
  }) {
    final cuando = LectorDePasadas.cuandoDe(fecha.path.split('/').last);
    if (cuando == null) return const [];

    final pasadas = <PasadaDePrueba>[];
    for (final flow in _carpetas(fecha)) {
      final nombre = flow.path.split('/').last;
      final commands = File('${flow.path}/commands.json');
      final leido = LectorDePasadas.leer(
        commands.existsSync() ? commands.readAsStringSync() : '',
      );

      pasadas.add(
        PasadaDePrueba(
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
    return pasadas;
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
