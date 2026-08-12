import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/assistant/data/datasources/claude_cli_data_source.dart';
import 'package:nexus/features/assistant/data/repositories/claude_bridge_impl.dart';
import 'package:nexus/features/assistant/domain/repositories/claude_bridge.dart';
import 'package:nexus/features/assistant/data/datasources/conversation_memory_data_source.dart';
import 'package:nexus/features/assistant/data/repositories/conversation_memory_impl.dart';
import 'package:nexus/features/assistant/domain/repositories/conversation_memory.dart';
import 'package:nexus/features/assistant/domain/usecases/ask_claude.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

final claudeCliDataSourceProvider = Provider<ClaudeCliDataSource>(
  (ref) => const ClaudeCliDataSource(),
);

final conversationMemoryProvider = Provider<ConversationMemory>(
  (ref) => const ConversationMemoryImpl(ConversationMemoryDataSource()),
);

final claudeBridgeProvider = Provider<ClaudeBridge>(
  (ref) => ClaudeBridgeImpl(ref.watch(claudeCliDataSourceProvider)),
);

/// Aquí se cose `assistant` con `workspace`: el puente pide «dónde y con qué
/// permiso» y esta capa se lo resuelve, sin que ninguna de las dos features
/// tenga que conocer a la otra.
///
/// Se lee en el momento de cada encargo —no al construir el provider— para que
/// mover el interruptor de permisos valga desde el turno siguiente.
final askClaudeProvider = Provider.family<AskClaude, String>((
  ref,
  conversationId,
) {
  return AskClaude(ref.watch(claudeBridgeProvider), () async {
    final workspace = ref.read(workspaceControllerProvider);
    final folder = ref.read(conversationFolderProvider(conversationId));
    if (folder == null) return null;
    return (
      workingDirectory: folder,
      canEdit: workspace.permission.canWrite,
      // **Ninguna otra carpeta.** Antes viajaban todas las emparejadas como
      // `--add-dir` para que un repo pudiera leer sus reglas en una carpeta
      // hermana, y con varias conversaciones eso significaba que el trabajo de
      // un proyecto se metía en otro — se vio en vivo: un encargo sobre un repo
      // listando los archivos del otro. Si las reglas viven fuera del repo, la
      // solución es emparejar la carpeta padre, no abrirle la puerta a todo.
      extraDirectories: const <String>[],
    );
  }, ref.watch(conversationMemoryProvider));
});
