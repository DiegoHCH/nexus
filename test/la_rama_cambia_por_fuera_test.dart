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

  /// 🔴 **Y una rama creada desde la app también se ve**, que es la otra mitad
  /// de la pregunta.
  ///
  /// Aquí el checkout lo hace quien trabaja dentro —Claude, cuando le pides una
  /// rama— y no hay diferencia: el vigía está sobre el archivo y no le importa
  /// quién lo escribió. Que sea el mismo mecanismo es justo la gracia, porque
  /// el camino que existía para este caso **estaba roto en una forma**: al
  /// terminar el encargo se invalidaba la rama de la carpeta emparejada, y el
  /// chip lee la de donde Claude trabaja de verdad. Con una raíz de varios
  /// repos esas dos no son la misma, así que se refrescaba una clave que nadie
  /// miraba.
  ///
  /// Por eso la prueba tiene la forma del caso que fallaba: el repo **dentro**
  /// de una raíz, que es donde las dos rutas se separan.
  test(
    'una rama creada desde dentro también, y en un repo de una raíz',
    () async {
      final raiz = Directory.systemTemp.createTempSync('nexus_raiz');
      addTearDown(() => raiz.deleteSync(recursive: true));
      final dentro = Directory('${raiz.path}/front-mobile-b2c')..createSync();
      await run(['init', '-q', '-b', 'main'], donde: dentro);
      await run(['config', 'user.email', 'prueba@nexus'], donde: dentro);
      await run(['config', 'user.name', 'Prueba'], donde: dentro);
      File('${dentro.path}/lib.dart').writeAsStringSync('uno\n');
      await run(['add', '.'], donde: dentro);
      await run(['commit', '-qm', 'inicio'], donde: dentro);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final info = await container.read(gitInfoProvider(dentro.path).future);
      expect(info?.branch, 'main');
      expect(
        info?.repository,
        'front-mobile-b2c',
        reason: 'la rama que se enseña es la del repo, no la de la raíz',
      );
      final sub = container.listen(gitInfoProvider(dentro.path), (_, _) {});
      addTearDown(sub.close);

      // Lo que hace Claude cuando le pides una rama nueva.
      await run(['checkout', '-q', '-b', 'feat/la-rama-nueva'], donde: dentro);

      final plazo = DateTime.now().add(const Duration(seconds: 10));
      String? rama;
      while (DateTime.now().isBefore(plazo)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        rama = (await container.read(
          gitInfoProvider(dentro.path).future,
        ))?.branch;
        if (rama == 'feat/la-rama-nueva') break;
      }

      expect(rama, 'feat/la-rama-nueva');
    },
  );

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

  // 🔴 **Y el segundo checkout también.** Aquí estaba el fallo que quedaba: el
  // vigía emitía `void`, así que cada aviso dejaba el proveedor en el mismo
  // `AsyncData(null)` de antes. Riverpod compara el estado nuevo con el viejo y
  // **son iguales**, así que no notifica: el primer cambio se veía —porque venía
  // de `AsyncLoading`— y del segundo en adelante, nada.
  //
  // Se reportó así: checkout en Android Studio, el chip sin moverse, y solo al
  // preguntarle a Claude «¿en qué rama estoy?» aparecía la nueva — porque eso
  // termina un turno, y al terminar un turno la rama se relee por otro camino.
  test(
    'y el segundo checkout también, que es donde se quedaba clavado',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        (await container.read(gitInfoProvider(repo.path).future))?.branch,
        'main',
      );
      final sub = container.listen(gitInfoProvider(repo.path), (_, _) {});
      addTearDown(sub.close);

      Future<String?> esperarLaRama(String cual) async {
        final plazo = DateTime.now().add(const Duration(seconds: 10));
        String? rama;
        while (DateTime.now().isBefore(plazo)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          rama = (await container.read(
            gitInfoProvider(repo.path).future,
          ))?.branch;
          if (rama == cual) break;
        }
        return rama;
      }

      await run(['checkout', '-q', '-b', 'la-primera']);
      expect(await esperarLaRama('la-primera'), 'la-primera');

      await run(['checkout', '-q', '-b', 'la-segunda']);
      expect(
        await esperarLaRama('la-segunda'),
        'la-segunda',
        reason:
            'el primero se veía porque el vigía pasaba de «cargando» a «listo»; '
            'del segundo en adelante el estado no cambiaba y nadie se enteraba',
      );
    },
  );
}
