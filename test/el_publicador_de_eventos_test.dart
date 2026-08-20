import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/entities/conversation.dart';
import 'package:nexus/features/assistant/domain/repositories/conversation_memory.dart';
import 'package:nexus/features/assistant/presentation/providers/assistant_controller.dart';
import 'package:nexus/features/assistant/presentation/providers/claude_bridge_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/remote/domain/event_bridge.dart';
import 'package:nexus/features/remote/domain/event_log.dart';
import 'package:nexus/features/remote/presentation/event_publisher.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/domain/entities/workspace.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:nexus_protocol/nexus_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

// El enganche entre el estado de la app y el puente.
//
// Se prueba **con Riverpod de verdad y sin socket**: lo que puede romperse aquí es la
// suscripción —a qué se escucha, cuándo se deja de escuchar— y eso no se ve con un
// doble del contenedor. El puente ya está probado aparte, así que aquí solo importa
// que le llegue lo que tiene que llegarle.

const carpeta = '/Users/alguien/repo';

class _ListaControlable extends ConversationsController {
  _ListaControlable(this._inicial);

  final Conversations _inicial;

  @override
  Conversations build() => _inicial;

  void poner(Conversations otras) => state = otras;
}

class _FixedWorkspace extends WorkspaceController {
  _FixedWorkspace(this._value);

  final Workspace _value;

  @override
  Workspace build() => _value;
}

class _SinMemoria implements ConversationMemory {
  const _SinMemoria();

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
  Future<void> forget(String folderPath) async {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late List<Event> publicados;
  late List<void Function()> ventanas;
  late EventBridge puente;

  /// Cierra las ventanas de agrupado abiertas.
  void pasarElTiempo() {
    final abiertas = [...ventanas];
    ventanas.clear();
    for (final cerrar in abiertas) {
      cerrar();
    }
  }

  /// Monta el contenedor con una lista de conversaciones controlable a mano.
  (ProviderContainer, _ListaControlable, EventPublisher) montar({
    List<String> ids = const ['c1'],
  }) {
    publicados = [];
    ventanas = [];
    puente = EventBridge(
      log: EventLog(),
      publicar: publicados.add,
      programar: (_, cerrar) => ventanas.add(cerrar),
    );

    final lista = _ListaControlable(
      Conversations(
        items: [
          for (final id in ids) Conversation(id: id, folderPath: carpeta),
        ],
        focusedId: ids.isEmpty ? null : ids.first,
      ),
    );

    final publicador = Provider<EventPublisher>(
      (ref) => EventPublisher(ref: ref, bridge: puente),
    );

    final c = ProviderContainer(
      overrides: [
        conversationsProvider.overrideWith(() => lista),
        conversationMemoryProvider.overrideWithValue(const _SinMemoria()),
        for (final id in ['c1', 'c2'])
          conversationFolderProvider(id).overrideWithValue(carpeta),
        workspaceControllerProvider.overrideWith(
          () => _FixedWorkspace(
            Workspace(
              folders: const [
                // En solo texto a propósito: es lo que permite provocar un cambio de
                // estado de verdad —el aviso del guardia de voz— sin lanzar a Claude.
                PairedFolder(path: carpeta, modality: FolderModality.textOnly),
              ],
              activePath: carpeta,
            ),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    return (c, lista, c.read(publicador));
  }

  List<Event> deTipo(String kind) =>
      publicados.where((e) => e.kind == kind).toList();

  test('al arrancar cuenta lo que ya hay, sin esperar a que cambie', () async {
    // Sin `fireImmediately`, una conversación quieta no existiría para el teléfono
    // hasta que alguien la tocara — y quien acaba de conectar necesita el estado de
    // ahora, no el del próximo cambio.
    final (_, _, publicador) = montar();
    publicador.arrancar();
    pasarElTiempo();

    expect(publicados, isNotEmpty);
    expect(publicados.map((e) => e.data['conversation']).toSet(), {'c1'});
  });

  test('un cambio de estado de verdad llega como evento', () async {
    final (c, _, publicador) = montar();
    publicador.arrancar();
    pasarElTiempo();
    publicados.clear();

    // El guardia de i5: una carpeta en solo texto no abre el micrófono y lo dice.
    // Es un cambio de estado real, pasando por el controlador de la app.
    await c.read(assistantControllerProvider('c1').notifier).toggleVoice();
    pasarElTiempo();

    final error = deTipo('error').single;
    expect(error.data['conversation'], 'c1');
    expect(error.data['message'], isNotNull);
  });

  test('las tres conversaciones se escuchan, no solo la del foco', () async {
    // La voz sirve a la que tiene el foco, pero el trabajo sigue en las demás. Un
    // teléfono que solo viera la enfocada se perdería justo lo que pasa de fondo.
    final (_, _, publicador) = montar(ids: ['c1', 'c2']);
    publicador.arrancar();
    pasarElTiempo();

    expect(publicados.map((e) => e.data['conversation']).toSet(), {'c1', 'c2'});
  });

  test('cerrar una conversación se avisa y se deja de escuchar', () async {
    final (c, lista, publicador) = montar(ids: ['c1', 'c2']);
    publicador.arrancar();
    pasarElTiempo();
    publicados.clear();

    lista.poner(
      const Conversations(
        items: [Conversation(id: 'c1', folderPath: carpeta)],
        focusedId: 'c1',
      ),
    );

    expect(deTipo('closed').single.data['conversation'], 'c2');

    // Y ya no se escucha: un cambio en la cerrada no genera nada. Sin esto, el
    // teléfono recibiría eventos de una conversación que ya quitó de la pantalla.
    publicados.clear();
    await c.read(assistantControllerProvider('c2').notifier).toggleVoice();
    pasarElTiempo();
    expect(publicados, isEmpty);
  });

  test('parar deja de contar, y no deja ventanas abiertas', () async {
    final (c, _, publicador) = montar();
    publicador.arrancar();
    pasarElTiempo();

    publicador.parar();
    publicados.clear();
    await c.read(assistantControllerProvider('c1').notifier).toggleVoice();
    pasarElTiempo();

    // Apagar el canal con una ventana abierta acabaría difundiendo sobre un socket
    // ya cerrado.
    expect(publicados, isEmpty);
    expect(puente.ventanasAbiertas, 0);
  });
}
