import 'dart:convert';
import 'dart:io';

import 'package:nexus/features/assistant/data/repositories/project_context_prompt.dart';
import 'package:nexus/features/workspace/domain/usecases/reglas_declaradas.dart';

/// Busca en el disco lo que Claude debería saber antes de empezar: las reglas
/// del árbol de carpetas y el contexto compartido del repo.
///
/// El contrato de `ai-context` está escrito en su propio `CLAUDE.md` y esto lo
/// sigue al pie de la letra: se sube desde la carpeta de trabajo hasta dar con
/// una carpeta llamada **exactamente** `ai-context` que tenga
/// `repo-map/registry.json`, y de ahí sale el `CONTEXT.md` del repo en juego.
class ProjectContextDataSource {
  /// Dónde el repo declara qué reglas hay que cargarle.
  ///
  /// En la raíz del proyecto y con nombre visible —no dentro de una carpeta
  /// oculta— porque es una decisión del equipo que se revisa en un PR, no una
  /// preferencia de la máquina de cada uno.
  static const _archivoDeReglas = ReglasDeclaradas.archivo;
  const ProjectContextDataSource();

  /// Hasta dónde se sube buscando reglas. Sin tope se llegaría a `/`, y las
  /// reglas de la raíz del disco no son reglas de nadie.
  static const _maxLevels = 6;

  Future<({List<ContextFile> rules, ContextFile? sharedContext})> read(
    String workingDirectory,
  ) async {
    final rules = [
      ...await _rules(workingDirectory),
      // **Al final del todo, y por lo mismo que el `CLAUDE.md` del proyecto va
      // último**: lo último leído es lo que pesa, y estas son las reglas que el
      // repo declara para sí mismo.
      ...await _declaradas(workingDirectory),
    ];
    final shared = await _sharedContext(workingDirectory);
    return (rules: rules, sharedContext: shared);
  }

  /// Las reglas que **el propio repo declara** en `.nexus-reglas`.
  ///
  /// Existe porque un proyecto puede guardar sus reglas fuera de un `CLAUDE.md`
  /// —repartidas por capa, en un repo de contexto aparte— y entonces Nexus no las
  /// veía en absoluto: solo mira los `CLAUDE.md` del árbol y el `CONTEXT.md` del
  /// repo. Medido en un caso real: **33 archivos de reglas, 328 KB, y ninguno
  /// llegaba al modelo.** El trabajo salía sin la mitad de la ley del sitio.
  ///
  /// **Las elige una persona, no la app.** Ese es el punto de esta pieza, y no una
  /// limitación: 328 KB son dieciséis veces lo que cabe en un encargo, así que
  /// alguien tiene que decidir qué entra — y quien sabe qué regla aplica a lo que
  /// se va a tocar es quien escribe el encargo, no un heurístico sobre su texto.
  ///
  /// El archivo es una ruta por línea. Se admiten comentarios con `#`, rutas
  /// absolutas, `~` y rutas relativas al repo: las reglas suelen vivir en un repo
  /// hermano, así que exigirlas dentro sería no servir para el caso que motivó
  /// esto.
  Future<List<ContextFile>> _declaradas(String workingDirectory) async {
    final lista = File('$workingDirectory/$_archivoDeReglas');
    if (!lista.existsSync()) return const [];

    final home = Platform.environment['HOME'] ?? '';
    final found = <ContextFile>[];

    // **Solo las que van siempre.** Las de capa —las que llevan flecha— las carga el
    // gancho justo antes de cada edición, sabiendo qué archivo se toca. Antes esto se
    // tragaba la línea entera como si fuera una ruta, así que un proyecto con reglas por
    // capa metía «**/domain/** -> …» en cada encargo con un aviso de que no existía.
    for (final regla in ReglasDeclaradas.leer(await lista.readAsString())) {
      if (!regla.siempre) continue;
      final crudo = regla.ruta;

      final ruta = switch (crudo) {
        _ when crudo.startsWith('/') => crudo,
        _ when crudo.startsWith('~/') => '$home${crudo.substring(1)}',
        _ => '$workingDirectory/$crudo',
      };

      final file = File(ruta);
      if (!file.existsSync()) {
        // **Se dice y no se calla.** Una regla declarada que no existe es un
        // archivo que se movió o un nombre mal escrito, y el síntoma sin esto
        // sería trabajo que ignora una regla sin que nadie sepa por qué.
        found.add((
          path: ruta,
          content:
              '> Nexus no encontró esta regla declarada en '
              '`$_archivoDeReglas`: `$ruta`. Alguien la movió o la escribió mal.',
        ));
        continue;
      }
      final content = await file.readAsString();
      if (content.trim().isNotEmpty) found.add((path: ruta, content: content));
    }

    return found;
  }

  /// Los `CLAUDE.md` del árbol, **de la carpeta más lejana a la más cercana**.
  /// Ese orden es el que importa: el del proyecto va el último porque lo último
  /// leído es lo que pesa.
  Future<List<ContextFile>> _rules(String workingDirectory) async {
    final found = <ContextFile>[];
    var current = Directory(workingDirectory).absolute;
    final home = Platform.environment['HOME'] ?? '';

    for (var level = 0; level < _maxLevels; level++) {
      final file = File('${current.path}/CLAUDE.md');
      if (file.existsSync()) {
        // Se lee siguiendo el enlace si lo hay: `~/personal/CLAUDE.md` es un
        // symlink a las reglas transversales, y tratarlo como un archivo
        // cualquiera es justo lo que se espera.
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          found.add((path: file.path, content: content));
        }
      }
      final parent = current.parent;
      // Parar en el home y en la raíz: por encima ya no hay proyecto.
      if (parent.path == current.path) break;
      if (current.path == home) break;
      current = parent;
    }

    return found.reversed.toList();
  }

  /// El `CONTEXT.md` del repo en el que se está trabajando, si el workspace
  /// tiene un `ai-context` con su mapa.
  ///
  /// **Con dos candidatos no se adivina.** Cargar las reglas del repo
  /// equivocado es peor que no cargar ninguna: el agente trabajaría convencido
  /// de tener el contexto bueno.
  Future<ContextFile?> _sharedContext(String workingDirectory) async {
    final registry = _findRegistry(workingDirectory);
    if (registry == null) return null;

    final entries = _repositories(await registry.readAsString());
    if (entries.isEmpty) return null;

    // El campo `repo` casa con el **nombre de la carpeta**, no con el id: en el
    // mapa del trabajo, la carpeta `front-mobile-b2c` es el id `fe-b2c`.
    final workingName = Directory(
      workingDirectory,
    ).absolute.path.split('/').last;
    var id = entries.entries
        .where((entry) => entry.value == workingName)
        .map((entry) => entry.key)
        .firstOrNull;

    // Trabajando sobre la carpeta que contiene los repos —el caso del
    // workspace— solo se resuelve si dentro hay exactamente uno del mapa.
    if (id == null) {
      final inside = entries.entries
          .where(
            (entry) =>
                Directory('$workingDirectory/${entry.value}').existsSync(),
          )
          .toList();
      if (inside.length != 1) return null;
      id = inside.single.key;
    }

    final context = File(
      '${registry.parent.parent.path}/repositories/$id/CONTEXT.md',
    );
    if (!context.existsSync()) return null;
    final content = await context.readAsString();
    return content.trim().isEmpty
        ? null
        : (path: context.path, content: content);
  }

  /// La carpeta tiene que llamarse `ai-context` y traer el mapa. Una con ese
  /// nombre y sin mapa no cuenta — así lo dice el contrato, y así falla de
  /// forma predecible en vez de a medias.
  File? _findRegistry(String workingDirectory) {
    var current = Directory(workingDirectory).absolute;
    for (var level = 0; level < _maxLevels; level++) {
      final registry = File(
        '${current.path}/ai-context/repo-map/registry.json',
      );
      if (registry.existsSync()) return registry;
      final parent = current.parent;
      if (parent.path == current.path) break;
      current = parent;
    }
    return null;
  }

  /// id → nombre de carpeta. Un mapa ilegible no rompe el encargo: se sigue sin
  /// contexto compartido, que es lo que pasaba antes de que esto existiera.
  Map<String, String> _repositories(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const {};
      final repositories = decoded['repositories'];
      if (repositories is! Map<String, dynamic>) return const {};
      return {
        for (final entry in repositories.entries)
          if (entry.value case {'repo': final String folder}) entry.key: folder,
      };
    } on FormatException {
      return const {};
    }
  }
}
