import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:nexus/core/platform/herramienta_externa.dart';
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

  /// Hasta dónde se guarda el diff al archivar la conversación.
  ///
  /// **Con tope y no entero**: un encargo grande deja cientos de kilobytes de
  /// diff, y una conversación de diez encargos multiplicaría por diez el
  /// archivo que el historial lee para pintar su lista. Doscientos mil
  /// caracteres cubren de sobra un encargo normal; lo que pase de ahí se
  /// recorta y se dice, que es mejor que un historial que pesa como el repo.
  static const maxGuardado = 200000;

  Map<String, dynamic> toJson() => {
    // El recorte va por archivos enteros: cortar un diff a mitad de un tramo
    // produce algo que ya no es un diff y que el visor pintaría torcido.
    'diff': _recortado,
    if (newFiles.isNotEmpty) 'nuevos': newFiles,
    if (diff.length > maxGuardado) 'recortado': true,
  };

  String get _recortado {
    if (diff.length <= maxGuardado) return diff;
    final corte = diff.lastIndexOf('\ndiff --git ', maxGuardado);
    return corte == -1 ? '' : diff.substring(0, corte + 1);
  }

  static GitChanges? fromJson(Map<String, dynamic> json) {
    final diff = json['diff'] as String? ?? '';
    final nuevos = [
      for (final archivo in json['nuevos'] as List<dynamic>? ?? const [])
        if (archivo is String) archivo,
    ];
    if (diff.isEmpty && nuevos.isEmpty) return null;
    return GitChanges(diff: diff, newFiles: nuevos);
  }
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

  /// Si esa rama sigue existiendo en ese repositorio.
  ///
  /// Se usa para saber qué corridas quedaron huérfanas: una rama borrada deja su plan, su
  /// gate y su cierre anotados en la cuenta para siempre, y esa lista se ensucia sola.
  ///
  /// Se pregunta por la referencia local y no por `git branch`, que también lista las
  /// remotas según cómo esté configurado: lo que decide si la corrida sigue viva es que la
  /// rama esté **aquí**, que es donde se trabajaba.
  Future<bool> ramaExiste(String folderPath, String rama) async =>
      await _run(folderPath, [
        'rev-parse',
        '--verify',
        '--quiet',
        'refs/heads/$rama',
      ]) !=
      null;

  /// Una huella del árbol **completo y estable**, para poder decir si una corrida del
  /// gate sigue cubriendo lo que hay.
  ///
  /// Dos cosas la hacen distinta de [snapshot], y las dos salieron de una prueba:
  ///
  /// **No usa `git stash create`.** Ese comando fabrica un commit, y el hash de un commit
  /// lleva la hora dentro: con el árbol sucio, llamarlo dos veces da dos valores para el
  /// mismo código. Como base de un diff da igual —se toma una vez— pero como huella para
  /// comparar después es justo lo contrario de lo que hace falta: el verde caducaría solo,
  /// al segundo siguiente, sin que nadie hubiera tocado nada.
  ///
  /// **Incluye lo que git todavía no sigue.** Un archivo nuevo sin añadir no sale en
  /// ningún diff, y escribir archivos nuevos es justo lo que hace un asistente: sin esto,
  /// el verde cubría código que el gate no vio nunca.
  ///
  /// Así que se mezclan tres cosas deterministas: el commit de `HEAD`, el diff contra él
  /// —con `--binary`, para que un cambio en un asset también cuente— y el hash del
  /// contenido de cada archivo sin seguir.
  ///
  /// **El hook que frena el PR calcula esto mismo en Python** y no comparten código. La
  /// construcción está fijada al byte a propósito, y hay una prueba que corre los dos
  /// lados sobre el mismo repositorio: si se separan, el freno deniega para siempre sin
  /// explicar por qué.
  Future<String?> huellaDelArbol(String folderPath) async {
    final cabeza = await _run(folderPath, ['rev-parse', 'HEAD']);
    // Sin repositorio no hay nada que comparar, y decirlo con un nulo es lo que hace que
    // arriba no se afirme que un verde cubre algo.
    if (await _run(folderPath, ['rev-parse', '--show-toplevel']) == null) {
      return null;
    }

    final diff =
        await _run(folderPath, [
          'diff',
          'HEAD',
          '--binary',
          '--no-color',
          '--no-ext-diff',
        ]) ??
        '';

    final sinSeguir =
        (await _run(folderPath, [
                  'ls-files',
                  '--others',
                  '--exclude-standard',
                ]) ??
                '')
            .split('\n')
            .where((linea) => linea.isNotEmpty)
            .toList();

    final material = StringBuffer('${cabeza ?? ''}\n$diff');
    if (sinSeguir.isNotEmpty) {
      // Todos de una vez: un proceso por archivo en un repo con `build/` sin ignorar
      // costaría segundos en cada pulsación.
      final hashes = await _conEntrada(folderPath, [
        'hash-object',
        '--stdin-paths',
      ], '${sinSeguir.join('\n')}\n');
      final lista = (hashes ?? '').split('\n');
      for (var i = 0; i < sinSeguir.length; i++) {
        material.write('\n${sinSeguir[i]}:${i < lista.length ? lista[i] : ''}');
      }
    }

    return sha1.convert(utf8.encode(material.toString())).toString();
  }

  /// Un `git` al que hay que darle algo por la entrada.
  Future<String?> _conEntrada(
    String folderPath,
    List<String> arguments,
    String entrada,
  ) async {
    try {
      final proceso = await Process.start(
        await HerramientaExterna.rutaDeGit(),
        ['-C', folderPath, ...arguments],
        environment: ClaudeEnvironment.forTools(),
      );
      proceso.stdin.write(entrada);
      await proceso.stdin.close();
      final salida = await proceso.stdout.transform(utf8.decoder).join();
      // La salida se consume antes del código: al revés, un `git` que escriba más de lo
      // que cabe en el búfer se queda esperando y esto no vuelve nunca.
      final codigo = await proceso.exitCode;
      return codigo == 0 ? salida.trim() : null;
    } on ProcessException {
      return null;
    }
  }

  Future<String?> _run(String folderPath, List<String> arguments) async {
    try {
      final result = await Process.run(
        await HerramientaExterna.rutaDeGit(),
        ['-C', folderPath, ...arguments],
        runInShell: false,
        environment: ClaudeEnvironment.forTools(),
      );
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
