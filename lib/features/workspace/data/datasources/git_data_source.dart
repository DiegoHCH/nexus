import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nexus/core/platform/claude_environment.dart';

/// En qué repositorio y en qué rama está una carpeta.
@immutable
class GitInfo {
  const GitInfo({required this.repository, required this.branch});

  /// El nombre del repositorio —la carpeta raíz del `.git`—, que no siempre es
  /// la carpeta emparejada: se puede trabajar sobre un subdirectorio.
  final String repository;

  /// La rama, o el commit corto con `HEAD` suelta. `null` mientras no se sabe.
  final String? branch;
}

/// Lo que una tarea dejó tocado.
@immutable
class GitChanges {
  const GitChanges({required this.diff, required this.newFiles});

  /// El `git diff` en crudo de lo que git ya seguía.
  final String diff;

  /// Los archivos que antes no existían. Van aparte porque **un diff no los
  /// enseña**: para git todavía no existen, y sin esto un encargo que solo crea
  /// archivos parecería no haber hecho nada.
  final List<String> newFiles;

  /// Cuántos archivos tocó, para poder decirlo sin abrir nada.
  int get fileCount =>
      RegExp(r'^diff --git ', multiLine: true).allMatches(diff).length +
      newFiles.length;
}

/// Pregunta a git, que es quien sabe.
///
/// Se lee de aquí y no de los archivos de `.git` a mano porque el caso raro
/// —`HEAD` suelta, un worktree, un submódulo— lo resuelve git y no un parser
/// nuestro.
class GitDataSource {
  const GitDataSource();

  /// `null` si esa carpeta no está en un repositorio.
  ///
  /// Eso no es un error: significa que **lo que Claude escriba ahí no se puede
  /// deshacer**, y por eso la interfaz lo dice en vez de callarse.
  Future<GitInfo?> read(String folderPath) async {
    final root = await _run(folderPath, ['rev-parse', '--show-toplevel']);
    if (root == null || root.isEmpty) return null;

    final branch = await _run(folderPath, [
      'rev-parse',
      '--abbrev-ref',
      'HEAD',
    ]);
    // Con `HEAD` suelta —un checkout a un commit o a una etiqueta— git contesta
    // literalmente «HEAD», que no dice nada. Ahí vale más el commit corto.
    final detached = branch == null || branch.isEmpty || branch == 'HEAD';
    return GitInfo(
      repository: root.split('/').last,
      branch: detached
          ? await _run(folderPath, ['rev-parse', '--short', 'HEAD'])
          : branch,
    );
  }

  /// Los repositorios que hay **dentro** de una carpeta, un nivel abajo.
  ///
  /// Es el caso del workspace: una carpeta raíz con varios repos dentro. Sin
  /// esto, Claude trabaja sobre la raíz y cualquier cosa de git —la rama, un
  /// commit— se hace en el sitio equivocado o directamente no se puede hacer.
  ///
  /// Un nivel y no en profundidad: bajar recursivamente por un workspace grande
  /// cuesta segundos y encuentra los repos de `node_modules`, que no son
  /// proyectos de nadie.
  Future<List<String>> reposInside(String folderPath) async {
    final directory = Directory(folderPath);
    if (!directory.existsSync()) return const [];

    final repos = <String>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = entity.path.split('/').last;
      if (name.startsWith('.')) continue;
      if (Directory('${entity.path}/.git').existsSync() ||
          File('${entity.path}/.git').existsSync()) {
        repos.add(entity.path);
      }
    }
    repos.sort();
    return repos;
  }

  /// Una marca del estado actual del repo, para poder comparar **después**.
  ///
  /// `git stash create` fabrica un commit con lo que hay sin tocar el árbol —no
  /// mueve nada, no guarda nada en la pila— y si no hay cambios devuelve vacío
  /// y vale `HEAD`. Es lo que permite que el diff sea **el de esta tarea** y no
  /// la suma de todo lo que llevas hecho: con `git diff HEAD` a secas, el
  /// segundo encargo enseñaría también lo del primero.
  Future<String?> snapshot(String folderPath) async {
    final stash = await _run(folderPath, ['stash', 'create']);
    if (stash != null && stash.isNotEmpty) return stash;
    return _run(folderPath, ['rev-parse', 'HEAD']);
  }

  /// Lo que cambió desde esa marca: el diff de lo ya seguido por git, y los
  /// archivos nuevos, que no salen en un diff normal.
  Future<GitChanges?> changesSince(String folderPath, String base) async {
    final diff = await _run(folderPath, ['diff', base]) ?? '';
    final untracked =
        await _run(folderPath, [
          'ls-files',
          '--others',
          '--exclude-standard',
        ]) ??
        '';
    final nuevos = untracked
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    if (diff.isEmpty && nuevos.isEmpty) return null;
    return GitChanges(diff: diff, newFiles: nuevos);
  }

  Future<String?> _run(String folderPath, List<String> arguments) async {
    try {
      final result = await Process.run('git', [
        '-C',
        folderPath,
        ...arguments,
      ], runInShell: false, environment: ClaudeEnvironment.forTools());
      if (result.exitCode != 0) return null;
      final output = (result.stdout as String).trim();
      return output.isEmpty ? null : output;
    } on ProcessException {
      // Sin git instalado no se rompe nada: simplemente no hay repositorio que
      // enseñar.
      return null;
    }
  }
}
