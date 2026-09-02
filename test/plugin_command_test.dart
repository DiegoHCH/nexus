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

    // 🔴 La regresión que se arregló: un instalado llega **sin `name` y sin
    // `pluginId`**, con el identificador en `id`, y la guarda de nombre vacío
    // los tiraba todos. Medido contra el binario.
    test('un instalado llega con `id` y `version`, y no se cae', () {
      final plugins = PluginCommand.parseList('''
{"installed":[{"id":"flash-flutter@flash-g66","version":"0.2.179",
               "scope":"user","enabled":true}],
 "available":[]}
''');

      expect(plugins.single.id, 'flash-flutter@flash-g66');
      expect(plugins.single.version, '0.2.179');
      expect(plugins.single.installed, isTrue);
      // El nombre y el marketplace se derivan del identificador, que ya dice
      // las dos cosas.
      expect(plugins.single.name, 'flash-flutter');
      expect(plugins.single.marketplace, 'flash-g66');
    });

    // El `available` de este CLI excluye lo ya puesto, así que el instalado es
    // la única entrada que hay: si se descartaba, el plugin no salía en
    // ninguna de las dos listas de la pantalla.
    test('lo puesto se enseña aunque el catálogo no lo traiga', () {
      final plugins = PluginCommand.parseList('''
{"installed":[{"id":"flash-flutter@flash-g66","version":"0.2.179"}],
 "available":[{"pluginId":"flashmemory@flash-g66","name":"flashmemory",
               "marketplaceName":"flash-g66","installCount":3}]}
''');

      expect(
        plugins.where((plugin) => plugin.installed).map((p) => p.id),
        ['flash-flutter@flash-g66'],
      );
    });

    // Las dos entradas del mismo plugin traen mitades distintas: la instalada
    // la versión y el interruptor, la del catálogo la descripción.
    test('el instalado se funde con el del catálogo, no lo borra', () {
      final plugins = PluginCommand.parseList('''
{"installed":[{"id":"a@x","version":"2.0.0","enabled":false}],
 "available":[{"pluginId":"a@x","name":"a","description":"hace cosas",
               "marketplaceName":"x","installCount":40}]}
''');

      expect(plugins.single.version, '2.0.0');
      expect(plugins.single.enabled, isFalse);
      expect(plugins.single.description, 'hace cosas');
      expect(plugins.single.installs, 40);
    });

    // Los instalados empatan todos a cero instalaciones y `List.sort` no
    // promete ser estable: sin desempate la lista se reordenaba sola.
    test('el orden no depende de la suerte cuando nadie tiene instalaciones', () {
      final orden = PluginCommand.parseList('''
{"installed":[{"id":"zeta@x"},{"id":"alfa@x"},{"id":"media@x"}],
 "available":[]}
''').map((plugin) => plugin.name);

      expect(orden, ['alfa', 'media', 'zeta']);
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
        version: null,
        installs: 10,
        enabled: true,
        installed: false,
      ),
      const ClaudePlugin(
        id: 'b',
        name: 'adobe',
        description: 'Edita imágenes',
        marketplace: 'x',
        version: null,
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
