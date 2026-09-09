import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/superpowers/domain/entities/mcp_server.dart';
import 'package:nexus/features/superpowers/domain/usecases/la_lista_de_mcp.dart';

/// **Los MCP de la cuenta también se listan.**
///
/// 🔴 Reportado mirando la pantalla: «no se están listando todos los MCP que
/// tengo en mi cuenta; solo se listan los de usuario y no los de claude.ai». Y
/// era exacto. Medido en este Mac, con el mismo perfil:
///
/// - `<perfil>/.claude.json` → `mcpServers`: **cinco**. Es lo que la pantalla
///   enseñaba, porque leer el archivo es instantáneo.
/// - `claude mcp list` → **veinte**: esos cinco y **quince conectores
///   `claude.ai …`** —Gmail, Slack, Calendar, Drive, Notion, Jira…—.
///
/// Los quince no están en ningún archivo del perfil: llegan con la sesión de
/// claude.ai. El único rastro en disco es `claudeAiMcpEverConnected`, que es un
/// registro de «alguna vez conectó» —seis nombres de los quince— y no la lista,
/// así que tampoco sirve.
McpServer _mio(String nombre, {McpStatus estado = McpStatus.unknown}) =>
    McpServer(name: nombre, spec: 'npx -y $nombre', status: estado);

McpServer _deLaCuenta(
  String nombre, {
  McpStatus estado = McpStatus.connected,
}) => McpServer(
  name: 'claude.ai $nombre',
  spec: 'https://mcp.$nombre.com/mcp',
  status: estado,
  fromAccount: true,
);

void main() {
  group('cuándo hay que volver a preguntarle al CLI', () {
    test('sin nada recordado, sí: la lista saldría a medias', () {
      expect(LaListaDeMcp.hayQuePreguntar(null), isTrue);
    });

    test('recién preguntado, no: cuesta casi un minuto de procesos', () {
      final ahora = DateTime(2026, 9, 9, 12);
      expect(
        LaListaDeMcp.hayQuePreguntar(
          ahora.subtract(const Duration(minutes: 20)),
          ahora: ahora,
        ),
        isFalse,
      );
    });

    test('pasado el plazo, otra vez', () {
      final ahora = DateTime(2026, 9, 9, 12);
      expect(
        LaListaDeMcp.hayQuePreguntar(
          ahora.subtract(const Duration(hours: 7)),
          ahora: ahora,
        ),
        isTrue,
      );
    });

    // Un reloj que va hacia atrás —cambio de hora, un archivo copiado de otra
    // máquina— no puede dejar la lista congelada para siempre.
    test('una fecha del futuro no congela la lista', () {
      final ahora = DateTime(2026, 9, 9, 12);
      expect(
        LaListaDeMcp.hayQuePreguntar(
          ahora.add(const Duration(days: 2)),
          ahora: ahora,
        ),
        isTrue,
      );
    });
  });

  // 🔴 **Pedido con la referencia delante:** «quisiera escribir el `/mcp` y que
  // me mostrara el listado de MCP en el chat, así como se hace en el CLI, con
  // su conectado o desconectado». Estaba en Ajustes, y eso es levantarse de la
  // conversación para responder una pregunta de una línea.
  group('contada en la conversación', () {
    String contada(List<McpServer> lista, {String? estado}) =>
        LaListaDeMcp.comoSeCuenta(
          lista: lista,
          titulo: '${lista.length} servidores MCP en la cuenta work:',
          comoEsta: (e) => switch (e) {
            McpStatus.connected => 'conectado',
            McpStatus.needsAuth => 'pide iniciar sesión',
            McpStatus.failed => 'no responde',
            McpStatus.unknown => 'sin comprobar',
          },
          deLaCuentaDicho: LaListaDeMcp.deLaCuenta(lista) > 0
              ? 'uno es de tu cuenta'
              : null,
          elEstado: estado,
        );

    test('cada uno con su estado y su destino, como en el CLI', () {
      final dicho = contada([
        _mio('maestro', estado: McpStatus.connected),
        _deLaCuenta('Figma', estado: McpStatus.needsAuth),
        _mio('g66', estado: McpStatus.failed),
        _mio('recién-puesto'),
      ]);

      expect(dicho, contains('· maestro — conectado · npx -y maestro'));
      expect(dicho, contains('claude.ai Figma — pide iniciar sesión'));
      expect(dicho, contains('· g66 — no responde'));
      expect(
        dicho,
        contains('recién-puesto — sin comprobar'),
        reason: 'uno del archivo que el CLI no ha mirado todavía',
      );
      // El destino va detrás del estado porque es lo que distingue dos
      // servidores con el mismo nombre.
      expect(dicho, contains('https://mcp.Figma.com/mcp'));
      expect(dicho, contains('uno es de tu cuenta'));
      expect(dicho, startsWith('4 servidores MCP en la cuenta work:'));
    });

    test('una línea por servidor y ni una más', () {
      final dicho = contada([
        _mio('a'),
        _mio('b'),
      ], estado: 'Estado de las 10:41.');

      expect(
        dicho.split('\n'),
        hasLength(4),
        reason: 'el título, los dos, y el estado',
      );
    });

    test('sin ninguno, solo se dice eso', () {
      expect(
        LaListaDeMcp.comoSeCuenta(
          lista: const [],
          titulo: 'Esta cuenta no tiene ninguno.',
          comoEsta: (_) => 'da igual',
          deLaCuentaDicho: 'esto no debería salir',
        ),
        'Esta cuenta no tiene ninguno.',
      );
    });
  });

  group('la lista junta', () {
    test('con solo el archivo, son los del archivo', () {
      final lista = LaListaDeMcp.junta(delArchivo: [_mio('context7')]);

      expect(lista.map((s) => s.name), ['context7']);
      expect(LaListaDeMcp.deLaCuenta(lista), 0);
    });

    // El caso del reporte: cinco tuyos y quince de la cuenta, en una sola
    // lista y sin pulsar nada.
    test('lo recordado trae los de la cuenta, y salen todos', () {
      final lista = LaListaDeMcp.junta(
        delArchivo: [_mio('context7'), _mio('maestro')],
        recordados: [
          _mio('context7'),
          _deLaCuenta('Gmail'),
          _deLaCuenta('Slack'),
        ],
      );

      expect(lista.map((s) => s.name), [
        'context7',
        'maestro',
        'claude.ai Gmail',
        'claude.ai Slack',
      ]);
      expect(LaListaDeMcp.deLaCuenta(lista), 2);
    });

    // 🔴 **Lo recordado no puede añadir servidores tuyos.** Uno que quitaste
    // hace un minuto sigue en el recuerdo de hace una hora: si lo recordado
    // sumara, seguiría en pantalla —y con su botón de quitar puesto— hasta la
    // siguiente comprobación.
    test('y no resucita uno tuyo que ya quitaste', () {
      final lista = LaListaDeMcp.junta(
        delArchivo: [_mio('context7')],
        recordados: [_mio('context7'), _mio('el-que-quité')],
      );

      expect(lista.map((s) => s.name), ['context7']);
    });

    test('los de la cuenta van en orden y después de los tuyos', () {
      final lista = LaListaDeMcp.junta(
        delArchivo: [_mio('maestro')],
        recordados: [
          _deLaCuenta('Slack'),
          _deLaCuenta('Gmail'),
          _deLaCuenta('Atlassian Rovo'),
        ],
      );

      expect(lista.map((s) => s.name), [
        'maestro',
        'claude.ai Atlassian Rovo',
        'claude.ai Gmail',
        'claude.ai Slack',
      ], reason: 'sobre los tuyos se puede actuar; sobre los otros no');
    });

    test('lo comprobado sustituye a lo recordado, no se le suma', () {
      final lista = LaListaDeMcp.junta(
        delArchivo: [_mio('maestro')],
        recordados: [_deLaCuenta('Gmail'), _deLaCuenta('Granola')],
        comprobados: [_mio('maestro'), _deLaCuenta('Gmail')],
      );

      expect(lista.map((s) => s.name), [
        'maestro',
        'claude.ai Gmail',
      ], reason: 'un conector desconectado en claude.ai no puede seguir ahí');
    });

    test('y le pega la salud a los tuyos, que es la misma cosa vista de otra '
        'ventana', () {
      final lista = LaListaDeMcp.junta(
        delArchivo: [_mio('maestro'), _mio('g66')],
        comprobados: [
          _mio('maestro', estado: McpStatus.connected),
          _mio('g66', estado: McpStatus.failed),
        ],
      );

      expect(lista.first.status, McpStatus.connected);
      expect(lista.last.status, McpStatus.failed);
      expect(lista.map((s) => s.spec), [
        'npx -y maestro',
        'npx -y g66',
      ], reason: 'el destino sigue siendo el del archivo');
    });

    test('sin comprobar, los tuyos se quedan sin saber cómo están', () {
      final lista = LaListaDeMcp.junta(delArchivo: [_mio('maestro')]);

      expect(lista.single.status, McpStatus.unknown);
    });
  });
}
