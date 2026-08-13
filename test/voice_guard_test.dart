import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/i18n/language_preference.dart';
import 'package:nexus/features/assistant/domain/repositories/conversation_memory.dart';
import 'package:nexus/features/assistant/presentation/providers/assistant_controller.dart';
import 'package:nexus/features/assistant/presentation/providers/claude_bridge_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/domain/entities/workspace.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FixedWorkspace extends WorkspaceController {
  _FixedWorkspace(this._value);

  final Workspace _value;

  @override
  Workspace build() => _value;
}

class _NoMemory implements ConversationMemory {
  const _NoMemory();

  @override
  Future<FolderMemory> read(String folderPath) async => const FolderMemory();

  @override
  Future<void> rememberSession(String folderPath, String sessionId) async {}

  @override
  Future<void> rememberPrompt(String folderPath, String prompt) async {}

  @override
  Future<void> forget(String folderPath) async {}
}

const conversationId = 'c1';
const folderPath = '/Users/alguien/repo';

ProviderContainer containerFor(FolderModality modality) {
  final container = ProviderContainer(
    overrides: [
      conversationFolderProvider(conversationId).overrideWithValue(folderPath),
      conversationMemoryProvider.overrideWithValue(const _NoMemory()),
      workspaceControllerProvider.overrideWith(
        () => _FixedWorkspace(
          Workspace(
            folders: [PairedFolder(path: folderPath, modality: modality)],
            activePath: folderPath,
          ),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // El guardia de i5, que es el que decide si tu voz sale de la máquina. Vive
  // en el código y no en un botón deshabilitado porque el atajo global se
  // saltaría el botón — y existe justo para usarse sin mirar la pantalla.
  test('una carpeta en solo texto no abre el micrófono', () async {
    final container = containerFor(FolderModality.textOnly);
    final controller = container.read(
      assistantControllerProvider(conversationId).notifier,
    );

    await controller.toggleVoice();

    final state = container.read(assistantControllerProvider(conversationId));
    expect(state.voiceActive, isFalse);
    // Contra el diccionario que la app tenga puesto, no contra el español a
    // pelo: en las pruebas el idioma del sistema es inglés, y clavar el texto
    // en un idioma haría fallar la prueba por traducir bien.
    expect(
      state.errorMessage,
      container.read(stringsProvider).textOnlyFolder('repo'),
    );
  });

  test('sin carpeta emparejada tampoco, y lo dice', () async {
    final container = ProviderContainer(
      overrides: [
        conversationFolderProvider(conversationId).overrideWithValue(null),
        conversationMemoryProvider.overrideWithValue(const _NoMemory()),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(
      assistantControllerProvider(conversationId).notifier,
    );
    await controller.toggleVoice();

    final state = container.read(assistantControllerProvider(conversationId));
    expect(state.voiceActive, isFalse);
    expect(state.errorMessage, isNotNull);
  });

  test('el aviso se puede quitar de en medio', () async {
    final container = containerFor(FolderModality.textOnly);
    final controller = container.read(
      assistantControllerProvider(conversationId).notifier,
    );

    await controller.toggleVoice();
    controller.dismissError();

    expect(
      container.read(assistantControllerProvider(conversationId)).errorMessage,
      isNull,
    );
  });
}
