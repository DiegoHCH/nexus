import 'dart:io';

import 'package:nexus/core/platform/claude_environment.dart';
import 'package:nexus/features/superpowers/domain/entities/skill.dart';
import 'package:nexus/features/superpowers/domain/usecases/skill_source.dart';
import 'package:path_provider/path_provider.dart';

/// Las skills instaladas en una cuenta, y las que se pueden traer de un repo.
///
/// **Van en la cuenta y no en el proyecto**, y esa es la diferencia con lo que
/// Nexus ya sabía hacer: 3.3 le pide a Claude que escriba una skill en el
/// `.claude/skills/` del repo, y ahí solo existe para ese repo. Instalada en el
/// `CLAUDE_CONFIG_DIR` de la cuenta, la carga cualquier sesión sin que nadie se
/// la pida.
class SkillsDataSource {
  const SkillsDataSource();

  Directory _dir(String configDir) => Directory('$configDir/skills');

  Future<List<Skill>> installed(String configDir) async {
    final dir = _dir(configDir);
    if (!dir.existsSync()) return const [];

    final skills = <Skill>[];
    for (final entry in dir.listSync()) {
      if (entry is! Directory) continue;
      final file = File('${entry.path}/SKILL.md');
      if (!file.existsSync()) continue;
      skills.add(
        Skill(
          id: entry.path.split('/').last,
          description: SkillSource.descriptionOf(await file.readAsString()),
        ),
      );
    }
    skills.sort((a, b) => a.id.compareTo(b.id));
    return skills;
  }

  /// Lo que trae un repo: toda carpeta con un `SKILL.md` dentro.
  ///
  /// Se busca por el archivo y no por una ruta fija porque cada repo se
  /// organiza a su manera — el oficial las tiene bajo `skills/`, y un repo de
  /// equipo puede tenerlas en la raíz.
  Future<({List<Skill> skills, String? error})> scan(String repoRaw) async {
    final repo = SkillSource.normalizeRepo(repoRaw);
    if (repo == null) {
      return (
        skills: const <Skill>[],
        error: 'Eso no parece un repo de GitHub',
      );
    }

    final cache = await _fetch(repo);
    if (cache == null) {
      return (skills: const <Skill>[], error: 'No se pudo traer $repo');
    }

    return (skills: await skillsIn(cache), error: null);
  }

  /// Las skills que hay dentro de una carpeta ya traída.
  ///
  /// Público **para poder probar el recorrido sin clonar nada**, que es justo la
  /// parte que fallaba: dónde busca y dónde no. Las tres formas que se le
  /// escapaban —una skill bajo `.github`, otra a cinco niveles de fondo, y un
  /// repo con cientos— se comprueban con carpetas de mentira en vez de contra la
  /// red, que sería lento y además dependería de que esos repos no cambien.
  Future<List<Skill>> skillsIn(Directory dir) async {
    final found = <Skill>[];
    await _walk(dir, 0, found);
    found.sort((a, b) => a.id.compareTo(b.id));
    return found;
  }

  /// Copia la carpeta de la skill al perfil. Reemplaza si ya estaba: eso es
  /// «actualizar», y es lo que uno espera al pulsar de nuevo.
  Future<String?> install(
    String configDir, {
    required String repoRaw,
    required String id,
  }) async {
    if (!SkillSource.validId(id)) return 'Identificador inválido';
    final repo = SkillSource.normalizeRepo(repoRaw);
    if (repo == null) return 'Repo inválido';

    final cache = await _fetch(repo);
    if (cache == null) return 'No se pudo traer $repo';

    final source = await _find(cache, id, 0);
    if (source == null) return 'La skill «$id» no está en $repo';

    try {
      final target = Directory('${_dir(configDir).path}/$id');
      if (target.existsSync()) target.deleteSync(recursive: true);
      await _copy(source, target);
      return null;
    } on FileSystemException catch (error) {
      return error.message;
    }
  }

  /// Crea el esqueleto y devuelve su ruta, para poder abrirlo.
  Future<({String? path, String? error})> create(
    String configDir, {
    required String name,
    required String description,
  }) async {
    final id = SkillSource.idFrom(name);
    if (id == null) return (path: null, error: 'Nombre inválido');

    final file = File('${_dir(configDir).path}/$id/SKILL.md');
    if (file.existsSync()) return (path: null, error: 'Ya existe «$id»');
    try {
      await file.create(recursive: true);
      await file.writeAsString(SkillSource.skeleton(id, description));
      return (path: file.path, error: null);
    } on FileSystemException catch (error) {
      return (path: null, error: error.message);
    }
  }

  Future<String?> remove(String configDir, String id) async {
    if (!SkillSource.validId(id)) return 'Identificador inválido';
    try {
      final dir = Directory('${_dir(configDir).path}/$id');
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      return null;
    } on FileSystemException catch (error) {
      return error.message;
    }
  }

  /// Clon superficial en caché, o `pull` si ya estaba.
  ///
  /// Superficial porque de un repo de skills solo interesa cómo está **hoy**:
  /// el oficial con historia entera son decenas de megas para copiar una
  /// carpeta de texto.
  Future<Directory?> _fetch(String repo) async {
    final support = await getApplicationSupportDirectory();
    final cache = Directory(
      '${support.path}/skills-cache/${repo.replaceAll('/', '__')}',
    );

    try {
      if (Directory('${cache.path}/.git').existsSync()) {
        final pull = await Process.run('git', [
          '-C',
          cache.path,
          'pull',
          '--ff-only',
        ], environment: ClaudeEnvironment.forTools());
        // Si el `pull` falla —sin red, o el repo cambió de historia— se usa lo
        // que ya había: una copia de ayer sirve, quedarse sin lista no.
        if (pull.exitCode != 0 && !cache.existsSync()) return null;
        return cache;
      }
      cache.parent.createSync(recursive: true);
      final clone = await Process.run('git', [
        'clone',
        '--depth',
        '1',
        'https://github.com/$repo.git',
        cache.path,
      ], environment: ClaudeEnvironment.forTools());
      return clone.exitCode == 0 ? cache : null;
    } on ProcessException {
      return null;
    }
  }

  /// Hasta dónde se baja buscando, y cuántas se recogen como mucho.
  ///
  /// Seis niveles y no cuatro porque los repos grandes anidan: en
  /// `davila7/claude-code-templates` las skills viven en
  /// `cli-tool/components/skills/<familia>/<skill>/`, y con cuatro se perdían
  /// 22 de las suyas. El tope existe para no recorrer un monorepo entero, no
  /// para recortar la lista: **ese repo tiene 896 skills** y con el anterior
  /// —100— la que buscabas era la número 228 y no aparecía nunca.
  static const _maxDepth = 6;
  static const _maxSkills = 1000;

  /// Lo que no se mira nunca.
  ///
  /// **Solo estas dos, y no toda carpeta que empiece por punto**, que era lo que
  /// hacía antes. `.github/skills/` y `.claude-plugin/skills/` son sitios
  /// legítimos y cada vez más comunes —los usa GitHub en `github/spec-kit`, con
  /// su única skill ahí dentro— así que saltarlos dejaba repos enteros
  /// aparentemente vacíos.
  static const _nuncaMirar = {'.git', 'node_modules'};

  Future<void> _walk(Directory dir, int depth, List<Skill> found) async {
    if (depth > _maxDepth || found.length >= _maxSkills) return;
    for (final entry in dir.listSync()) {
      if (entry is! Directory) continue;
      final name = entry.path.split('/').last;
      if (_nuncaMirar.contains(name)) continue;

      final file = File('${entry.path}/SKILL.md');
      if (file.existsSync()) {
        found.add(
          Skill(
            id: name,
            description: SkillSource.descriptionOf(await file.readAsString()),
          ),
        );
      } else {
        await _walk(entry, depth + 1, found);
      }
    }
  }

  Future<Directory?> _find(Directory dir, String id, int depth) async {
    if (depth > _maxDepth) return null;
    for (final entry in dir.listSync()) {
      if (entry is! Directory) continue;
      final name = entry.path.split('/').last;
      if (_nuncaMirar.contains(name)) continue;
      if (name == id && File('${entry.path}/SKILL.md').existsSync()) {
        return entry;
      }
      final hit = await _find(entry, id, depth + 1);
      if (hit != null) return hit;
    }
    return null;
  }

  Future<void> _copy(Directory source, Directory target) async {
    target.createSync(recursive: true);
    for (final entry in source.listSync(recursive: true)) {
      final relative = entry.path.substring(source.path.length + 1);
      if (entry is Directory) {
        Directory('${target.path}/$relative').createSync(recursive: true);
      } else if (entry is File) {
        final destination = File('${target.path}/$relative');
        destination.parent.createSync(recursive: true);
        await entry.copy(destination.path);
      }
    }
  }
}
