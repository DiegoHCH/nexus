import 'dart:async';
import 'package:nexus/features/superpowers/presentation/providers/superpowers_providers.dart';
import 'package:nexus/features/superpowers/domain/entities/mcp_server.dart';
import 'package:nexus/features/superpowers/data/datasources/mcp_data_source.dart';
import 'package:nexus/features/superpowers/data/datasources/el_recuerdo_de_los_mcp.dart';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/i18n/language_preference.dart';
import 'package:nexus/features/assistant/domain/entities/claude_event.dart';
import 'package:nexus/features/assistant/domain/entities/peticion_de_permiso.dart';
import 'package:nexus/features/assistant/domain/repositories/conversation_memory.dart';
import 'package:nexus/features/assistant/domain/usecases/ask_claude.dart';
import 'package:nexus/features/assistant/domain/usecases/los_comandos_de_la_casa.dart';
import 'package:nexus/features/assistant/presentation/providers/assistant_controller.dart';
import 'package:nexus/features/assistant/presentation/providers/claude_bridge_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/assistant/presentation/state/chat_message.dart';
import 'package:nexus/features/history/data/datasources/local_conversation_store.dart';
import 'package:nexus/features/history/domain/entities/conversation_record.dart';
import 'package:nexus/features/history/domain/entities/conversation_summary.dart';
import 'package:nexus/features/history/presentation/providers/archive_providers.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/domain/entities/workspace.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// **La ayuda y el olvido, escribiéndolos en la conversación.**
///
/// 🔴 Nace de una pregunta que no tenía respuesta dentro de la app: «qué
/// comandos puedo usar en Nexus, como el `/clear` de Claude». Lo que se prueba
/// aquí es lo que el enrutado no puede decir solo: que la lista **se pinta** y
/// que el olvido **olvida de verdad** — y que ninguno de los dos gasta un
/// encargo, que es lo que costaría preguntárselo a Claude.
const _id = 'c1';
const _carpeta = '/Users/alguien/General';

class _Claude implements AskClaude {
  _Claude({List<String> mcpCaidos = const []}) : mcpCaidos = [...mcpCaidos];

  final pedidos = <String>[];

  /// Los servidores MCP que el arranque dice que no levantaron. El CLI manda
  /// este parte en **cada** encargo, que es justo lo que había que dejar de
  /// repetir en pantalla.
  final List<String> mcpCaidos;

  @override
  Stream<ClaudeEvent> call(
    String instruction, {
    bool remember = true,
    bool allowWrites = true,
    Future<RespuestaDePermiso> Function(PeticionDePermiso)? alPedirPermiso,
  }) async* {
    pedidos.add(instruction);
    if (mcpCaidos.isNotEmpty) yield ClaudeMcpCaido(mcpCaidos);
    yield const ClaudeTextDelta('ya está');
    yield const ClaudeTurnCompleted(result: 'ya está');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Una memoria que solo apunta lo que se le manda olvidar. Entera y no con
/// `noSuchMethod`: el controlador la lee al construirse, y un doble a medias
/// falla por una puerta que no tiene nada que ver con lo que se prueba.
class _Memoria implements ConversationMemory {
  final olvidadas = <String>[];

  @override
  Future<void> forget(String folderPath) async => olvidadas.add(folderPath);

  @override
  Future<FolderMemory> read(String folderPath, {String? claudeProfile}) async =>
      const FolderMemory();
  @override
  Future<void> rememberSession(
    String folderPath,
    String sessionId, {
    String? claudeProfile,
  }) async {}
  @override
  Future<void> rememberPrompt(String folderPath, String prompt) async {}
  @override
  Future<void> rememberPermissionMode(
    String folderPath,
    String mode, {
    String? claudeProfile,
  }) async {}
}

/// Lo que hay puesto en la cuenta, sin salir a preguntarle al CLI: `check` no
/// se llama en estas pruebas —tarda casi un minuto— y por eso devuelve nulo.
class _Mcp extends McpDataSource {
  const _Mcp(this.servidores);

  final List<McpServer> servidores;

  @override
  Future<List<McpServer>> list(String configDir) async => servidores;

  @override
  Future<List<McpServer>?> check(String configDir) async => null;
}

class _SinAlmacen implements LocalConversationStore {
  const _SinAlmacen();
  @override
  Future<void> save(ConversationRecord record) async {}
  @override
  Future<List<ConversationSummary>> list(String folderPath) async => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Espacio extends WorkspaceController {
  @override
  Workspace build() => Workspace(
    folders: [PairedFolder(path: _carpeta, modality: FolderModality.voice)],
    activePath: _carpeta,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late _Claude claude;
  late _Memoria memoria;
  late Directory recuerdos;

  setUp(() => recuerdos = Directory.systemTemp.createTempSync('mcp_chat'));
  tearDown(() => recuerdos.deleteSync(recursive: true));

  Future<void> vueltas() async {
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  ProviderContainer contenedor({List<String> mcpCaidos = const []}) {
    claude = _Claude(mcpCaidos: mcpCaidos);
    memoria = _Memoria();
    final c = ProviderContainer(
      overrides: [
        conversationFolderProvider(_id).overrideWithValue(_carpeta),
        conversationMemoryProvider.overrideWithValue(memoria),
        workspaceControllerProvider.overrideWith(_Espacio.new),
        localConversationStoreProvider.overrideWithValue(const _SinAlmacen()),
        askClaudeProvider(_id).overrideWithValue(claude),
        mcpDataSourceProvider.overrideWithValue(
          const _Mcp([
            McpServer(name: 'maestro', spec: 'maestro mcp'),
            McpServer(
              name: 'claude.ai Gmail',
              spec: 'https://gmailmcp.googleapis.com/mcp/v1',
              fromAccount: true,
            ),
          ]),
        ),
        // El recuerdo, a una carpeta temporal: leerlo del soporte de la app
        // pasa por un canal de plataforma que en una prueba no contesta.
        elRecuerdoDeLosMcpProvider.overrideWithValue(
          ElRecuerdoDeLosMcp(carpeta: recuerdos),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  List<ChatMessage> mensajesDe(ProviderContainer c) =>
      c.read(assistantControllerProvider(_id)).messages;

  test('«/ayuda» pinta la lista, y no gasta un encargo', () async {
    final c = contenedor();

    await c.read(assistantControllerProvider(_id).notifier).submit('/ayuda');
    await vueltas();

    final mensajes = mensajesDe(c);
    expect(mensajes.first.text, '/ayuda', reason: 'lo que se escribió se ve');
    expect(mensajes.last.author, ChatAuthor.nexus);
    // Los textos se leen del contenedor: el idioma se elige en Ajustes y esta
    // prueba no manda en eso.
    expect(mensajes.last.text, startsWith(c.read(stringsProvider).ayudaTitulo));
    // Y están todos: la lista sale del catálogo, no de un texto a mano.
    for (final comando in ElComandoDeLaCasa.values) {
      expect(
        mensajes.last.text,
        contains(comando.comoSeEscribe),
        reason: comando.name,
      );
    }
    expect(
      claude.pedidos,
      isEmpty,
      reason: 'preguntar qué comandos hay no es trabajo para Claude',
    );
  });

  test('«/clear» olvida la sesión de esta carpeta y lo dice', () async {
    final c = contenedor();

    await c.read(assistantControllerProvider(_id).notifier).submit('/clear');
    await vueltas();

    expect(memoria.olvidadas, [
      _carpeta,
    ], reason: 'el olvido es de la carpeta, que es donde vive la sesión');
    // Una pantalla que no cambia se lee como que el comando no hizo nada — y
    // hay que aclarar que lo escrito sigue estando.
    expect(mensajesDe(c).last.text, contains('General'));
    expect(claude.pedidos, isEmpty);
  });

  // 🔴 **Pedido con la referencia delante:** «quisiera escribir el `/mcp` y que
  // me mostrara el listado de MCP en el chat, así como se hace en el CLI, con
  // su conectado o desconectado».
  test(
    '«/mcp» cuenta los servidores de la cuenta, sin gastar un encargo',
    () async {
      final c = contenedor();

      await c.read(assistantControllerProvider(_id).notifier).submit('/mcp');
      await vueltas();

      final dicho = mensajesDe(c).last;
      expect(dicho.author, ChatAuthor.nexus);
      expect(dicho.text, contains('maestro'));
      expect(dicho.text, contains('claude.ai Gmail'));
      // Sin comprobar todavía se dice así, en vez de callarlo o inventarlo.
      expect(dicho.text, contains(c.read(stringsProvider).mcpSinComprobar));
      // Y se dice cuántos son de la cuenta, que no se quitan desde aquí.
      expect(dicho.text, contains(c.read(stringsProvider).mcpDeLaCuenta(1)));
      expect(
        claude.pedidos,
        isEmpty,
        reason: 'preguntar qué MCP hay puestos no es trabajo para Claude',
      );
    },
  );

  // 🔴 **Reportado por otra persona con captura:** «cada vez que hago un prompt
  // esto salta» — el aviso de los servidores MCP que no arrancaron. El parte
  // del CLI viene en **cada** encargo, así que un gateway caído pintaba el
  // mismo aviso encima de cada respuesta. Un aviso que se repite deja de
  // avisar: se cierra sin leer.
  group('el aviso de los MCP caídos', () {
    test('se dice una vez y no en cada encargo', () async {
      final c = contenedor(mcpCaidos: ['figma-console', 'docs-context']);
      final controlador = c.read(assistantControllerProvider(_id).notifier);

      await controlador.submit('lo primero');
      await vueltas();
      expect(
        c.read(assistantControllerProvider(_id)).notice,
        contains('figma-console'),
        reason: 'la primera vez sí: es información nueva',
      );

      // Se cierra, como haría cualquiera, y se manda otro encargo.
      controlador.dismissNotice();
      await controlador.submit('lo segundo');
      await vueltas();

      expect(
        c.read(assistantControllerProvider(_id)).notice,
        isNull,
        reason: 'los mismos caídos no son noticia dos veces',
      );
    });

    // Que caiga otro **sí** es nuevo, y por eso se guarda el conjunto y no un
    // booleano.
    test('pero si cae otro, se vuelve a decir', () async {
      final c = contenedor(mcpCaidos: ['figma-console']);
      final controlador = c.read(assistantControllerProvider(_id).notifier);

      await controlador.submit('lo primero');
      await vueltas();
      controlador.dismissNotice();

      claude.mcpCaidos.add('docs-context');
      await controlador.submit('lo segundo');
      await vueltas();

      expect(
        c.read(assistantControllerProvider(_id)).notice,
        contains('docs-context'),
      );
    });
  });

  // La otra mitad del enrutado, vista desde aquí: lo que no es un comando
  // sigue siendo trabajo.
  test('y una frase normal sigue yendo a Claude', () async {
    final c = contenedor();

    await c
        .read(assistantControllerProvider(_id).notifier)
        .submit('mira el historial');
    await vueltas();

    expect(claude.pedidos, ['mira el historial']);
  });
}
