import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/i18n/language_preference.dart';
import 'package:nexus/features/artifacts/presentation/providers/artifacts_providers.dart';
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

class _FixedArtifacts extends ArtifactsFolder {
  _FixedArtifacts(this._value);

  final String? _value;

  @override
  String? build() => _value;
}

class _NoMemory implements ConversationMemory {
  const _NoMemory();

  @override
  Future<FolderMemory> read(String folderPath, {String? claudeProfile}) async => const FolderMemory();

  @override
  Future<void> rememberSession(String folderPath, String sessionId, {String? claudeProfile}) async {}

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

  // El único hueco que le quedaba a i5, reportado preguntando: «si está en solo
  // texto, ¿puede que algo viaje igual?».
  //
  // La respuesta era casi no. Las demás carpetas emparejadas **no** viajan
  // —`extraDirectories` va vacío a propósito, y hay un comentario contando que
  // antes sí y se vio un encargo listando los archivos del otro repo—, pero la
  // carpeta de artefactos sí viaja en todos los encargos como `--add-dir`.
  group('la carpeta de artefactos no puede ser una puerta', () {
    ProviderContainer conCajon(String artifacts, FolderModality modalidadCajon) {
      const cajonPath = '/Users/alguien/salida';
      final container = ProviderContainer(
        overrides: [
          conversationFolderProvider(conversationId).overrideWithValue(folderPath),
          conversationMemoryProvider.overrideWithValue(const _NoMemory()),
          artifactsFolderProvider.overrideWith(() => _FixedArtifacts(artifacts)),
          workspaceControllerProvider.overrideWith(
            () => _FixedWorkspace(
              Workspace(
                folders: [
                  // La conversación trabaja en una carpeta **con voz**: el
                  // guardia de antes no salta, y este es el que tiene que saltar.
                  const PairedFolder(
                    path: folderPath,
                    modality: FolderModality.voice,
                  ),
                  PairedFolder(path: cajonPath, modality: modalidadCajon),
                ],
                activePath: folderPath,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('si el cajón es de solo texto, la voz no se abre', () async {
      final container = conCajon(
        '/Users/alguien/salida',
        FolderModality.textOnly,
      );
      final controller = container.read(
        assistantControllerProvider(conversationId).notifier,
      );

      await controller.toggleVoice();

      final state = container.read(assistantControllerProvider(conversationId));
      expect(state.voiceActive, isFalse);
      expect(
        state.errorMessage,
        container.read(stringsProvider).textOnlyArtifactsFolder('salida'),
      );
    });

    test('y tampoco si está en una subcarpeta suya', () async {
      // `--add-dir` da acceso al subárbol entero, así que el cajón metido dentro
      // abre la misma puerta que puesto en la raíz.
      final container = conCajon(
        '/Users/alguien/salida/mockups',
        FolderModality.textOnly,
      );
      final controller = container.read(
        assistantControllerProvider(conversationId).notifier,
      );

      await controller.toggleVoice();

      expect(
        container.read(assistantControllerProvider(conversationId)).errorMessage,
        container.read(stringsProvider).textOnlyArtifactsFolder('salida'),
      );
    });

    // Lo de «con el cajón en modo voz no estorba» se comprueba abajo, en la
    // prueba pura: aquí no se puede. Al no saltar el guardia, `toggleVoice`
    // **abre la sesión de verdad** —micrófono, WebSocket— y la prueba acaba
    // reventando por un camino que no tiene nada que ver con lo que afirma.
  });

  group('quién contiene a quién, sin providers', () {
    final cajon = Workspace(
      folders: const [
        PairedFolder(path: '/a/privado', modality: FolderModality.textOnly),
        PairedFolder(path: '/a/publico', modality: FolderModality.voice),
      ],
    );

    test('la misma carpeta, y sus hijas', () {
      expect(cajon.textOnlyOwnerOf('/a/privado')?.name, 'privado');
      expect(cajon.textOnlyOwnerOf('/a/privado/dentro')?.name, 'privado');
      expect(cajon.textOnlyOwnerOf('/a/privado/')?.name, 'privado');
    });

    test('pero no una vecina con el mismo prefijo', () {
      // `/a/privadoX` empieza por `/a/privado` y **no** está dentro. Comparar
      // cadenas a pelo diría que sí y negaría la voz sin motivo.
      expect(cajon.textOnlyOwnerOf('/a/privadoX'), isNull);
    });

    test('ni las que permiten voz, ni la nada', () {
      expect(cajon.textOnlyOwnerOf('/a/publico'), isNull);
      expect(cajon.textOnlyOwnerOf(null), isNull);
      expect(cajon.textOnlyOwnerOf(''), isNull);
    });
  });
}
