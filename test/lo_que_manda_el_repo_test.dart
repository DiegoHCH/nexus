import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/workspace/data/datasources/repo_config_data_source.dart';
import 'package:nexus/features/workspace/domain/entities/config_del_repo.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/domain/entities/workspace.dart';
import 'package:nexus/features/workspace/domain/repositories/workspace_store.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

/// El `.nexus/` versionado: lo que un repositorio declara sobre sí mismo.
///
/// Casi todo este archivo prueba **una sola frase**: que un archivo que viaja
/// dentro de un repositorio solo puede apretar. Clonar no puede ser un permiso,
/// y esa no es una propiedad que se lea en el código de un vistazo — se lee
/// mirando cada rama de la regla, que es lo que hay aquí.

class _StoreDeMentira implements WorkspaceStore {
  _StoreDeMentira(this.workspace);

  Workspace workspace;

  @override
  Future<Workspace> read() async => workspace;

  @override
  Future<void> save(Workspace next) async => workspace = next;
}

void main() {
  group('el archivo, cuando está bien escrito', () {
    test('lo que declara se lee tal cual', () {
      final config = ConfigDelRepo.deTexto('''
        {
          "soloTexto": true,
          "soloLectura": true,
          "comandosVetados": ["build_runner", "  pod install  "],
          "carpetaDePruebas": "flows",
          "modelo": "opus",
          "esfuerzo": "high"
        }
      ''')!;

      expect(config.soloTexto, isTrue);
      expect(config.soloLectura, isTrue);
      expect(config.comandosVetados, ['build_runner', 'pod install']);
      expect(config.carpetaDePruebas, 'flows');
      expect(config.modelo, 'opus');
      expect(config.esfuerzo, 'high');
      expect(config.avisos, isEmpty);
      expect(config.declaraAlgo, isTrue);
    });

    test('uno vacío no es lo mismo que uno que no está', () {
      // `null` = no hay archivo. `{}` = hay archivo y no pide nada, que es lo
      // que deja alguien preparando el sitio antes de escribir las reglas.
      expect(ConfigDelRepo.deTexto(null), isNull);
      expect(ConfigDelRepo.deTexto('   '), isNull);

      final vacio = ConfigDelRepo.deTexto('{}')!;
      expect(vacio.declaraAlgo, isFalse);
      expect(vacio.avisos, isEmpty);
    });
  });

  group('el archivo, cuando está mal escrito', () {
    // Se avisa y no se aplica. Las dos mitades importan: aplicarlo sería
    // adivinar, y callarlo dejaría a quien lo revisa en el PR sin saber que su
    // línea no hace nada.
    test('una llave que no existe se avisa y no concede nada', () {
      final config = ConfigDelRepo.deTexto('{"permitirVoz": true}')!;

      expect(config.declaraAlgo, isFalse);
      expect(config.avisos.single, contains('permitirVoz'));
    });

    test('un tipo que no cuadra se avisa y no se aplica', () {
      final config = ConfigDelRepo.deTexto('''
        {"soloTexto": "sí", "comandosVetados": "build_runner", "modelo": 4}
      ''')!;

      expect(config.soloTexto, isFalse);
      expect(config.comandosVetados, isEmpty);
      expect(config.modelo, isNull);
      expect(config.avisos, hasLength(3));
    });

    test('lo que no es JSON se avisa entero, no revienta', () {
      final roto = ConfigDelRepo.deTexto('{ esto no es json')!;
      expect(roto.declaraAlgo, isFalse);
      expect(roto.avisos.single, contains('JSON'));

      final lista = ConfigDelRepo.deTexto('["build_runner"]')!;
      expect(lista.declaraAlgo, isFalse);
      expect(lista.avisos.single, contains('objeto'));
    });
  });

  group('la regla: el repositorio solo puede apretar', () {
    final tuya = const PairedFolder(
      path: '/repo',
      modality: FolderModality.voice,
      claudeProfile: '/Users/yo/.claude-trabajo',
      claudeModel: 'sonnet',
      blockedCommands: ['make generate'],
      carpetaDePruebas: 'mis-flows',
    );

    test('puede apagar la voz', () {
      final apretada = const ConfigDelRepo(soloTexto: true).aplicarA(tuya);
      expect(apretada.modality, FolderModality.textOnly);
    });

    test('no puede encenderla, y no hay forma de pedirlo', () {
      final callada = const PairedFolder(
        path: '/repo',
        modality: FolderModality.textOnly,
      );

      // Ni declarándolo, ni con la llave que uno esperaría que existiera.
      for (final texto in [
        '{}',
        '{"soloTexto": false}',
        '{"modalidad": "voz"}',
        '{"permitirVoz": true}',
        '{"soloTexto": true}',
      ]) {
        final config = ConfigDelRepo.deTexto(texto)!;
        expect(
          config.aplicarA(callada).modality,
          FolderModality.textOnly,
          reason: 'con «$texto» la carpeta se abrió a la voz',
        );
      }
    });

    test('suma comandos vetados y no quita ninguno', () {
      final apretada = const ConfigDelRepo(
        comandosVetados: ['build_runner', 'make generate'],
      ).aplicarA(tuya);

      // Los tuyos primero, el suyo detrás, y el repetido una sola vez.
      expect(apretada.blockedCommands, ['make generate', 'build_runner']);
    });

    test('la carpeta de pruebas del repo gana a la tuya', () {
      // No es un permiso: solo dice dónde mirar, y dónde están las pruebas de
      // un repositorio es un hecho suyo y no una preferencia tuya.
      final apretada = const ConfigDelRepo(
        carpetaDePruebas: 'flows',
      ).aplicarA(tuya);
      expect(apretada.carpetaDePruebas, 'flows');
    });

    test('el modelo lo propone, pero tu elección gana', () {
      final config = const ConfigDelRepo(modelo: 'opus', esfuerzo: 'high');

      // Tú elegiste sonnet: se respeta, porque el cupo que se gasta es el tuyo.
      expect(config.aplicarA(tuya).claudeModel, 'sonnet');
      // Y el esfuerzo, que no elegiste, lo pone el repo.
      expect(config.aplicarA(tuya).claudeEffort, 'high');
    });

    test('la cuenta de Claude no se lee del repositorio', () {
      // Es una ruta del disco de una persona: versionarla le rompería el
      // arranque a todos los demás.
      final apretada = const ConfigDelRepo(soloTexto: true).aplicarA(tuya);
      expect(apretada.claudeProfile, '/Users/yo/.claude-trabajo');

      final config = ConfigDelRepo.deTexto(
        '{"claudeProfile": "/Users/otro/.claude"}',
      )!;
      expect(config.avisos.single, contains('claudeProfile'));
      expect(config.aplicarA(tuya).claudeProfile, '/Users/yo/.claude-trabajo');
    });

    // El de forma, que es el que sobrevive a que alguien añada una rama nueva:
    // en cuanto la regla mencione `FolderModality.voice` habrá un camino por el
    // que un repositorio ajeno enciende el micrófono.
    test('la regla no nombra la voz en ninguna rama', () {
      final fuente = File(
        'lib/features/workspace/domain/entities/config_del_repo.dart',
      ).readAsStringSync();
      final regla = fuente.substring(fuente.indexOf('PairedFolder aplicarA'));

      expect(
        regla,
        isNot(contains('FolderModality.voice')),
        reason:
            'el único FolderModality que puede salir de aquí es textOnly; si '
            'aparece el otro, clonar un repositorio abre el micrófono',
      );
    });
  });

  group('el lector del disco', () {
    late Directory repo;

    setUp(() => repo = Directory.systemTemp.createTempSync('nexus-config'));
    tearDown(() => repo.deleteSync(recursive: true));

    void escribir(String contenido) {
      File('${repo.path}/${ConfigDelRepo.archivo}')
        ..createSync(recursive: true)
        ..writeAsStringSync(contenido);
    }

    test('sin archivo no declara nada', () async {
      expect(await RepoConfigDataSource().leer(repo.path), isNull);
    });

    test('lo que hay en el disco es lo que se aplica', () async {
      escribir('{"soloLectura": true}');
      final config = await RepoConfigDataSource().leer(repo.path);
      expect(config?.soloLectura, isTrue);
    });

    test('un archivo que cambia se vuelve a leer', () async {
      final lector = RepoConfigDataSource();
      escribir('{"soloTexto": true}');
      expect((await lector.leer(repo.path))?.soloTexto, isTrue);

      // La caché va por fecha y tamaño, así que el contenido nuevo tiene que
      // ser de otro tamaño o llevar otra fecha para que esto pruebe algo.
      final archivo = File('${repo.path}/${ConfigDelRepo.archivo}');
      archivo.writeAsStringSync('{"soloTexto": false, "modelo": "opus"}');
      archivo.setLastModifiedSync(
        DateTime.now().add(const Duration(seconds: 2)),
      );

      final segunda = await lector.leer(repo.path);
      expect(segunda?.soloTexto, isFalse);
      expect(segunda?.modelo, 'opus');
    });

    test('un directorio con ese nombre no es un archivo', () async {
      Directory(
        '${repo.path}/${ConfigDelRepo.archivo}',
      ).createSync(recursive: true);
      expect(await RepoConfigDataSource().leer(repo.path), isNull);
    });
  });

  group('lo que se enseña y lo que se guarda', () {
    late Directory repo;

    setUp(() => repo = Directory.systemTemp.createTempSync('nexus-workspace'));
    tearDown(() => repo.deleteSync(recursive: true));

    /// Un contenedor con el workspace ya cargado del store de mentira.
    Future<(ProviderContainer, _StoreDeMentira)> arrancar(
      Workspace inicial,
    ) async {
      final store = _StoreDeMentira(inicial);
      final container = ProviderContainer(
        overrides: [workspaceStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      container.read(workspaceControllerProvider);
      await container.read(workspaceControllerProvider.notifier).recargar();
      // Dos vueltas: la primera carga del store, la segunda lee el `.nexus/`.
      await Future<void>.delayed(Duration.zero);
      await container.read(workspaceControllerProvider.notifier).recargar();
      return (container, store);
    }

    test(
      'el repositorio aprieta lo que ves, y no toca lo que guardaste',
      () async {
        File('${repo.path}/${ConfigDelRepo.archivo}')
          ..createSync(recursive: true)
          ..writeAsStringSync('{"soloTexto": true, "soloLectura": true}');

        final (container, store) = await arrancar(
          Workspace(
            folders: [
              PairedFolder(path: repo.path, modality: FolderModality.voice),
            ],
            activePath: repo.path,
            permission: FilePermission.canEdit,
          ),
        );

        final visto = container.read(workspaceControllerProvider);
        expect(visto.folders.single.modality, FolderModality.textOnly);
        expect(visto.permission, FilePermission.readOnly);
        expect(visto.configActiva?.soloTexto, isTrue);

        // Y lo tuyo sigue intacto: el día que el repositorio quite la regla,
        // vuelve la voz que tú habías dado, no la que te dejó él.
        final mio = container
            .read(workspaceControllerProvider.notifier)
            .guardado;
        expect(mio.folders.single.modality, FolderModality.voice);
        expect(mio.permission, FilePermission.canEdit);
        expect(store.workspace.folders.single.modality, FolderModality.voice);
      },
    );

    test(
      'cambiar un ajuste no guarda la regla del repositorio como tuya',
      () async {
        File('${repo.path}/${ConfigDelRepo.archivo}')
          ..createSync(recursive: true)
          ..writeAsStringSync('{"comandosVetados": ["build_runner"]}');

        final (container, store) = await arrancar(
          Workspace(
            folders: [
              PairedFolder(
                path: repo.path,
                modality: FolderModality.textOnly,
                blockedCommands: const ['make generate'],
              ),
            ],
            activePath: repo.path,
          ),
        );

        final notifier = container.read(workspaceControllerProvider.notifier);
        expect(
          container
              .read(workspaceControllerProvider)
              .folders
              .single
              .blockedCommands,
          ['make generate', 'build_runner'],
        );

        // Se toca otra cosa, que es cuando el bug se colaría: al reescribir la
        // carpeta entera se llevaría por delante la lista ya sumada.
        await notifier.setClaudeModel(repo.path, 'opus');

        expect(
          store.workspace.folders.single.blockedCommands,
          ['make generate'],
          reason:
              'el comando del repositorio se guardó como si lo hubieras puesto tú',
        );
      },
    );
  });
}
