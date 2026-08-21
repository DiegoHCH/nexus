import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/artifacts/data/datasources/artifacts_data_source.dart';
import 'package:nexus/features/artifacts/domain/entities/artifact.dart';
import 'package:nexus/features/assistant/data/datasources/claude_cli_data_source.dart';
import 'package:nexus/features/assistant/data/repositories/claude_bridge_impl.dart';
import 'package:nexus/features/assistant/data/repositories/project_context_prompt.dart';

void main() {
  group('qué entra en la lista', () {
    test('lo que el visor sabe pintar', () {
      expect(Artifact.isViewable('/x/mockup.html'), isTrue);
      expect(Artifact.isViewable('/x/informe.PDF'), isTrue);
      expect(Artifact.isViewable('/x/captura.png'), isTrue);
    });

    // Un `.md` habría que interpretarlo y un `.zip` no tiene nada que enseñar:
    // ofrecerlos abriría una ventana en blanco.
    test('y no lo que abriría una ventana vacía', () {
      expect(Artifact.isViewable('/x/notas.md'), isFalse);
      expect(Artifact.isViewable('/x/todo.zip'), isFalse);
      expect(Artifact.isViewable('/x/sin-extension'), isFalse);
    });
  });

  group('la carpeta', () {
    late Directory dir;
    const source = ArtifactsDataSource();

    setUp(() => dir = Directory.systemTemp.createTempSync('nexus_art'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('lo más reciente arriba: es lo que vas a abrir', () async {
      File('${dir.path}/viejo.html').writeAsStringSync('<p>a</p>');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      File('${dir.path}/nuevo.html').writeAsStringSync('<p>b</p>');

      final artifacts = await source.list(dir.path);

      expect(artifacts.map((artifact) => artifact.name), [
        'nuevo.html',
        'viejo.html',
      ]);
    });

    // La carpeta de artefactos es un cajón, no un árbol: bajando recursivamente
    // se colaría en la lista el `assets/` que muchos documentos traen al lado.
    test('un nivel, y sin los ocultos', () async {
      File('${dir.path}/bueno.html').writeAsStringSync('<p>a</p>');
      File('${dir.path}/.oculto.html').writeAsStringSync('<p>b</p>');
      Directory('${dir.path}/assets').createSync();
      File('${dir.path}/assets/dentro.png').writeAsStringSync('x');

      final artifacts = await source.list(dir.path);

      expect(artifacts.map((artifact) => artifact.name), ['bueno.html']);
    });

    test('una carpeta que no existe no revienta', () async {
      expect(await source.list('${dir.path}/no-existe'), isEmpty);
    });
  });

  group('lo que se le dice a Claude', () {
    // Sin decírselo, un mockup acaba en la raíz del repo y la lista se queda
    // vacía mientras el archivo existe.
    test('con carpeta elegida, se le nombra', () {
      final prompt = ProjectContextPrompt.compose(
        rules: const [],
        artifactsFolder: '/Users/x/Documentos',
      );

      expect(prompt, contains('/Users/x/Documentos'));
      // Y se le acota: el código del proyecto no va ahí.
      expect(prompt, contains('código del proyecto'));
    });

    // Inventarle un destino sería escribir donde el usuario no ha invitado.
    test('sin carpeta elegida, no se le inventa un destino', () {
      expect(ProjectContextPrompt.compose(rules: const []), isNull);
    });
  });

  // Medido contra el binario el 13 ago: sin `--add-dir`, escribir fuera del
  // directorio de trabajo se deniega —sale en `permission_denials`— y Claude
  // acaba pidiendo un permiso que en headless no hay quien conceda. Con él,
  // el archivo se crea y no hay denegación.
  test('la carpeta de documentos viaja como carpeta alcanzable', () async {
    final bridge = ClaudeBridgeImpl(_SpyCli());

    await bridge
        .ask(
          'haz un mockup',
          workingDirectory: '/repo',
          canEdit: true,
          artifactsFolder: '/Users/x/Documentos',
        )
        .toList();

    expect(_SpyCli.lastDirs, contains('/Users/x/Documentos'));
  });

  group('que cuenta como documento y que viaja como texto', () {
    test('un .html es las dos cosas', () {
      // Las dos preguntas se solapan a proposito: el visor del Mac lo pinta **y**
      // viaja por el canal como una cadena, porque un HTML es texto. De eso depende
      // que el telefono pueda abrir los veintiocho que hay.
      expect(Artifact.isViewable('/x/mockup.html'), isTrue);
      expect(Artifact.isTextual('/x/mockup.html'), isTrue);
      expect(Artifact.isListable('/x/mockup.html'), isTrue);
    });

    test(
      'un .md es documento y texto, aunque el visor del Mac no lo pinte',
      () {
        expect(Artifact.isListable('/x/informe.md'), isTrue);
        expect(Artifact.isTextual('/x/informe.md'), isTrue);
        expect(Artifact.isViewable('/x/informe.md'), isFalse);
      },
    );

    test('un .png es documento pero NO texto', () {
      // Leerlo como cadena da un error de codificacion, no una imagen: por eso se
      // dice en la lista en vez de descubrirse al abrir.
      expect(Artifact.isListable('/x/logo.png'), isTrue);
      expect(Artifact.isTextual('/x/logo.png'), isFalse);
    });

    test('un .zip no es nada de esto', () {
      expect(Artifact.isListable('/x/todo.zip'), isFalse);
    });
  });
}

/// Se queda con lo que se le pasó al proceso, sin lanzar ninguno.
class _SpyCli implements ClaudeCliDataSource {
  static List<String> lastDirs = const [];

  @override
  Stream<Map<String, dynamic>> run(
    String instruction, {
    required String workingDirectory,
    required String permissionMode,
    List<String> extraDirectories = const [],
    String? resumeSessionId,
    String? appendSystemPrompt,
    String? configDir,
    String? model,
    String? effort,
    List<String> disallowedTools = const [],
  }) {
    lastDirs = extraDirectories;
    return const Stream.empty();
  }
}
