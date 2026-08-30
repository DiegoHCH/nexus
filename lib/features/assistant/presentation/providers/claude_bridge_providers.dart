import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/i18n/language_preference.dart';
import 'package:nexus/features/artifacts/presentation/providers/artifacts_providers.dart';
import 'package:nexus/features/assistant/data/datasources/claude_cli_data_source.dart';
import 'package:nexus/features/assistant/data/repositories/claude_bridge_impl.dart';
import 'package:nexus/features/assistant/data/repositories/stays_awake_impl.dart';
import 'package:nexus/features/assistant/domain/repositories/stays_awake.dart';
import 'package:nexus/features/assistant/domain/repositories/claude_bridge.dart';
import 'package:nexus/features/assistant/data/datasources/conversation_memory_data_source.dart';
import 'package:nexus/features/assistant/data/repositories/conversation_memory_impl.dart';
import 'package:nexus/features/assistant/domain/repositories/conversation_memory.dart';
import 'package:nexus/features/assistant/domain/usecases/ask_claude.dart';
import 'package:nexus/features/assistant/domain/usecases/folder_errand_queue.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/workspace/domain/usecases/allowed_commands.dart';
import 'package:nexus/features/workspace/domain/usecases/blocked_commands.dart';
import 'package:nexus/features/workspace/domain/usecases/repo_from_instruction.dart';
import 'package:nexus/features/e2e/presentation/providers/raiz_de_los_flows_provider.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
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
  return AskClaude(
    ref.watch(claudeBridgeProvider),
    (instruction) async {
      final workspace = ref.read(workspaceControllerProvider);
      final folder = ref.read(conversationFolderProvider(conversationId));
      if (folder == null) return null;
      final paired = workspace.folders
          .where((item) => item.path == folder)
          .firstOrNull;

      // Con una raíz de varios repos, nombrar uno en el encargo coloca a Claude
      // dentro. Se guarda además de usarse, para que la barra enseñe dónde se
      // movió: un cambio de directorio invisible es de los que luego nadie
      // entiende al leer un commit.
      final repos = await ref.read(reposInsideProvider(folder).future);
      if (repos.length > 1) {
        final nombrado = RepoFromInstruction.resolve(instruction, repos);
        if (nombrado != null && nombrado != paired?.activeRepo) {
          await ref
              .read(workspaceControllerProvider.notifier)
              .setActiveRepo(folder, nombrado);
        }
      }
      final activo =
          ref
              .read(workspaceControllerProvider)
              .folders
              .where((item) => item.path == folder)
              .firstOrNull
              ?.workingDirectory ??
          folder;
      return (
        workingDirectory: activo,
        canEdit: workspace.permission.canWrite,
        // **Ninguna otra carpeta.** Antes viajaban todas las emparejadas como
        // `--add-dir` para que un repo pudiera leer sus reglas en una carpeta
        // hermana, y con varias conversaciones eso significaba que el trabajo de
        // un proyecto se metía en otro — se vio en vivo: un encargo sobre un repo
        // listando los archivos del otro. Si las reglas viven fuera del repo, la
        // solución es emparejar la carpeta padre, no abrirle la puerta a todo.
        extraDirectories: const <String>[],
        language: ref.read(stringsProvider).languageName,
        // Modelo, esfuerzo y cuenta salen de **la carpeta**: es la unidad que
        // organiza todo lo demás —memoria, contexto, archivo— y no había motivo
        // para que estos dos fueran la excepción global.
        disallowedTools: BlockedCommands.patterns(
          paired?.blockedCommands ?? const [],
        ),
        // **Descargar viene de serie**, y el resto lo pone la carpeta. Sin la
        // descarga, generar una imagen o traerse un archivo no sirve de nada:
        // el trabajo se hace y no se puede guardar. Va en la forma estrecha
        // —`curl -o`— y no en `curl` a secas, que autorizaría también
        // `curl -d @archivo`, o sea la puerta de salida.
        comandosPermitidos: [
          AllowedCommands.paraDescargar,
          ...AllowedCommands.patterns(paired?.allowedCommands ?? const []),
        ],
        constraintsNotice: AllowedCommands.comoSeDescarga(
          BlockedCommands.notice(paired?.blockedCommands ?? const []),
        ),
        model: paired?.claudeModel,
        effort: paired?.claudeEffort,
        claudeProfile: paired?.claudeProfile,
        artifactsFolder: ref.read(artifactsFolderProvider),
        // Solo cuando hay algo elegido —la carpeta declarada o la raíz común—. Sin
        // nada, vale `.maestro/`, que es la convención de Maestro y Claude ya conoce:
        // decirlo en cada encargo de cada proyecto sería ruido para quien no tiene
        // pruebas.
        carpetaDePruebas: _dondeVanLasPruebas(ref, paired),
      );
    },
    ref.watch(conversationMemoryProvider),
    ref.watch(folderErrandQueueProvider),
    ref.watch(staysAwakeProvider),
  );
});

/// La carpeta de pruebas que se le nombra al encargo, o `null` si no hay nada elegido.
///
/// Aparte del contexto porque decide **si se dice o no**, que es una regla y no un dato:
/// con `.maestro/` no hace falta decir nada, y con una carpeta elegida hace falta decirlo
/// o Claude escribe la prueba donde Nexus no mira.
String? _dondeVanLasPruebas(Ref ref, PairedFolder? paired) {
  if (paired == null) return null;
  final raiz = ref.read(raizDeLosFlowsProvider);
  final declarada = (paired.carpetaDePruebas ?? '').trim();
  if (declarada.isEmpty && (raiz == null || raiz.trim().isEmpty)) return null;
  return paired.pruebasEn(Platform.environment['HOME'] ?? '', raiz: raiz);
}

/// Uno solo para toda la app, por el mismo motivo que la cola: lleva la cuenta
/// de cuántos encargos hay en marcha, y esa cuenta cruza conversaciones.
final staysAwakeProvider = Provider<StaysAwake>((ref) => StaysAwakeImpl());

/// Una sola cola para toda la app, no una por conversación: su trabajo es
/// justamente coordinar entre conversaciones distintas.
final folderErrandQueueProvider = Provider<FolderErrandQueue>(
  (ref) => FolderErrandQueue(),
);
