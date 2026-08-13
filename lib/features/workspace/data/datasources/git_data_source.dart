import 'dart:io';

import 'package:flutter/foundation.dart';

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

  Future<String?> _run(String folderPath, List<String> arguments) async {
    try {
      final result = await Process.run('git', [
        '-C',
        folderPath,
        ...arguments,
      ], runInShell: false);
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
