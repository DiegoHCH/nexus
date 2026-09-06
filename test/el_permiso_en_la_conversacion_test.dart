import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/nexus_theme.dart';
import 'package:nexus/core/i18n/language_preference.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/assistant/domain/entities/claude_event.dart';
import 'package:nexus/features/assistant/domain/entities/peticion_de_permiso.dart';
import 'package:nexus/features/assistant/domain/repositories/claude_bridge.dart';
import 'package:nexus/features/assistant/domain/repositories/conversation_memory.dart';
import 'package:nexus/features/assistant/presentation/providers/assistant_controller.dart';
import 'package:nexus/features/assistant/presentation/providers/claude_bridge_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/assistant/presentation/state/chat_message.dart';
import 'package:nexus/features/assistant/presentation/widgets/chat_panel.dart';
import 'package:nexus/features/history/data/datasources/local_conversation_store.dart';
import 'package:nexus/features/history/domain/entities/conversation_record.dart';
import 'package:nexus/features/history/domain/entities/conversation_summary.dart';
import 'package:nexus/features/history/presentation/providers/archive_providers.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/domain/entities/workspace.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const conversationId = 'c1';
const folderPath = '/Users/alguien/General';

const _peticion = PeticionDePermiso(
  id: 'req-1',
  herramienta: 'Write',
  nombreVisible: 'Write',
  entrada: {'file_path': '/tmp/a.txt', 'content': 'hola'},
  descripcion: 'a.txt',
  sugerencias: [
    {'type': 'setMode', 'mode': 'acceptEdits', 'destination': 'session'},
  ],
);

/// El permiso se pregunta **en la conversación**, no en una ventana.
///
/// Era una modal y se cambió a petición: una ventana obliga a contestar antes
/// de seguir, tapa lo que estabas leyendo y no deja mirar el resto del hilo
/// para decidir. El precio de moverlo al chat es que **se puede ignorar**, y
/// eso es justo lo que obliga a las dos garantías que se prueban aquí: que
/// mientras hay una en pie se dice, y que ninguna se queda sin contestar.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  ({ProviderContainer container, _PuenteQuePregunta puente}) montar({
    FilePermission permiso = FilePermission.canEdit,
  }) {
    final puente = _PuenteQuePregunta();
    final container = ProviderContainer(
      overrides: [
        conversationFolderProvider(
          conversationId,
        ).overrideWithValue(folderPath),
        conversationMemoryProvider.overrideWithValue(const _NoMemory()),
        workspaceControllerProvider.overrideWith(() => _Workspace(permiso)),
        claudeBridgeProvider.overrideWithValue(puente),
        // Mismo motivo que en `el_orbe_espera_la_respuesta_test`: guardar de
        // verdad sale a buscar `path_provider`, que en una prueba pura no
        // existe, y se queda en vuelo tras el `dispose`.
        localConversationStoreProvider.overrideWithValue(const _SinDisco()),
        conversationArchiveProvider.overrideWith((ref) async => null),
      ],
    );
    addTearDown(container.dispose);
    return (container: container, puente: puente);
  }

  /// Espera **a la condición**, no a un número de vueltas.
  ///
  /// Con `pumpEventQueue()` a secas estas pruebas eran verdes sueltas y rojas
  /// en la suite entera: el encargo pasa por varios saltos asíncronos antes de
  /// llegar a preguntar, y con la máquina cargada veinte vueltas se quedaban
  /// cortas. Un fallo que solo aparece cuando el CI va lento es peor que uno
  /// que aparece siempre.
  Future<void> hasta(bool Function() listo) async {
    for (var vuelta = 0; vuelta < 200 && !listo(); vuelta++) {
      await pumpEventQueue(times: 1);
    }
    expect(listo(), isTrue, reason: 'no llegó a cumplirse a tiempo');
  }

  AssistantController mando(ProviderContainer c) =>
      c.read(assistantControllerProvider(conversationId).notifier);
  ChatMessage? elPermiso(ProviderContainer c) => c
      .read(assistantControllerProvider(conversationId))
      .messages
      .where((m) => m.permiso != null)
      .lastOrNull;

  Future<({ProviderContainer container, _PuenteQuePregunta puente})>
  preguntando() async {
    final m = montar();
    unawaited(mando(m.container).submit('haz algo'));
    await hasta(() => elPermiso(m.container) != null);
    return m;
  }

  group('la pregunta es un turno', () {
    test('aparece en la conversación, sin contestar', () async {
      final m = await preguntando();

      final mensaje = elPermiso(m.container);
      expect(mensaje, isNotNull);
      expect(mensaje!.permiso!.id, 'req-1');
      expect(mensaje.decision, isNull);
      expect(mensaje.esperaPermiso, isTrue);
      // Lo que la modal daba gratis: que no se pueda pasar por alto en
      // silencio. Aquí hay que decirlo.
      expect(
        m.container.read(assistantControllerProvider(conversationId)).notice,
        m.container.read(stringsProvider).permisoEnEspera,
      );
    });

    test('conceder contesta y deja dicho qué se decidió', () async {
      final m = await preguntando();
      mando(m.container).responderPermiso('req-1', DecisionDePermiso.concedido);
      await hasta(() => m.puente.contestado != null);

      expect(m.puente.contestado, isA<PermisoConcedido>());
      expect(
        (m.puente.contestado! as PermisoConcedido).permisosNuevos,
        isEmpty,
      );
      expect(elPermiso(m.container)!.decision, DecisionDePermiso.concedido);
      expect(
        m.container.read(assistantControllerProvider(conversationId)).notice,
        isNull,
      );
    });

    test('permitir todo devuelve la sugerencia del CLI', () async {
      final m = await preguntando();
      mando(
        m.container,
      ).responderPermiso('req-1', DecisionDePermiso.concedidoTodo);
      await hasta(() => m.puente.contestado != null);

      expect(
        (m.puente.contestado! as PermisoConcedido).permisosNuevos,
        _peticion.sugerencias,
      );
    });

    test('negar llega al modelo con un motivo', () async {
      final m = await preguntando();
      mando(m.container).responderPermiso('req-1', DecisionDePermiso.denegado);
      await hasta(() => m.puente.contestado != null);

      expect(m.puente.contestado, isA<PermisoDenegado>());
      expect((m.puente.contestado! as PermisoDenegado).motivo, isNotEmpty);
    });

    // 🔴 La garantía que sostiene todo lo demás: al otro lado hay un proceso
    // detenido. Una pregunta que se queda sin contestar no es una pausa, es el
    // encargo colgado — y parar tiene que soltarla.
    test('parar contesta a la que quedaba en pie', () async {
      final m = await preguntando();
      mando(m.container).stopWork();
      await hasta(() => m.puente.contestado != null);

      expect(m.puente.contestado, isA<PermisoDenegado>());
      expect(elPermiso(m.container)!.decision, DecisionDePermiso.cancelado);
      expect(
        m.container.read(assistantControllerProvider(conversationId)).notice,
        isNull,
      );
    });

    test('cerrar la conversación también la suelta', () async {
      final m = await preguntando();
      m.container.dispose();
      await hasta(() => m.puente.contestado != null);

      expect(m.puente.contestado, isA<PermisoDenegado>());
    });

    // Contestar dos veces lo mismo —doble clic, el teclado— no puede reventar:
    // completar un `Completer` ya completado lanza.
    test('contestar dos veces no revienta', () async {
      final m = await preguntando();
      final mando1 = mando(m.container);
      mando1.responderPermiso('req-1', DecisionDePermiso.concedido);
      mando1.responderPermiso('req-1', DecisionDePermiso.denegado);
      await hasta(() => m.puente.contestado != null);

      expect(m.puente.contestado, isA<PermisoConcedido>());
    });
  });

  // La otra mitad de la regla: una carpeta de solo lectura **no pregunta**.
  // Ese modo promete que no se toca el disco, y convertirlo en un botón sería
  // cambiar la promesa por un clic.
  test('la carpeta de solo lectura no pregunta', () async {
    final m = montar(permiso: FilePermission.readOnly);
    unawaited(mando(m.container).submit('haz algo'));
    // Aquí se espera a que el encargo **termine**, que es lo que demuestra que
    // pasó de largo sin preguntar. Esperar a la pregunta sería esperar a algo
    // que no va a ocurrir.
    await hasta(() => m.puente.termino);
    expect(elPermiso(m.container), isNull);
    expect(m.puente.leDieronAQuienPreguntar, isFalse);
  });

  group('cómo se ve en el panel', () {
    Future<List<(String, DecisionDePermiso)>> pintar(
      WidgetTester tester,
      ChatMessage mensaje,
    ) async {
      final pulsado = <(String, DecisionDePermiso)>[];
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: NexusTheme.dark(),
            builder: (context, child) =>
                StringsScope(strings: const NexusStringsEs(), child: child!),
            home: Scaffold(
              body: ChatPanel(
                messages: [mensaje],
                onPermiso: (id, d) => pulsado.add((id, d)),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return pulsado;
    }

    testWidgets('enseña el argumento y las tres salidas', (tester) async {
      final strings = const NexusStringsEs();
      final pulsado = await pintar(
        tester,
        const ChatMessage(
          author: ChatAuthor.nexus,
          text: '¿Le dejas usar Write?',
          permiso: _peticion,
        ),
      );

      // El argumento, que es lo que se aprueba de verdad.
      expect(find.text('a.txt'), findsOneWidget);
      expect(find.text(strings.permisoEscribe), findsOneWidget);

      await tester.tap(find.text(strings.permisoConcederTodo));
      expect(pulsado, [('req-1', DecisionDePermiso.concedidoTodo)]);
    });

    testWidgets('contestado deja el rastro y quita los botones', (
      tester,
    ) async {
      final strings = const NexusStringsEs();
      await pintar(
        tester,
        const ChatMessage(
          author: ChatAuthor.nexus,
          text: '¿Le dejas usar Write?',
          permiso: _peticion,
          decision: DecisionDePermiso.denegado,
        ),
      );

      expect(find.text(strings.permisoDichoDenegado), findsOneWidget);
      expect(find.text(strings.permisoConceder), findsNothing);
      expect(find.text(strings.permisoConcederTodo), findsNothing);
    });

    // Sin sugerencia que aplicar, «Permitir todo» prometería dejar de preguntar
    // sin poder cumplirlo.
    testWidgets('sin sugerencia no se ofrece permitir todo', (tester) async {
      await pintar(
        tester,
        const ChatMessage(
          author: ChatAuthor.nexus,
          text: '¿Le dejas usar Read?',
          permiso: PeticionDePermiso(
            id: 'req-2',
            herramienta: 'Read',
            nombreVisible: 'Read',
            entrada: {'file_path': '/tmp/a.txt'},
          ),
        ),
      );

      expect(
        find.text(const NexusStringsEs().permisoConcederTodo),
        findsNothing,
      );
      // Y leer no se anuncia como escritura.
      expect(find.text(const NexusStringsEs().permisoEscribe), findsNothing);
    });
  });
}

class _PuenteQuePregunta implements ClaudeBridge {
  RespuestaDePermiso? contestado;
  var leDieronAQuienPreguntar = false;
  var termino = false;

  @override
  Stream<ClaudeEvent> ask(
    String instruction, {
    required String workingDirectory,
    required bool canEdit,
    List<String> extraDirectories = const [],
    String? resumeSessionId,
    String? claudeProfile,
    String? model,
    String? effort,
    String? artifactsFolder,
    String? carpetaDePruebas,
    List<String> disallowedTools = const [],
    List<String> comandosPermitidos = const [],
    String? constraintsNotice,
    String? language,
    String? nombres,
    String? modoConcedido,
    Future<RespuestaDePermiso> Function(PeticionDePermiso)? alPedirPermiso,
  }) async* {
    yield const ClaudeSessionStarted(sessionId: 's1', model: 'm');
    leDieronAQuienPreguntar = alPedirPermiso != null;
    if (alPedirPermiso == null) {
      termino = true;
      yield const ClaudeTurnCompleted(result: 'sin preguntar');
      return;
    }
    contestado = await alPedirPermiso(_peticion);
    yield const ClaudeTurnCompleted(result: 'listo');
  }
}

class _NoMemory implements ConversationMemory {
  const _NoMemory();
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
    String f,
    String mode, {
    String? claudeProfile,
  }) async {}

  @override
  Future<void> forget(String folderPath) async {}
}

class _Workspace extends WorkspaceController {
  _Workspace(this.permiso);

  final FilePermission permiso;

  @override
  Workspace build() => Workspace(
    folders: [
      PairedFolder(
        path: folderPath,
        modality: FolderModality.voice,
        // **El permiso es de la carpeta**, y el de la app es el tope: hacen
        // falta los dos para que se escriba, así que los dos van a lo que pida
        // la prueba. Sin esto no se pregunta nada — que es lo correcto y no lo
        // que esta prueba mira.
        puedeEditar: permiso.canWrite,
      ),
    ],
    activePath: folderPath,
    permission: permiso,
  );
}

class _SinDisco implements LocalConversationStore {
  const _SinDisco();
  @override
  Future<void> save(ConversationRecord record) async {}
  @override
  Future<List<ConversationSummary>> list(String folderPath) async => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
