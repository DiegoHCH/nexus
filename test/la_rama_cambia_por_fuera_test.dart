import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/workspace/data/datasources/git_data_source.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

/// La rama que enseña la app cuando la cambias **por fuera**.
///
/// 🔴 Nace de un caso medido: se cambió de rama en el editor y el chip siguió
/// diciendo `main`. Solo cerrando Nexus y volviendo a abrirlo se enteró. La
/// rama se releía al terminar cada turno —lo que cubre el checkout que hace
/// Claude— pero cambiando de rama a mano no termina ningún turno, así que el
/// dato se quedaba viejo para siempre.
///
/// Con un repositorio de verdad, por lo mismo que el resto de las pruebas de
/// git en este repo: lo que se prueba es cómo se comporta git —dónde vive el
/// `HEAD`, qué toca al hacer checkout— y un doble solo confirmaría lo que creo
/// que hace.
void main() {
  late Directory repo;
  const git = GitDataSource();

  Future<void> run(List<String> args, {Directory? donde}) async {
    final result = await Process.run(
      'git',
      args,
      workingDirectory: (donde ?? repo).path,
    );
    if (result.exitCode != 0) {
      throw StateError('git ${args.join(' ')} → ${result.stderr}');
    }
  }

  setUp(() async {
    repo = Directory.systemTemp.createTempSync('nexus_rama');
    await run(['init', '-q', '-b', 'main']);
    await run(['config', 'user.email', 'prueba@nexus']);
    await run(['config', 'user.name', 'Prueba']);
    File('${repo.path}/lib.dart').writeAsStringSync('uno\n');
    await run(['add', '.']);
    await run(['commit', '-qm', 'inicio']);
  });

  tearDown(() => repo.deleteSync(recursive: true));

  group('dónde vive el HEAD que hay que vigilar', () {
    test('en un repo normal, dentro de su .git', () async {
      final head = await git.dondeViveElHead(repo.path);
      expect(head, isNotNull);
      expect(head!.path, '${repo.resolveSymbolicLinksSync()}/.git/HEAD');
      expect(head.existsSync(), isTrue);
    });

    // 🔴 El caso que rompe componer la ruta a mano. En un worktree `.git` es un
    // **archivo** que apunta a otro sitio, así que `<carpeta>/.git/HEAD` no
    // existe — y el `HEAD` que cambia al hacer checkout es el de allí.
    test('en un worktree, en el suyo y no en el del repo padre', () async {
      final fuera = Directory.systemTemp.createTempSync('nexus_wt');
      addTearDown(() => fuera.deleteSync(recursive: true));
      final wt = '${fuera.path}/rama';
      await run(['worktree', 'add', '-q', '-b', 'otra', wt]);
      addTearDown(() => run(['worktree', 'remove', '--force', wt]));

      expect(
        File('$wt/.git').statSync().type,
        FileSystemEntityType.file,
        reason: 'si esto fuera una carpeta, el caso no probaría nada',
      );

      final head = await git.dondeViveElHead(wt);
      expect(head, isNotNull);
      expect(head!.existsSync(), isTrue);
      expect(
        head.path,
        contains('worktrees'),
        reason: 'el HEAD de un worktree no es el del repo padre',
      );
    });

    test('fuera de un repositorio no hay nada que vigilar', () async {
      final suelta = Directory.systemTemp.createTempSync('nexus_sin_git');
      addTearDown(() => suelta.deleteSync(recursive: true));
      expect(await git.dondeViveElHead(suelta.path), isNull);
    });
  });

  // 🔴 La prueba del caso entero: nadie le pide nada a la app, se cambia de
  // rama desde fuera, y el dato que enseña el chip cambia solo.
  test('un checkout por fuera se nota sin reiniciar nada', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // La primera lectura, que es la que se quedaba clavada.
    expect(
      (await container.read(gitInfoProvider(repo.path).future))?.branch,
      'main',
    );
    // Y se mantiene escuchando, que es lo que hace que el vigía exista: sin
    // nadie mirando, el proveedor se desecha y con él el vigilante.
    final sub = container.listen(gitInfoProvider(repo.path), (_, _) {});
    addTearDown(sub.close);

    await run(['checkout', '-q', '-b', 'front-mobile-b2c']);

    // El vigía deja pasar la ráfaga del checkout antes de avisar, así que se
    // le da margen de sobra sin quedarse esperando para siempre si no llega.
    final plazo = DateTime.now().add(const Duration(seconds: 10));
    String? rama;
    while (DateTime.now().isBefore(plazo)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      rama = (await container.read(gitInfoProvider(repo.path).future))?.branch;
      if (rama == 'front-mobile-b2c') break;
    }

    expect(
      rama,
      'front-mobile-b2c',
      reason:
          'cambiar de rama en el editor no termina ningún turno, así que sin '
          'vigilar el HEAD el chip se queda con la rama vieja hasta reiniciar',
    );
  });
}
