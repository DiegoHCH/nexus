import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/remote/domain/dispatcher.dart';
import 'package:nexus/features/artifacts/data/datasources/artifacts_data_source.dart';
import 'package:nexus/features/artifacts/domain/entities/artifact.dart';
import 'package:nexus/features/assistant/data/datasources/claude_cli_data_source.dart';
import 'package:nexus/features/assistant/data/repositories/claude_bridge_impl.dart';
import 'package:nexus/features/assistant/data/repositories/project_context_prompt.dart';
import 'package:nexus/features/assistant/domain/entities/peticion_de_permiso.dart';

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

  // Que la app **rechace** lo que no cabe ya lo prueba de verdad
  // `la_superficie_del_canal_test`, que construye la superficie entera y le pide
  // un documento de medio mega. Aquí queda lo único que esa prueba no puede ver:
  // el **orden**. Medir después de leer da el mismo resultado y el mismo fallo,
  // y para cuando se mide, el pico de memoria y el marco de WebSocket ya han
  // pasado — un comportamiento correcto por un camino que no lo es.
  group('lo que no cabe por el canal', () {
    final superficie = File(
      'lib/features/remote/presentation/assistant_surface.dart',
    ).readAsStringSync();

    test('se pregunta cuánto ocupa antes de abrirlo', () {
      final mide = superficie.indexOf('await archivo.length()');
      final lee = superficie.indexOf('return archivo.readAsString()');

      expect(mide, isNot(-1), reason: 'ya no se pregunta el tamaño');
      expect(lee, isNot(-1));
      expect(mide, lessThan(lee), reason: 'medir después es medir tarde');
      // Y el `readAsString` sin tope que había antes no puede volver.
      expect(superficie, isNot(contains('File(artifactId).readAsString()')));
    });

    test('medio mega, que es generoso para texto', () {
      // Un informe largo son treinta kilobytes. El tope esta para lo que no es un
      // documento, no para recortar los que si lo son.
      expect(Dispatcher.maxBytesDeDocumento, 512 * 1024);
    });
  });

  group('donde se abre cada documento', () {
    // Las dos son comprobaciones **sobre el codigo** y no sobre pixeles, y se dice:
    // una hoja de macOS con miniaturas de QuickLook y un visor web con vista de
    // plataforma no se levantan en un test de widgets sin montar media plataforma.
    // Lo que se ata es la decision, que es justo lo que se rompio las dos veces.

    test('la lista del Mac no esconde lo que su visor no pinta', () {
      // Estuvo filtrada a `isViewable` y el resultado era una pantalla que decia «no
      // hay documentos» con ciento dieciocho en la carpeta: noventa eran `.md`.
      final hoja = File(
        'lib/features/artifacts/presentation/widgets/artifacts_sheet.dart',
      ).readAsStringSync();
      final lista = hoja.substring(
        hoja.indexOf('final artifacts ='),
        hoja.indexOf(';', hoja.indexOf('final artifacts =')),
      );

      expect(
        lista,
        isNot(contains('isViewable')),
        reason:
            'filtrar la lista por lo que abre el visor esconde documentos que '
            'existen; el tipo decide donde se abren, no si se enseñan',
      );
      // Y sigue habiendo dos caminos al abrir: uno no vale para los dos.
      expect(hoja, contains('Artifact.isViewable(artifact.path)'));
    });

    test('el visor del movil no vive dentro de un scroll', () {
      // El molde de las listas envuelve todo en un `SingleChildScrollView`, y el
      // scroll de fuera se queda los gestos: el documento no se movia y parecia que el
      // visor estaba roto. Con su pantalla propia el que hace scroll es el visor.
      final pagina = File(
        'lib/features/remote/presentation/pages/utility_pages.dart',
      ).readAsStringSync();
      // Desde la pantalla hasta el final de su estado: `ArtifactPage` tiene
      // estado desde que el permiso de scripts es por documento, así que lo que
      // se quiere mirar vive en `_ArtifactPageState` y no en la clase de fuera.
      final desde = pagina.indexOf('class ArtifactPage');
      final estado = pagina.indexOf('class _ArtifactPageState', desde);
      final cuerpo = pagina.substring(
        desde,
        pagina.indexOf('\nclass ', estado + 10),
      );

      final pintado = cuerpo.indexOf('_Pintado(');
      expect(pintado, isNot(-1), reason: 'ya no se pinta nada en el movil');
      // El `_Pintado` va en el `Scaffold` propio, que aparece **antes** que el molde.
      expect(
        cuerpo.indexOf('Scaffold('),
        lessThan(pintado),
        reason:
            'si el visor cae dentro de _ListaDeUtilidad, vuelve a no poder hacer '
            'scroll y a perder el ancho por el padding',
      );
      expect(cuerpo.indexOf('_ListaDeUtilidad('), greaterThan(pintado));
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
    List<String> herramientasMcp = const [],
    Future<RespuestaDePermiso> Function(PeticionDePermiso)? alPedirPermiso,
  }) {
    lastDirs = extraDirectories;
    return const Stream.empty();
  }
}
