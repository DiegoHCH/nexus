import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/workspace/data/datasources/git_data_source.dart';

/// Con un repositorio de verdad, no con uno fingido: lo que se prueba aquí es
/// justamente cómo se comporta git, y un doble solo confirmaría lo que creo
/// que hace.
void main() {
  late Directory repo;
  const git = GitDataSource();

  Future<void> run(List<String> args) async {
    final result = await Process.run('git', args, workingDirectory: repo.path);
    if (result.exitCode != 0) {
      throw StateError('git ${args.join(' ')} → ${result.stderr}');
    }
  }

  void write(String name, String content) =>
      File('${repo.path}/$name').writeAsStringSync(content);

  setUp(() async {
    repo = Directory.systemTemp.createTempSync('nexus_git');
    await run(['init', '-q']);
    await run(['config', 'user.email', 'prueba@nexus']);
    await run(['config', 'user.name', 'Prueba']);
    write('lib.dart', 'uno\n');
    await run(['add', '.']);
    await run(['commit', '-qm', 'inicio']);
  });

  tearDown(() => repo.deleteSync(recursive: true));

  test('sin tocar nada, no hay cambios que enseñar', () async {
    final base = await git.snapshot(repo.path);
    expect(await git.changesSince(repo.path, base!), isNull);
  });

  test('lo editado durante la tarea sale en el diff', () async {
    final base = await git.snapshot(repo.path);
    write('lib.dart', 'uno\ndos\n');

    final cambios = await git.changesSince(repo.path, base!);

    expect(cambios!.diff, contains('lib.dart'));
    expect(cambios.diff, contains('+dos'));
    expect(cambios.fileCount, 1);
  });

  // Un diff normal no los enseña —para git todavía no existen— y sin esto un
  // encargo que solo crea archivos parecería no haber hecho nada.
  test('los archivos nuevos se listan aparte', () async {
    final base = await git.snapshot(repo.path);
    write('nuevo.dart', 'hola\n');

    final cambios = await git.changesSince(repo.path, base!);

    expect(cambios!.newFiles, ['nuevo.dart']);
    expect(cambios.fileCount, 1);
  });

  // Lo que se pidió: el diff **de esa tarea**, no la suma de la conversación.
  // Con `git diff HEAD` a secas, el segundo encargo enseñaría también lo del
  // primero.
  test('el diff es el de esta tarea, no el acumulado', () async {
    // Primera tarea: toca un archivo y se queda sin commitear, como pasa de
    // verdad cuando Claude edita.
    write('lib.dart', 'uno\nprimera\n');

    // Segunda tarea: se marca el estado *ya con lo anterior dentro*.
    final base = await git.snapshot(repo.path);
    write('otro.dart', 'segunda\n');

    final cambios = await git.changesSince(repo.path, base!);

    expect(cambios!.newFiles, ['otro.dart']);
    expect(cambios.diff, isNot(contains('primera')));
  });

  test('una carpeta que no es un repositorio no inventa cambios', () async {
    final suelta = Directory.systemTemp.createTempSync('nexus_sin_git');
    addTearDown(() => suelta.deleteSync(recursive: true));

    expect(await git.snapshot(suelta.path), isNull);
    expect(await git.read(suelta.path), isNull);
  });
}
