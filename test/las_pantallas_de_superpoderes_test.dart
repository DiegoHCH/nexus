import 'package:flutter/material.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/features/superpowers/data/datasources/mcp_data_source.dart';
import 'package:nexus/features/superpowers/data/datasources/plugins_data_source.dart';
import 'package:nexus/features/superpowers/data/datasources/skills_data_source.dart';
import 'package:nexus/features/superpowers/domain/entities/claude_plugin.dart';
import 'package:nexus/features/superpowers/domain/entities/mcp_server.dart';
import 'package:nexus/features/superpowers/domain/entities/skill.dart';
import 'package:nexus/features/superpowers/presentation/providers/superpowers_providers.dart';
import 'package:nexus/features/superpowers/presentation/widgets/mcp_panel.dart';
import 'package:nexus/features/superpowers/presentation/widgets/plugins_panel.dart';
import 'package:nexus/features/superpowers/presentation/widgets/skills_panel.dart';

import 'support/screen_harness.dart';

/// Los tres paneles de superpoderes, que estaban **al 0 %**.
///
/// Toda la feature con más diálogos con formulario del proyecto no tenía una
/// sola línea ejecutada por la suite. Y es justo la clase de cosa que estas
/// pruebas pillan y el analizador no —lo dice el encabezado del `ci.yml`: «una
/// fila que desborda, un velo colapsado a tamaño cero»—.
///
/// Lo que se comprueba es lo que se rompe sin avisar: que **lo vacío se dice**
/// en vez de dejar un hueco mudo, que **lo largo no desborda** —hay repos con
/// 896 skills y marketplaces con 287 plugins— y que un fallo de la cuenta se
/// enseña en vez de quedarse en un panel en blanco.
const _cuenta = '/Users/alguien/.claude';

class _Skills extends SkillsDataSource {
  const _Skills({this.puestas = const [], this.delRepo, this.error});

  final List<Skill> puestas;
  final List<Skill>? delRepo;
  final String? error;

  @override
  Future<List<Skill>> installed(String configDir) async => puestas;

  @override
  Future<({List<Skill> skills, String? error})> scan(String repoRaw) async =>
      (skills: delRepo ?? const [], error: error);
}

class _Mcp extends McpDataSource {
  const _Mcp({this.servidores = const []});

  final List<McpServer> servidores;

  @override
  Future<List<McpServer>> list(String configDir) async => servidores;

  @override
  Future<List<McpServer>?> check(String configDir) async => servidores;
}

class _Plugins extends PluginsDataSource {
  const _Plugins({this.puestos = const [], this.tiendas = const []});

  final List<ClaudePlugin> puestos;
  final List<Marketplace> tiendas;

  @override
  Future<List<ClaudePlugin>> list(String configDir) async => puestos;

  @override
  Future<List<Marketplace>> marketplaces(String configDir) async => tiendas;
}

ClaudePlugin plugin(String nombre, {bool instalado = true}) => ClaudePlugin(
  id: '$nombre@tienda',
  name: nombre,
  description: 'Lo que hace $nombre, contado en una línea que ocupa lo suyo.',
  marketplace: 'tienda',
  version: '1.2.3',
  installs: 128,
  enabled: true,
  installed: instalado,
);

void main() {
  const textos = NexusStringsEs();

  /// Ninguna de estas pruebas puede desbordar. Se comprueba en las dos: una
  /// pantalla que desborda tira una excepción del framework y `pumpScreen` la
  /// deja en `takeException`.
  void sinDesbordar(WidgetTester tester) {
    expect(
      tester.takeException(),
      isNull,
      reason: 'algo desbordó o reventó al pintar',
    );
  }

  group('skills', () {
    Future<void> abrir(WidgetTester tester, SkillsDataSource fuente) =>
        pumpScreen(
          tester,
          const Scaffold(body: SkillsPanel(configDir: _cuenta)),
          overrides: [skillsDataSourceProvider.overrideWithValue(fuente)],
        );

    testWidgets('sin ninguna puesta lo dice, en vez de dejar un hueco', (
      tester,
    ) async {
      await abrir(tester, const _Skills());

      expect(find.text(textos.skillsNone), findsOneWidget);
      sinDesbordar(tester);
    });

    testWidgets('las puestas se enseñan con su descripción', (tester) async {
      await abrir(
        tester,
        const _Skills(
          puestas: [
            Skill(id: 'revisar-pr', description: 'Revisa un PR de GitHub'),
          ],
        ),
      );

      expect(find.text('revisar-pr'), findsOneWidget);
      expect(
        find.textContaining('Revisa un PR'),
        findsWidgets,
        reason:
            'la descripción es lo único que el agente mira para activarla: no '
            'es decorativa',
      );
      sinDesbordar(tester);
    });

    // 🔴 El caso que motivó el buscador: `davila7/claude-code-templates` tiene
    // **896**. Una lista así sin recortar no cabe en ninguna ventana.
    testWidgets('un repo con cientos no desborda la ventana', (tester) async {
      await abrir(
        tester,
        _Skills(
          delRepo: [
            for (var i = 0; i < 300; i++)
              Skill(
                id: 'skill-numero-$i',
                description:
                    'Una descripción larga de la skill $i, de las que ocupan '
                    'una línea entera y a veces dos en una ventana estrecha.',
              ),
          ],
        ),
      );

      sinDesbordar(tester);
    });

    testWidgets('un repo que no se puede leer lo dice', (tester) async {
      await abrir(tester, const _Skills(error: 'Eso no parece un repo'));

      expect(find.textContaining('Eso no parece un repo'), findsOneWidget);
      sinDesbordar(tester);
    });
  });

  group('servidores MCP', () {
    Future<void> abrir(WidgetTester tester, McpDataSource fuente) => pumpScreen(
      tester,
      const Scaffold(body: McpPanel(configDir: _cuenta)),
      overrides: [mcpDataSourceProvider.overrideWithValue(fuente)],
    );

    testWidgets('sin ninguno lo dice', (tester) async {
      await abrir(tester, const _Mcp());

      expect(find.text(textos.mcpNone), findsOneWidget);
      sinDesbordar(tester);
    });

    testWidgets(
      'cada uno se enseña con su destino, que es lo que lo identifica',
      (tester) async {
        await abrir(
          tester,
          const _Mcp(
            servidores: [
              McpServer(name: 'contexto', spec: 'https://mcp.example.com/sse'),
            ],
          ),
        );

        expect(find.text('contexto'), findsOneWidget);
        expect(
          find.textContaining('mcp.example.com'),
          findsWidgets,
          reason:
              'dos con el mismo nombre y distinto destino son cosas distintas',
        );
        sinDesbordar(tester);
      },
    );

    // Un comando con sus argumentos es largo de verdad, y es lo normal en los
    // servidores locales.
    testWidgets('un destino larguísimo no desborda', (tester) async {
      await abrir(
        tester,
        const _Mcp(
          servidores: [
            McpServer(
              name: 'uno-de-los-locales',
              spec:
                  'npx -y @modelcontextprotocol/server-filesystem '
                  '/Users/alguien/una/ruta/bastante/larga/que/alguien/tendra '
                  '--con --unas --cuantas --banderas --detras',
            ),
          ],
        ),
      );

      sinDesbordar(tester);
    });
  });

  group('plugins', () {
    Future<void> abrir(WidgetTester tester, PluginsDataSource fuente) =>
        pumpScreen(
          tester,
          const Scaffold(body: PluginsPanel(configDir: _cuenta)),
          overrides: [pluginsDataSourceProvider.overrideWithValue(fuente)],
        );

    testWidgets('sin ninguno lo dice', (tester) async {
      await abrir(tester, const _Plugins());

      expect(find.text(textos.pluginsNone), findsOneWidget);
      sinDesbordar(tester);
    });

    testWidgets('uno instalado se enseña con su versión', (tester) async {
      await abrir(tester, _Plugins(puestos: [plugin('flash-flutter')]));

      expect(find.text('flash-flutter'), findsOneWidget);
      expect(
        find.textContaining('1.2.3'),
        findsWidgets,
        reason: 'sin la versión no se sabe si hay que actualizarlo',
      );
      sinDesbordar(tester);
    });

    // El marketplace del proyecto tiene 287.
    testWidgets('un catálogo de cientos no desborda', (tester) async {
      await abrir(
        tester,
        _Plugins(
          puestos: [
            for (var i = 0; i < 300; i++)
              plugin('plugin-numero-$i', instalado: false),
          ],
          tiendas: const [Marketplace(name: 'tienda', repo: 'alguien/repo')],
        ),
      );

      sinDesbordar(tester);
    });
  });

  // El tema claro nunca se había mirado en esta feature, y un desbordamiento o
  // un texto ilegible ahí no rompen ninguna regla: solo se ven.
  testWidgets('los tres se pintan también en claro', (tester) async {
    for (final panel in const [
      Scaffold(body: SkillsPanel(configDir: _cuenta)),
      Scaffold(body: McpPanel(configDir: _cuenta)),
      Scaffold(body: PluginsPanel(configDir: _cuenta)),
    ]) {
      await pumpScreen(
        tester,
        panel,
        theme: NexusTheme.light(),
        overrides: [
          skillsDataSourceProvider.overrideWithValue(const _Skills()),
          mcpDataSourceProvider.overrideWithValue(const _Mcp()),
          pluginsDataSourceProvider.overrideWithValue(const _Plugins()),
        ],
      );
      sinDesbordar(tester);
    }
  });
}
