import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/usecases/mcp_permissions.dart';

/// Que las manos puedan usar sus herramientas.
///
/// En headless **nadie aprueba nada**: sin permiso explícito, toda llamada a un servidor
/// MCP se deniega sola. El sintoma no se parecia a un problema de permisos —«no puedo
/// consultar tu calendario», con el conector conectado y sano— y el modo de permisos no
/// influye: con `acceptEdits` fallaba igual.
void main() {
  test('los cuatro flags llegan a la linea de comandos', () {
    // **Tres de ellos se calculaban y se tiraban.** `disallowedTools`, `model` y
    // `effort` llegaban al datasource y no aparecian en los argumentos: se pasaban de
    // mano en mano por tres capas para nada. La consecuencia que dolia es que la
    // funcion de comandos bloqueados estaba **inerte** —se podia configurar y no hacia
    // nada— y el modelo por carpeta no llegaba al CLI.
    //
    // Se comprueban los nombres exactos porque se verificaron contra `claude --help`:
    // inventarse un flag aqui no falla, se ignora, que es como llegamos a esto.
    final fuente = File(
      'lib/features/assistant/data/datasources/claude_cli_data_source.dart',
    ).readAsStringSync();

    for (final flag in [
      "'--model'",
      "'--effort'",
      "'--allowedTools'",
      "'--disallowedTools'",
    ]) {
      expect(fuente, contains(flag), reason: '$flag no se pasa al CLI');
    }
  });

  late Directory perfil;

  setUp(() => perfil = Directory.systemTemp.createTempSync('perfil'));
  tearDown(() => perfil.deleteSync(recursive: true));

  void escribir(String json) =>
      File('${perfil.path}/.claude.json').writeAsStringSync(json);

  group('los servidores de un perfil', () {
    test('salen de los dos sitios, no solo de mcpServers', () async {
      // Los conectores de la cuenta de claude.ai viven en **otra clave** y son los que
      // importan aqui: Calendar, Gmail, Drive, Slack. Mirar solo `mcpServers` deja
      // fuera justo los que se querian usar — en la maquina donde se midio, tres
      // frente a seis.
      escribir('''
      {
        "mcpServers": {"docs-context": {}, "context7": {}},
        "claudeAiMcpEverConnected": ["claude.ai Google Calendar", "claude.ai Gmail"]
      }''');

      expect(
        await McpPermissions.permitidosPara(perfil.path, puedeEscribir: true),
        containsAll([
          'docs-context',
          'context7',
          'claude_ai_Google_Calendar',
          'claude_ai_Gmail',
        ]),
      );
    });

    test('los puntos y espacios pasan a guion bajo, y el guion se queda', () {
      // No es «todo lo que no sea alfanumerico»: los nombres reales de las
      // herramientas conservan el guion —`mcp__docs-context__query-docs`— y lo que
      // cambia son los puntos y los espacios.
      expect(
        McpPermissions.comoSeLlamaLaHerramienta('claude.ai Google Calendar'),
        'claude_ai_Google_Calendar',
      );
      expect(
        McpPermissions.comoSeLlamaLaHerramienta('docs-context'),
        'docs-context',
      );
    });

    test(
      'se lee en cada encargo, asi que un MCP nuevo entra sin reiniciar',
      () async {
        escribir('{"mcpServers": {"uno": {}}}');
        expect(
          await McpPermissions.permitidosPara(perfil.path, puedeEscribir: true),
          ['uno'],
        );

        // Alguien instala otro con la app abierta. **No hay cache**: la siguiente
        // lectura lo ve. Guardarlo al arrancar habria obligado a reiniciar Nexus cada
        // vez que se añade una herramienta, y eso nadie lo adivina.
        escribir('{"mcpServers": {"uno": {}, "dos": {}}}');
        expect(
          await McpPermissions.permitidosPara(perfil.path, puedeEscribir: true),
          ['uno', 'dos'],
        );
      },
    );

    test('un perfil sin archivo, o con basura, no revienta ni inventa', () async {
      // Pasa de verdad: el perfil por defecto de esta maquina no esta autenticado y
      // no tiene ni conectores. Devolver una lista vacia es lo correcto —no habra
      // herramientas— y lo que no vale es caerse en la ruta de cada encargo.
      expect(
        await McpPermissions.permitidosPara(perfil.path, puedeEscribir: true),
        isEmpty,
      );
      expect(
        await McpPermissions.permitidosPara(null, puedeEscribir: true),
        isEmpty,
      );
      expect(
        await McpPermissions.permitidosPara('', puedeEscribir: true),
        isEmpty,
      );

      escribir('esto no es json');
      expect(
        await McpPermissions.permitidosPara(perfil.path, puedeEscribir: true),
        isEmpty,
      );

      escribir('{"mcpServers": "tampoco es un mapa"}');
      expect(
        await McpPermissions.permitidosPara(perfil.path, puedeEscribir: true),
        isEmpty,
      );
    });

    test('acepta la clave de la cuenta tambien como mapa', () async {
      // El formato es de otro programa: hoy es una lista y puede dejar de serlo.
      escribir('{"claudeAiMcpEverConnected": {"claude.ai Slack": true}}');
      expect(
        await McpPermissions.permitidosPara(perfil.path, puedeEscribir: true),
        ['claude_ai_Slack'],
      );
    });
  });

  group('lo que no puede tocar una carpeta de solo lectura', () {
    test('lo que sale de la maquina esta negado por nombre completo', () {
      // Por nombre y no con comodin: se probo `--allowedTools "mcp__*"` contra el CLI
      // real y **no autoriza nada**, asi que tampoco se puede confiar en un patron
      // para negar.
      for (final herramienta in McpPermissions.escrituraDeFuera) {
        expect(herramienta, startsWith('mcp__'));
        expect(
          herramienta.split('__').length,
          3,
          reason: '$herramienta no nombra servidor y herramienta',
        );
      }
    });

    test('estan las cuatro que mas duelen', () {
      // Mandar un correo es irreversible; crear o borrar una reunion le llega a otras
      // personas; escribir en un canal lo lee un equipo; compartir un archivo lo
      // reparte. Si alguna de estas se cae de la lista, una carpeta de solo lectura
      // deja de serlo hacia fuera.
      expect(
        McpPermissions.escrituraDeFuera,
        containsAll([
          'mcp__claude_ai_Gmail__send_message',
          'mcp__claude_ai_Google_Calendar__create_event',
          'mcp__claude_ai_Slack__slack_send_message',
          'mcp__claude_ai_Google_Drive__share_file',
        ]),
      );
    });

    test('la lista es por nombre, y eso queda escrito donde se lee', () {
      // No es una prueba de comportamiento: es una guarda contra que alguien borre la
      // advertencia. Lo que garantiza el solo lectura es **el disco**; hacia fuera de
      // la maquina lo unico que protege es esta lista, que por ser por nombre es
      // incompleta por naturaleza — un conector nuevo trae sus escrituras y no
      // aparece aqui hasta que alguien lo añada.
      final fuente = File(
        'lib/features/assistant/domain/usecases/mcp_permissions.dart',
      ).readAsStringSync();

      expect(fuente, contains('incompleta por naturaleza'));
      expect(fuente, contains('el disco'));
    });
  });
  group('un conector nuevo y una carpeta de solo lectura', () {
    test('el conector desconocido no se autoriza si no se puede escribir', () async {
      // **El agujero que esto cierra.** La lista de negacion es por nombre, asi que no
      // puede adivinar las escrituras de un conector que no conoce: autorizarlo entero
      // dejaria escribir hacia fuera desde una carpeta que promete no escribir.
      escribir('''
      {
        "mcpServers": {"docs-context": {}},
        "claudeAiMcpEverConnected": [
          "claude.ai Google Calendar",
          "claude.ai Lo Que Instale Manana"
        ]
      }''');

      final enSoloLectura = await McpPermissions.permitidosPara(
        perfil.path,
        puedeEscribir: false,
      );

      // El catalogado si, porque de ese sabemos que negarle.
      expect(enSoloLectura, contains('claude_ai_Google_Calendar'));
      // El desconocido no. **Falla del lado seguro**: se pierde que funcione en solo
      // lectura y se gana que la promesa no dependa de que alguien actualice una lista.
      expect(enSoloLectura, isNot(contains('claude_ai_Lo_Que_Instale_Manana')));
      // Y los propios van siempre: los eligio el usuario y son procesos suyos.
      expect(enSoloLectura, contains('docs-context'));
    });

    test('y en una carpeta que puede escribir, va entero', () async {
      escribir('''
      {"claudeAiMcpEverConnected": ["claude.ai Lo Que Instale Manana"]}''');

      // Si la carpeta puede escribir, no hay promesa que romper: no se le va a estorbar
      // a un conector nuevo por no estar catalogado.
      expect(
        await McpPermissions.permitidosPara(perfil.path, puedeEscribir: true),
        contains('claude_ai_Lo_Que_Instale_Manana'),
      );
    });

    test('los catalogados salen de la propia lista de negacion', () {
      // Derivado y no escrito aparte: con dos listas, añadir las escrituras de un
      // conector nuevo y olvidarse de apuntarlo como catalogado lo dejaria sin
      // autorizar para siempre, sin que nadie entendiera por que.
      expect(
        McpPermissions.conectoresCatalogados,
        containsAll([
          'claude_ai_Google_Calendar',
          'claude_ai_Gmail',
          'claude_ai_Slack',
          'claude_ai_Google_Drive',
        ]),
      );
    });
  });
}
