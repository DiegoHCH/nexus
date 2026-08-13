import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/superpowers/domain/entities/claude_plugin.dart';
import 'package:nexus/features/superpowers/domain/usecases/plugin_command.dart';

void main() {
  group('las órdenes', () {
    test('siempre alcance user: aquí se configura la cuenta', () {
      expect(PluginCommand.install('algo@oficial'), [
        'plugin',
        'install',
        'algo@oficial',
        '-s',
        'user',
      ]);
      expect(PluginCommand.uninstall('algo'), contains('user'));
      expect(
        PluginCommand.setEnabled('algo', enabled: false),
        contains('disable'),
      );
      expect(
        PluginCommand.setEnabled('algo', enabled: true),
        contains('enable'),
      );
    });

    // No hay terminal al otro lado: si el marketplace cambió el comando de
    // instalación, el CLI esperaría una confirmación que nadie puede darle y el
    // botón parecería colgado.
    test('actualizar no puede quedarse esperando una confirmación', () {
      expect(PluginCommand.update('algo'), contains('-y'));
    });

    test('un identificador raro no llega a ejecutarse', () {
      expect(PluginCommand.install('algo; rm -rf /'), isNull);
      expect(PluginCommand.removeMarketplace('con espacios'), isNull);
      expect(PluginCommand.addMarketplace('dos palabras'), isNull);
      expect(PluginCommand.addMarketplace(''), isNull);
    });
  });

  group('lo que devuelve el CLI', () {
    // Medido contra el binario: `list --json` a secas devuelve un array plano y
    // solo con `--available` aparece el objeto con las dos listas. Dar por
    // hecha la segunda forma habría dejado la pantalla vacía sin error alguno.
    test('el array plano son los instalados', () {
      final plugins = PluginCommand.parseList(
        '[{"name":"uno","pluginId":"uno@x","description":"d"}]',
      );

      expect(plugins.single.installed, isTrue);
      expect(plugins.single.id, 'uno@x');
    });

    test('el objeto trae instalados y disponibles', () {
      final plugins = PluginCommand.parseList('''
{"installed":[{"pluginId":"a@x","name":"a","enabled":false,"installCount":5}],
 "available":[{"pluginId":"b@x","name":"b","installCount":900},
              {"pluginId":"a@x","name":"a","installCount":5}]}
''');

      // Ordenados por instalaciones: es lo único parecido a una señal de
      // calidad entre 287 candidatos.
      expect(plugins.map((plugin) => plugin.id), ['b@x', 'a@x']);
      // El instalado pisa al disponible: sale en las dos listas y lo que
      // interesa saber es que ya lo tienes.
      expect(plugins.last.installed, isTrue);
      expect(plugins.last.enabled, isFalse);
      expect(plugins.first.installed, isFalse);
    });

    test('una respuesta rota no tumba la pantalla', () {
      expect(PluginCommand.parseList('no es json'), isEmpty);
      expect(PluginCommand.parseMarketplaces('{}'), isEmpty);
    });

    // Comprobado en este Mac: `installLocation` apunta a directorios de perfil
    // que ya no existen —quedó de antes de renombrarlos—, así que se enseña el
    // repositorio, que sí es cierto.
    test('del marketplace se enseña el repo, no la ruta local', () {
      final markets = PluginCommand.parseMarketplaces('''
[{"name":"claude-plugins-official","source":"github",
  "repo":"anthropics/claude-plugins-official",
  "installLocation":"/Users/x/.claude-trabajo/plugins/marketplaces/oficial"}]
''');

      expect(markets.single.name, 'claude-plugins-official');
      expect(markets.single.repo, 'anthropics/claude-plugins-official');
    });
  });

  // 287 disponibles: una lista sin buscador no es una lista, es un muro.
  group('el buscador', () {
    final plugins = [
      const ClaudePlugin(
        id: 'a',
        name: 'security-testing',
        description: 'Audita specs de OpenAPI',
        marketplace: 'x',
        installs: 10,
        enabled: true,
        installed: false,
      ),
      const ClaudePlugin(
        id: 'b',
        name: 'adobe',
        description: 'Edita imágenes',
        marketplace: 'x',
        installs: 5,
        enabled: true,
        installed: false,
      ),
    ];

    test('mira el nombre y también la descripción', () {
      expect(PluginCommand.search(plugins, 'security').single.id, 'a');
      expect(PluginCommand.search(plugins, 'openapi').single.id, 'a');
      expect(PluginCommand.search(plugins, 'imágenes').single.id, 'b');
    });

    test('sin nada escrito no filtra', () {
      expect(PluginCommand.search(plugins, '  ').length, 2);
    });
  });
}
