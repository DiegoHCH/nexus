import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/entities/claude_event.dart';
import 'package:nexus/features/assistant/domain/repositories/claude_bridge.dart';
import 'package:nexus/features/assistant/domain/repositories/conversation_memory.dart';
import 'package:nexus/features/assistant/domain/usecases/ask_claude.dart';
import 'package:nexus/features/assistant/domain/repositories/stays_awake.dart';
import 'package:nexus/features/assistant/domain/usecases/folder_errand_queue.dart';

class _Bridge implements ClaudeBridge {
  final asked = <String>[];
  final resumed = <String?>[];

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
    List<String> disallowedTools = const [],
  }) async* {
    asked.add(instruction);
    resumed.add(resumeSessionId);
    yield const ClaudeSessionStarted(sessionId: 'sesion-1', model: 'x');
    yield const ClaudeTurnCompleted(result: 'listo');
  }
}

class _Memory implements ConversationMemory {
  final prompts = <String>[];
  String? sessionId;

  @override
  Future<FolderMemory> read(String folderPath) async =>
      FolderMemory(sessionId: sessionId, prompts: prompts);

  @override
  Future<void> rememberSession(String folderPath, String id) async =>
      sessionId = id;

  @override
  Future<void> rememberPrompt(String folderPath, String prompt) async =>
      prompts.add(prompt);

  @override
  Future<void> forget(String folderPath) async {}
}

class _Awake implements StaysAwake {
  int held = 0;
  int released = 0;

  @override
  Future<void Function()> hold(String reason) async {
    held++;
    return () => released++;
  }
}

AskClaude _askWith(
  _Bridge bridge,
  _Memory memory, {
  String? folder = '/repo',
  _Awake? awake,
}) => AskClaude(
  bridge,
  (_) async => folder == null
      ? null
      : (
          workingDirectory: folder,
          canEdit: false,
          extraDirectories: const <String>[],
          language: 'español',
          claudeProfile: null,
          model: null,
          effort: null,
          artifactsFolder: null,
          disallowedTools: const <String>[],
          constraintsNotice: null,
        ),
  memory,
  FolderErrandQueue(),
  awake ?? _Awake(),
);

void main() {
  test(
    'sin carpeta emparejada lo dice, en vez de trabajar sobre la raíz',
    () async {
      final bridge = _Bridge();
      final events = await _askWith(bridge, _Memory(), folder: null)(
        'algo',
      ).toList();

      expect(events.single, isA<ClaudeFailed>());
      expect(bridge.asked, isEmpty);
    },
  );

  test('lo pedido se recuerda, y el idioma viaja como preferencia', () async {
    final bridge = _Bridge();
    final memory = _Memory();

    await _askWith(bridge, memory)('mira el historial').toList();

    expect(memory.prompts, ['mira el historial']);
    expect(bridge.asked.single, startsWith('mira el historial'));
    expect(bridge.asked.single, contains('español'));
  });

  // El identificador se guarda en cuanto arranca, no al terminar: si el encargo
  // se cancela a media ejecución, lo hablado hasta ahí ya forma parte de la
  // sesión, y olvidarlo dejaría a Claude repitiendo trabajo hecho.
  test('la sesión se recuerda y se reanuda en el siguiente encargo', () async {
    final bridge = _Bridge();
    final memory = _Memory();
    final ask = _askWith(bridge, memory);

    await ask('primero').toList();
    await ask('segundo').toList();

    expect(memory.sessionId, 'sesion-1');
    expect(bridge.resumed, [null, 'sesion-1']);
  });

  // Comprimir no es una petición del usuario: si apareciera en «lo que le has
  // pedido», la lista para repetir peticiones se llenaría de /compact.
  test('comprimir no ensucia el historial de peticiones', () async {
    final bridge = _Bridge();
    final memory = _Memory();
    final ask = _askWith(bridge, memory);

    await ask('mira el historial').toList();
    await ask('/compact', remember: false).toList();

    expect(memory.prompts, ['mira el historial']);
    expect(bridge.asked.last, startsWith('/compact'));
  });

  group('el Mac no se duerme mientras dura el encargo', () {
    test('se pide al empezar y se suelta al terminar', () async {
      final awake = _Awake();

      await _askWith(_Bridge(), _Memory(), awake: awake)('algo').toList();

      expect(awake.held, 1);
      expect(awake.released, 1);
    });

    // Cerrar la conversación a media ejecución cancela el stream, y por ahí se
    // sale sin pasar por el final. Si eso no soltara, el Mac se quedaría sin
    // poder dormirse el resto de la sesión — y nadie lo relacionaría con esto.
    test('también si se cancela a mitad', () async {
      final awake = _Awake();
      final stream = _askWith(_Bridge(), _Memory(), awake: awake)('algo');

      final subscription = stream.listen(null);
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(awake.held, 1);
      expect(awake.released, 1);
    });

    // Sin carpeta no hay encargo: ni se lanza nada ni hay por qué tocar el
    // sistema.
    test('sin carpeta no se pide nada', () async {
      final awake = _Awake();

      await _askWith(_Bridge(), _Memory(), folder: null, awake: awake)(
        'algo',
      ).toList();

      expect(awake.held, 0);
    });
  });
}
