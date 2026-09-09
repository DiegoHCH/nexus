import 'dart:async';

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
  final pedidos = <String>[];

  @override
  Stream<ClaudeEvent> call(
    String instruction, {
    bool remember = true,
    bool allowWrites = true,
    Future<RespuestaDePermiso> Function(PeticionDePermiso)? alPedirPermiso,
  }) async* {
    pedidos.add(instruction);
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

  Future<void> vueltas() async {
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  ProviderContainer contenedor() {
    claude = _Claude();
    memoria = _Memoria();
    final c = ProviderContainer(
      overrides: [
        conversationFolderProvider(_id).overrideWithValue(_carpeta),
        conversationMemoryProvider.overrideWithValue(memoria),
        workspaceControllerProvider.overrideWith(_Espacio.new),
        localConversationStoreProvider.overrideWithValue(const _SinAlmacen()),
        askClaudeProvider(_id).overrideWithValue(claude),
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
