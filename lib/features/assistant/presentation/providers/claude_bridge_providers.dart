import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/assistant/data/datasources/claude_cli_data_source.dart';
import 'package:nexus/features/assistant/data/repositories/claude_bridge_impl.dart';
import 'package:nexus/features/assistant/domain/repositories/claude_bridge.dart';
import 'package:nexus/features/assistant/domain/usecases/ask_claude.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

final claudeCliDataSourceProvider = Provider<ClaudeCliDataSource>(
  (ref) => const ClaudeCliDataSource(),
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
final askClaudeProvider = Provider<AskClaude>((ref) {
  return AskClaude(ref.watch(claudeBridgeProvider), () async {
    final workspace = ref.read(workspaceControllerProvider);
    final active = workspace.active;
    if (active == null) return null;
    return (
      workingDirectory: active.path,
      canEdit: workspace.permission.canWrite,
      // Las demás carpetas emparejadas viajan como `--add-dir`: es lo que
      // permite que un repo lea las reglas que viven en una carpeta hermana.
      extraDirectories: [
        for (final folder in workspace.folders)
          if (folder.path != active.path) folder.path,
      ],
    );
  });
});
