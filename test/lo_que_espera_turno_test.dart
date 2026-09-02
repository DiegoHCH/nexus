import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/artifacts/domain/repositories/gemini_image_key_store.dart';
import 'package:nexus/features/artifacts/presentation/providers/artifacts_providers.dart';
import 'package:nexus/features/assistant/domain/entities/claude_event.dart';
import 'package:nexus/features/assistant/domain/repositories/conversation_memory.dart';
import 'package:nexus/features/assistant/domain/usecases/ask_claude.dart';
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

/// **Escribir mientras trabaja encola; no interrumpe.**
///
/// Antes cada mensaje nuevo cancelaba el encargo en curso, así que escribir
/// tres cosas seguidas dejaba dos sin respuesta — y sin decir por qué: las tres
/// se quedaban pintadas como si esperasen turno. Se reportó mirando la
/// pantalla: «se me trabó, le escribí varias veces y cuando reaccionó tenía los
/// mensajes encolados». No estaban encolados, estaban muertos.
///
/// La referencia es el CLI, que es lo que la gente ya tiene en las manos:
/// escribir encola —«press up to edit queued messages»— y para interrumpir hay
/// un gesto aparte, «esc to interrupt». Aquí ese gesto es el botón Detener.
const _id = 'c1';
const _carpeta = '/Users/alguien/General';

/// Un Claude que se queda trabajando hasta que la prueba lo suelta.
///
/// Es lo que hace falta para medir esto: sin un encargo **realmente** en vuelo
/// no hay nada que encolar, y un doble que contesta al momento haría pasar la
/// prueba con el código viejo y con el nuevo.
class _Claude implements AskClaude {
  _Claude();

  final pedidos = <String>[];
  final _turnos = <Completer<void>>[];

  @override
  Stream<ClaudeEvent> call(
    String instruction, {
    bool remember = true,
    bool allowWrites = true,
  }) async* {
    pedidos.add(instruction);
    final suelta = Completer<void>();
    _turnos.add(suelta);
    try {
      await suelta.future;
    } on Object catch (error) {
      yield ClaudeFailed(error.toString());
      return;
    }
    yield const ClaudeTextDelta('ya está');
    yield const ClaudeTurnCompleted(result: 'ya está');
  }

  /// Deja terminar al encargo que está en vuelo.
  void termina() => _turnos.removeAt(0).complete();

  /// Y lo deja **fallar**, que es el otro final de un encargo.
  void falla() => _turnos.removeAt(0).completeError(StateError('se cayó'));

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Sin llave de imágenes: `/imagen` falla enseguida, que es lo que hace falta
/// para medir la conversación sin salir a la red ni gastar un céntimo.
class _SinLlaveDeImagenes implements GeminiImageKeyStore {
  const _SinLlaveDeImagenes();
  @override
  Future<String?> read(String? perfil) async => null;
  @override
  Future<void> save(String? perfil, String key) async {}
  @override
  Future<void> clear(String? perfil) async {}
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

  Future<void> vueltas() async {
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  ProviderContainer contenedor() {
    claude = _Claude();
    final c = ProviderContainer(
      overrides: [
        conversationFolderProvider(_id).overrideWithValue(_carpeta),
        conversationMemoryProvider.overrideWithValue(const _SinMemoria()),
        workspaceControllerProvider.overrideWith(_Espacio.new),
        localConversationStoreProvider.overrideWithValue(const _SinAlmacen()),
        askClaudeProvider(_id).overrideWithValue(claude),
        geminiImageKeyStoreProvider.overrideWithValue(
          const _SinLlaveDeImagenes(),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('el segundo mensaje espera turno en vez de matar al primero', () async {
    final c = contenedor();
    final controlador = c.read(assistantControllerProvider(_id).notifier);

    await controlador.submit('ordena la casa');
    await vueltas();
    await controlador.submit('y saca la basura');
    await vueltas();

    // 🔴 Con el código viejo aquí había dos: el segundo cancelaba al primero y
    // arrancaba enseguida.
    expect(claude.pedidos, [
      'ordena la casa',
    ], reason: 'el segundo salió antes de que el primero terminara');
  });

  test('y sale solo cuando el primero termina', () async {
    final c = contenedor();
    final controlador = c.read(assistantControllerProvider(_id).notifier);

    await controlador.submit('ordena la casa');
    await vueltas();
    await controlador.submit('y saca la basura');
    await vueltas();

    claude.termina();
    await vueltas();

    expect(claude.pedidos, ['ordena la casa', 'y saca la basura']);
  });

  /// 🔴 **Y con la cola vacía, el siguiente sale como cualquiera.**
  ///
  /// Se vio en pantalla: se pidió «flow init», contestó, y a partir de ahí
  /// **nada**. Dos mensajes más escritos, ninguna respuesta, el orbe dormido, y
  /// en el registro ni una línea de que se hubiera lanzado un encargo — porque
  /// no se lanzó: se encolaron los dos, en una cola que nadie iba a vaciar.
  ///
  /// La guarda pregunta si hay una suscripción, y esa solo se soltaba **por el
  /// camino de la cola**: al terminar un encargo con la cola vacía se quedaba
  /// puesta para siempre. A partir de ahí la guarda decía «hay algo corriendo»
  /// sobre un encargo que había terminado hacía rato, y quien vacía la cola es
  /// justo el final de un encargo — que ya no iba a volver a ocurrir.
  ///
  /// Las pruebas de aquí encolaban **con el primero todavía en vuelo**, que es
  /// el caso que sí funcionaba. Este es el de después.
  test(
    'terminado el primero y sin cola, el siguiente sale al momento',
    () async {
      final c = contenedor();
      final controlador = c.read(assistantControllerProvider(_id).notifier);

      await controlador.submit('ordena la casa');
      await vueltas();
      claude.termina();
      await vueltas();

      // Nadie escribió nada mientras trabajaba: la cola está vacía.
      await controlador.submit('y ahora saca la basura');
      await vueltas();

      expect(
        claude.pedidos,
        ['ordena la casa', 'y ahora saca la basura'],
        reason:
            'con la cola vacía nadie va a vaciarla, así que encolarlo aquí es '
            'perderlo: se queda escrito en pantalla y no lo contesta nadie',
      );
    },
  );

  /// 🔴 **Fallar también es terminar**, y ese era el mismo callejón por otra
  /// puerta: un encargo que falla dejaba la suscripción puesta, así que la
  /// conversación se quedaba muda para siempre después de un fallo — que es
  /// justo cuando más ganas tienes de escribir otra cosa.
  test('después de un fallo la conversación sigue viva', () async {
    final c = contenedor();
    final controlador = c.read(assistantControllerProvider(_id).notifier);

    await controlador.submit('ordena la casa');
    await vueltas();
    claude.falla();
    await vueltas();

    await controlador.submit('bueno, saca la basura entonces');
    await vueltas();

    expect(claude.pedidos, [
      'ordena la casa',
      'bueno, saca la basura entonces',
    ]);
  });

  /// Y lo que ya estaba esperando turno cuando el encargo falló **no se
  /// pierde**: lo que quisiste después de lo que falló sigue valiendo.
  test('y lo que esperaba turno sale, en vez de morir con el fallo', () async {
    final c = contenedor();
    final controlador = c.read(assistantControllerProvider(_id).notifier);

    await controlador.submit('ordena la casa');
    await vueltas();
    await controlador.submit('y saca la basura');
    await vueltas();

    claude.falla();
    await vueltas();

    expect(claude.pedidos, ['ordena la casa', 'y saca la basura']);
  });

  /// La tercera puerta: `/imagen` no pasa por Claude, pero **cancela** lo
  /// anterior. Cancelar no es soltar, y la guarda mira si hay suscripción, no
  /// si sigue viva: sin soltarla, el mensaje siguiente a una imagen se encolaba
  /// para siempre igual que los otros dos casos.
  test('después de un /imagen el siguiente mensaje sale', () async {
    final c = contenedor();
    final controlador = c.read(assistantControllerProvider(_id).notifier);

    await controlador.submit('ordena la casa');
    await vueltas();
    claude.termina();
    await vueltas();

    // Sin llave de imágenes falla enseguida, que es lo que hace falta: lo que
    // se mide es el estado en el que deja la conversación, no el dibujo.
    await controlador.submit('/imagen un gato');
    await vueltas();

    await controlador.submit('y ahora saca la basura');
    await vueltas();

    expect(claude.pedidos.last, 'y ahora saca la basura');
  });

  test('los dos se ven escritos desde el momento en que se mandan', () async {
    final c = contenedor();
    final controlador = c.read(assistantControllerProvider(_id).notifier);

    await controlador.submit('ordena la casa');
    await vueltas();
    await controlador.submit('y saca la basura');
    await vueltas();

    final mios = c
        .read(assistantControllerProvider(_id))
        .messages
        .where((m) => m.author == ChatAuthor.user)
        .map((m) => m.text);
    expect(mios, ['ordena la casa', 'y saca la basura']);
  });

  /// Y **sin repetirse** al salir de la cola: el mensaje ya está escrito desde
  /// que se mandó, así que volver a pintarlo dejaría la misma petición dos
  /// veces con una sola respuesta debajo.
  test('el encolado no se escribe dos veces', () async {
    final c = contenedor();
    final controlador = c.read(assistantControllerProvider(_id).notifier);

    await controlador.submit('ordena la casa');
    await vueltas();
    await controlador.submit('y saca la basura');
    await vueltas();
    claude.termina();
    await vueltas();

    final cuantas = c
        .read(assistantControllerProvider(_id))
        .messages
        .where(
          (m) => m.author == ChatAuthor.user && m.text == 'y saca la basura',
        )
        .length;
    expect(cuantas, 1);
  });

  /// **La respuesta a lo que esperó turno dice a qué contesta.**
  ///
  /// Es el precio de encolar: escribes tres cosas y las tres respuestas llegan
  /// después, así que el orden deja de decir a cuál contesta cada una. La cita
  /// —barra al canto y la pregunta atenuada encima, como en cualquier chat—
  /// devuelve lo que la cola se llevó.
  test('la respuesta a lo encolado cita su pregunta', () async {
    final c = contenedor();
    final controlador = c.read(assistantControllerProvider(_id).notifier);

    await controlador.submit('ordena la casa');
    await vueltas();
    await controlador.submit('y saca la basura');
    await vueltas();

    // El primero contesta: su respuesta no cita nada, porque va pegada a su
    // pregunta y el orden ya lo dice.
    claude.termina();
    await vueltas();
    final primera = c
        .read(assistantControllerProvider(_id))
        .messages
        .lastWhere((m) => m.author == ChatAuthor.nexus);
    expect(primera.respondeA, isNull);

    // El encolado sí: entre su pregunta y su respuesta hay otros mensajes.
    claude.termina();
    await vueltas();
    final segunda = c
        .read(assistantControllerProvider(_id))
        .messages
        .lastWhere((m) => m.author == ChatAuthor.nexus);
    expect(segunda.respondeA, 'y saca la basura');
  });

  /// Detener es «para», no «pausa». Dejar la cola viva haría que al soltar el
  /// botón arrancara solo lo siguiente, que es lo contrario de lo pedido.
  test('detener se lleva por delante lo que esperaba turno', () async {
    final c = contenedor();
    final controlador = c.read(assistantControllerProvider(_id).notifier);

    await controlador.submit('ordena la casa');
    await vueltas();
    await controlador.submit('y saca la basura');
    await vueltas();

    await controlador.stopWork();
    await vueltas();

    expect(claude.pedidos, ['ordena la casa']);
  });
}
