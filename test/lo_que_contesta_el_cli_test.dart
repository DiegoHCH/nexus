import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/superpowers/data/datasources/mcp_data_source.dart';
import 'package:nexus/features/superpowers/data/datasources/plugins_data_source.dart';

/// Cómo se lee lo que contesta el CLI, con un `claude` de mentira.
///
/// 🔴 **El texto del error es la mitad del producto aquí.** El propio código lo
/// dice: se devuelve lo que dijo el CLI y no un booleano «porque lo que dice es
/// accionable —"ya existe uno con ese nombre"— y esconderlo detrás de "no se
/// pudo" obliga a abrir la terminal para averiguar qué pasó». Eso son cuatro
/// caminos distintos y ninguno tenía prueba.
void main() {
  late Directory cajon;

  setUp(() => cajon = Directory.systemTemp.createTempSync('nexus_cli'));
  tearDown(() => cajon.deleteSync(recursive: true));

  Future<String> guionDe(String cuerpo) async {
    final script = File('${cajon.path}/claude-de-mentira.sh');
    script.writeAsStringSync('#!/bin/sh\n$cuerpo\n');
    await Process.run('chmod', ['+x', script.path]);
    return script.path;
  }

  group('los servidores MCP', () {
    McpDataSource conUnCli(String cuerpo) =>
        McpDataSource(claude: () => guionDe(cuerpo));

    test('con código cero no hay error que contar', () async {
      final fuente = conUnCli('exit 0');

      expect(await fuente.remove(cajon.path, 'contexto'), isNull);
    });

    // Lo accionable suele venir por `stderr`, y es lo que se prefiere.
    test('el error del CLI se devuelve tal cual', () async {
      final fuente = conUnCli(
        'echo "Error: ya existe uno con ese nombre" >&2\nexit 1',
      );

      expect(
        await fuente.remove(cajon.path, 'contexto'),
        'Error: ya existe uno con ese nombre',
      );
    });

    // Pero no siempre lo pone ahí: un CLI que falla escribiendo por `stdout`
    // dejaría el mensaje vacío si solo se mirara `stderr`.
    test('si stderr viene vacío, se cuenta lo de stdout', () async {
      final fuente = conUnCli('echo "no se pudo resolver el comando"\nexit 1');

      expect(
        await fuente.remove(cajon.path, 'contexto'),
        'no se pudo resolver el comando',
      );
    });

    test(
      'sin binario que lanzar se cuenta el motivo, no un silencio',
      () async {
        final fuente = McpDataSource(
          claude: () async => '${cajon.path}/esto-no-existe',
        );

        expect(await fuente.remove(cajon.path, 'contexto'), isNotNull);
      },
    );

    test('unos datos que no arman comando ni se lanzan', () async {
      final fuente = conUnCli('exit 0');

      expect(
        await fuente.add(cajon.path, name: '', url: null),
        isNotNull,
        reason: 'sin nombre ni destino no hay comando que correr',
      );
    });

    // 🔴 El error va **por cuenta**: puesto en montón se pierde justo lo que lo
    // hace útil, que es saber en cuál no entró.
    test('en varias cuentas, cada una con su fallo', () async {
      final fuente = conUnCli(r'''
case "$CLAUDE_CONFIG_DIR" in
  *rota) echo "no hay sesión en esta cuenta" >&2; exit 1 ;;
  *) exit 0 ;;
esac
''');

      final fallos = await fuente.addEn(
        ['${cajon.path}/buena', '${cajon.path}/rota'],
        name: 'contexto',
        url: 'https://mcp.example.com/sse',
      );

      expect(fallos.keys, ['${cajon.path}/rota']);
      expect(fallos.values.single, 'no hay sesión en esta cuenta');
    });
  });

  group('los plugins', () {
    PluginsDataSource conUnCli(String cuerpo) =>
        PluginsDataSource(claude: () => guionDe(cuerpo));

    test('lo que no contesta nada se lee como ninguno', () async {
      final fuente = conUnCli('exit 1');

      expect(await fuente.list(cajon.path), isEmpty);
      expect(await fuente.marketplaces(cajon.path), isEmpty);
    });

    test('una instalación que sale bien no deja error', () async {
      final fuente = conUnCli('exit 0');

      expect(await fuente.install(cajon.path, 'flash@tienda'), isNull);
    });

    test('y una que falla dice por qué', () async {
      final fuente = conUnCli('echo "marketplace desconocido" >&2\nexit 1');

      expect(
        await fuente.install(cajon.path, 'flash@tienda'),
        'marketplace desconocido',
      );
    });
  });
}
