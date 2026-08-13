import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/superpowers/domain/entities/mcp_server.dart';
import 'package:nexus/features/superpowers/domain/usecases/mcp_command.dart';

void main() {
  group('la orden que se le pasa al CLI', () {
    // El alcance es «user» porque aquí se configura la cuenta. Uno de proyecto
    // viviría en un `.mcp.json` dentro del repo, que es decisión del repo.
    test('un servidor por URL va como transporte http y alcance user', () {
      expect(McpCommand.add(name: 'figma', url: 'https://mcp.figma.com/mcp'), [
        'mcp',
        'add',
        '-s',
        'user',
        '--transport',
        'http',
        'figma',
        'https://mcp.figma.com/mcp',
      ]);
    });

    test('uno por comando va detrás del doble guion', () {
      expect(
        McpCommand.add(
          name: 'context7',
          command: ['npx', '-y', '@upstash/context7-mcp'],
        ),
        [
          'mcp',
          'add',
          '-s',
          'user',
          'context7',
          '--',
          'npx',
          '-y',
          '@upstash/context7-mcp',
        ],
      );
    });

    // Aquí está la trampa: después del `--`, el CLI toma las variables por
    // argumentos del servidor, y la clave de API acabaría en su línea de
    // comandos en vez de en su entorno.
    test('las variables de entorno van ANTES del doble guion', () {
      final args = McpCommand.add(
        name: 'algo',
        command: ['npx', 'algo-mcp'],
        env: ['API_KEY=secreto'],
      )!;

      expect(args.indexOf('-e') < args.indexOf('--'), isTrue);
      expect(args.sublist(args.indexOf('-e'), args.indexOf('--')), [
        '-e',
        'API_KEY=secreto',
      ]);
    });

    test('una variable mal escrita no se cuela', () {
      final args = McpCommand.add(
        name: 'algo',
        command: ['x'],
        env: ['sin-igual', '1MAL=x', 'BIEN=x'],
      )!;

      expect(args.where((arg) => arg.contains('=')), ['BIEN=x']);
    });

    // Estos argumentos acaban en un proceso: un nombre con espacios o comillas
    // es la puerta a que la orden diga otra cosa.
    test('un nombre raro no llega a ejecutarse', () {
      expect(McpCommand.add(name: 'con espacios', url: 'https://x'), isNull);
      expect(McpCommand.add(name: '', url: 'https://x'), isNull);
      expect(McpCommand.remove('rm -rf /'), isNull);
    });

    test('sin URL ni comando no hay orden que dar', () {
      expect(McpCommand.add(name: 'algo'), isNull);
    });
  });

  group('lo que devuelve `claude mcp list`', () {
    // Medido contra el binario el 13 ago: los conectores de la cuenta llevan
    // espacios en el nombre y URLs con «https://» —o sea, más dos puntos— así
    // que el nombre tiene que leerse no ávido o se parte por donde no es.
    const salida = '''
Checking MCP server health…

claude.ai Atlassian Rovo: https://mcp.atlassian.com/v1/mcp - ✔ Connected
claude.ai Figma: https://mcp.figma.com/mcp - ! Needs authentication
docs-context: npx -y @upstash/context7-mcp - ✔ Connected
roto: algo - ✘ Failed to connect
''';

    test('se leen todos, con su nombre entero', () {
      final servers = McpCommand.parseList(salida);

      expect(servers.map((server) => server.name), [
        'claude.ai Atlassian Rovo',
        'claude.ai Figma',
        'docs-context',
        'roto',
      ]);
      expect(servers.first.spec, 'https://mcp.atlassian.com/v1/mcp');
    });

    test('el estado se traduce', () {
      final servers = McpCommand.parseList(salida);

      expect(servers[0].status, McpStatus.connected);
      expect(servers[1].status, McpStatus.needsAuth);
      expect(servers[3].status, McpStatus.failed);
    });

    // Los de la cuenta llegan con la sesión de claude.ai y no están en el
    // archivo del perfil: ofrecer un botón de quitar que no puede quitar sería
    // peor que no ofrecerlo.
    test('los conectores de la cuenta quedan marcados', () {
      final servers = McpCommand.parseList(salida);

      expect(servers[0].fromAccount, isTrue);
      expect(servers[2].fromAccount, isFalse);
    });

    test('la cabecera y las líneas vacías no cuentan como servidores', () {
      expect(McpCommand.parseList('Checking MCP server health…\n\n'), isEmpty);
    });
  });
}
