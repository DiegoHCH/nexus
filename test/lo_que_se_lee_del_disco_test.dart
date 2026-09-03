import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/e2e/data/datasources/repo_de_pruebas_data_source.dart';
import 'package:nexus/features/stats/data/datasources/transcript_data_source.dart';
import 'package:nexus/features/superpowers/data/datasources/mcp_data_source.dart';

/// Lo que la capa `data` lee del disco, probado sin lanzar un proceso.
///
/// 🔴 La capa estaba al **55,3 %**, y el motivo de que no subiera es que casi
/// todo ahí lanza binarios. Pero **no todo**: estos tres leen archivos, y son
/// archivos cuyo formato lo decide otro —la configuración de Claude Code, la
/// disposición de un repo de Maestro, el JSONL de los transcritos—. O sea que
/// pueden cambiar sin que nadie de aquí toque nada, y cuando cambien lo que se
/// ve es una lista vacía: la pantalla dice «no hay» en vez de «no supe leerlo».
void main() {
  late Directory cajon;

  setUp(() => cajon = Directory.systemTemp.createTempSync('nexus_disco'));
  tearDown(() => cajon.deleteSync(recursive: true));

  group('los servidores MCP del perfil', () {
    const fuente = McpDataSource();

    void config(Object contenido) =>
        File('${cajon.path}/.claude.json').writeAsStringSync(
          contenido is String ? contenido : jsonEncode(contenido),
        );

    test('sin archivo no hay servidores, y no es un error', () async {
      expect(await fuente.list(cajon.path), isEmpty);
    });

    test('un archivo ilegible tampoco tumba la pantalla', () async {
      config('{ esto no cierra');

      expect(await fuente.list(cajon.path), isEmpty);
    });

    test('un archivo sin la clave se lee vacío', () async {
      config({'otraCosa': 1});

      expect(await fuente.list(cajon.path), isEmpty);
    });

    test('uno por URL se identifica por su URL', () async {
      config({
        'mcpServers': {
          'contexto': {'url': 'https://mcp.example.com/sse'},
        },
      });

      final leidos = await fuente.list(cajon.path);

      expect(leidos.single.name, 'contexto');
      expect(leidos.single.spec, 'https://mcp.example.com/sse');
    });

    // 🔴 El `spec` es lo que distingue dos servidores con el mismo nombre, así
    // que un comando tiene que llegar entero: con los argumentos detrás.
    test('uno local se identifica por su comando con argumentos', () async {
      config({
        'mcpServers': {
          'archivos': {
            'command': 'npx',
            'args': ['-y', '@modelcontextprotocol/server-filesystem', '/tmp'],
          },
        },
      });

      expect(
        (await fuente.list(cajon.path)).single.spec,
        'npx -y @modelcontextprotocol/server-filesystem /tmp',
      );
    });

    test('uno sin URL ni comando no revienta: se queda sin destino', () async {
      config({
        'mcpServers': {
          'a-medias': {'type': 'stdio'},
        },
      });

      final leidos = await fuente.list(cajon.path);

      expect(leidos.single.name, 'a-medias');
      expect(leidos.single.spec, isEmpty);
    });
  });

  group('los flows de un repo de pruebas', () {
    const fuente = RepoDePruebasDataSource();

    void flow(String ruta) => File('${cajon.path}/flows/$ruta')
      ..createSync(recursive: true)
      ..writeAsStringSync('appId: com.ejemplo\n---\n- launchApp\n');

    test('sin carpeta de flows no hay ninguno', () async {
      expect(await fuente.flows(cajon.path), isEmpty);
    });

    test('se listan en orden y con su ruta relativa al clon', () async {
      flow('onboarding.yaml');
      flow('pagos/tarjeta.yaml');
      flow('pagos/transferencia.yml');

      expect(await fuente.flows(cajon.path), [
        'flows/onboarding.yaml',
        'flows/pagos/tarjeta.yaml',
        'flows/pagos/transferencia.yml',
      ]);
    });

    test('lo que no es un flow no se cuela', () async {
      flow('bueno.yaml');
      File('${cajon.path}/flows/LEEME.md').writeAsStringSync('nada');
      File('${cajon.path}/flows/.oculto.yaml').writeAsStringSync('nada');

      expect(await fuente.flows(cajon.path), ['flows/bueno.yaml']);
    });

    test('leer devuelve el contenido, y null si no está', () async {
      flow('onboarding.yaml');

      expect(
        await fuente.leer(clon: cajon.path, ruta: 'flows/onboarding.yaml'),
        contains('launchApp'),
      );
      expect(
        await fuente.leer(clon: cajon.path, ruta: 'flows/no-existe.yaml'),
        isNull,
      );
    });
  });

  group('los transcritos', () {
    const fuente = TranscriptDataSource();

    void transcrito(String nombre, List<String> lineas) =>
        File('${cajon.path}/projects/$nombre')
          ..createSync(recursive: true)
          ..writeAsStringSync(lineas.join('\n'));

    String turno({
      required String cuando,
      required String sesion,
      String tipo = 'assistant',
      int entrada = 100,
      int salida = 50,
    }) => jsonEncode({
      'type': tipo,
      'timestamp': cuando,
      'sessionId': sesion,
      'message': {
        'model': 'claude-opus-5',
        'usage': {'input_tokens': entrada, 'output_tokens': salida},
      },
    });

    test('sin carpeta de proyectos no hay turnos', () async {
      expect(await fuente.read(cajon.path), isEmpty);
    });

    test('se leen de todos los proyectos y salen en orden de reloj', () async {
      transcrito('uno/a.jsonl', [
        turno(cuando: '2026-09-03T12:00:00Z', sesion: 's1'),
      ]);
      transcrito('otro/b.jsonl', [
        turno(cuando: '2026-09-03T09:00:00Z', sesion: 's2'),
      ]);

      final turnos = await fuente.read(cajon.path);

      expect(turnos.map((t) => t.sessionId), ['s2', 's1']);
    });

    // La mayoría de las líneas no son turnos —adjuntos, instantáneas de
    // archivos— y algunas pesan 160 KB. Que se salten es el rendimiento; que no
    // rompan es lo que se prueba aquí.
    test('lo que no es un turno se salta sin romper el resto', () async {
      transcrito('uno/a.jsonl', [
        '{"type":"file-snapshot","enorme":true}',
        'esto no es json',
        '',
        turno(cuando: '2026-09-03T10:00:00Z', sesion: 's1'),
        '{"type":"assistant","sin":"fecha"}',
      ]);

      final turnos = await fuente.read(cajon.path);

      expect(turnos.single.sessionId, 's1');
    });

    test('lo que no es .jsonl no se mira', () async {
      transcrito('uno/a.txt', [
        turno(cuando: '2026-09-03T10:00:00Z', sesion: 's1'),
      ]);

      expect(await fuente.read(cajon.path), isEmpty);
    });

    test('el gasto del turno llega entero', () async {
      transcrito('uno/a.jsonl', [
        turno(
          cuando: '2026-09-03T10:00:00Z',
          sesion: 's1',
          entrada: 1200,
          salida: 340,
        ),
      ]);

      final turno0 = (await fuente.read(cajon.path)).single;

      expect(turno0.input, 1200);
      expect(turno0.output, 340);
      expect(turno0.model, 'claude-opus-5');
      expect(turno0.fromAssistant, isTrue);
    });
  });
}
