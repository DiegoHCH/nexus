import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/domain/entities/audio_frame.dart';
import 'package:nexus/features/assistant/domain/entities/claude_event.dart';
import 'package:nexus/features/assistant/domain/entities/voice_event.dart';
import 'package:nexus/features/assistant/domain/repositories/audio_output.dart';
import 'package:nexus/features/assistant/domain/repositories/claude_bridge.dart';
import 'package:nexus/features/assistant/domain/repositories/conversation_memory.dart';
import 'package:nexus/features/assistant/domain/repositories/stays_awake.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_gateway.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_input.dart';
import 'package:nexus/features/assistant/domain/usecases/ask_claude.dart';
import 'package:nexus/features/assistant/domain/usecases/folder_errand_queue.dart';
import 'package:nexus/features/assistant/domain/usecases/hold_voice_conversation.dart';
import 'package:nexus/features/assistant/presentation/state/session_meter.dart';

/// El micrófono, callado: esta prueba va de lo que llega del servicio.
class _Mic implements VoiceInput {
  final _frames = StreamController<AudioFrame>();

  @override
  Future<bool> hasPermission() async => true;

  @override
  Stream<AudioFrame> listen() => _frames.stream;
}

/// La sesión de voz, movida a mano desde la prueba.
class _Session implements VoiceSession {
  final events_ = StreamController<VoiceEvent>.broadcast();
  final notes = <String>[];

  void emit(VoiceEvent event) => events_.add(event);

  @override
  Stream<VoiceEvent> get events => events_.stream;

  @override
  String? endReason;

  @override
  void sendAudio(Uint8List pcm) {}

  @override
  void sendSystemNote(String text) => notes.add(text);

  @override
  void sendToolResult({
    required String callId,
    required String name,
    required String result,
  }) {}

  @override
  Future<void> close() async {
    if (!events_.isClosed) await events_.close();
  }
}

class _Gateway implements VoiceGateway {
  _Gateway(this.session);
  final _Session session;

  @override
  Future<VoiceSession> connect() async => session;

  @override
  Future<VoiceSession> resume() async => session;
}

class _Speaker implements AudioOutput {
  @override
  Future<void> start() async {}
  @override
  void enqueue(Uint8List pcm) {}
  @override
  Future<void> discard() async {}
  @override
  Future<Duration> pending() async => Duration.zero;
  @override
  Future<void> stop() async {}
}

/// Anota el encargo que le llega. Es el testigo de la prueba: lo que Claude
/// recibe es lo que el usuario dijo, o no lo es.
///
/// Se guarda **sin la coletilla del idioma** que `AskClaude` le pega detrás:
/// aquí se mira qué se pidió, no cómo se envuelve.
class _Bridge implements ClaudeBridge {
  _Bridge({this.tarda = Duration.zero});

  /// Lo que tarda Claude en contestar. Con `Duration.zero` el encargo va y
  /// vuelve dentro del mismo turno; alargándolo se reproduce lo que pasa de
  /// verdad — que la respuesta buena llega cuando ya estás hablando de otra
  /// cosa.
  final Duration tarda;

  final _raw = <String>[];

  List<String> get asked => [
    for (final instruction in _raw) instruction.split('\n\n').first,
  ];

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
    _raw.add(instruction);
    if (tarda > Duration.zero) await Future<void>.delayed(tarda);
    yield ClaudeTurnCompleted(
      result: 'lo de «${instruction.split('\n\n').first}»',
    );
  }
}

class _Memory implements ConversationMemory {
  @override
  Future<FolderMemory> read(String folderPath, {String? claudeProfile}) async =>
      const FolderMemory(sessionId: null, prompts: []);
  @override
  Future<void> rememberSession(
    String folderPath,
    String id, {
    String? claudeProfile,
  }) async {}
  @override
  Future<void> rememberPrompt(String folderPath, String prompt) async {}
  @override
  Future<void> forget(String folderPath) async {}
}

class _Awake implements StaysAwake {
  @override
  Future<void Function()> hold(String reason) async => () {};
}

/// Un doble de `HoldVoiceConversation` con todo cableado menos lo que la
/// prueba quiera mirar.
HoldVoiceConversation _conversation(
  _Session session,
  _Bridge bridge, {
  void Function(String)? log,
}) => HoldVoiceConversation(
  _Mic(),
  _Gateway(session),
  _Speaker(),
  _askClaude(bridge),
  log ?? (_) {},
);

AskClaude _askClaude2(ClaudeBridge bridge) => _armar(bridge);

AskClaude _askClaude(_Bridge bridge) => _armar(bridge);

AskClaude _armar(ClaudeBridge bridge) => AskClaude(
  bridge,
  (_) async => (
    workingDirectory: '/repo',
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
  _Memory(),
  FolderErrandQueue(),
  _Awake(),
);

/// Un puente que **anuncia el modelo**, como hace el CLI en su evento `init`.
///
/// El `_Bridge` de arriba solo emite el fin de turno, y por eso ninguna prueba
/// veía que el modelo se estaba tirando: el evento que lo trae no existía en las
/// pruebas.
class _BridgeQueDiceElModelo implements ClaudeBridge {
  _BridgeQueDiceElModelo(this.model);

  final String model;

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
    // El orden es el de verdad: primero el `init` con el modelo, y el fin de
    // turno con las cifras al final.
    yield ClaudeSessionStarted(sessionId: 'ses-1', model: this.model);
    yield const ClaudeTurnCompleted(
      result: 'hecho',
      turnTokens: 1200,
      contextTokens: 175922,
    );
  }
}

void main() {
  test(
    'una frase larga llega en pedazos y va a Claude entera, no su cola (b11)',
    () async {
      final session = _Session();
      final bridge = _Bridge();
      final conversation = HoldVoiceConversation(
        _Mic(),
        _Gateway(session),
        _Speaker(),
        _askClaude(bridge),
        (_) {},
      );

      final subscription = conversation().listen((_) {});
      await Future<void>.delayed(Duration.zero);

      // Así llega de verdad: la transcripción de lo que dices viene por
      // trozos, no frase a frase. Lo dice el propio evento.
      for (final trozo in [
        'mira el repositorio ',
        'de nexus y dime ',
        'cuántos tests hay',
      ]) {
        session.emit(VoiceUserTranscript(trozo));
      }
      // El modelo contestó de memoria, sin llamar a la herramienta: aquí es
      // donde este código corrige y manda el encargo a Claude.
      session.emit(const VoiceTurnCompleted());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(bridge.asked, hasLength(1));
      expect(
        bridge.asked.single,
        'mira el repositorio de nexus y dime cuántos tests hay',
        reason:
            'antes se guardaba solo el último trozo, así que a Claude le '
            'llegaba «cuántos tests hay» — la frase cortada a mitad',
      );

      await subscription.cancel();
    },
  );

  test(
    'el turno cierra la frase: la siguiente no arrastra la anterior',
    () async {
      final session = _Session();
      final bridge = _Bridge();
      final conversation = HoldVoiceConversation(
        _Mic(),
        _Gateway(session),
        _Speaker(),
        _askClaude(bridge),
        (_) {},
      );

      final subscription = conversation().listen((_) {});
      await Future<void>.delayed(Duration.zero);

      session.emit(const VoiceUserTranscript('corre los tests'));
      session.emit(const VoiceTurnCompleted());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      session.emit(const VoiceUserTranscript('y ahora mira el historial'));
      session.emit(const VoiceTurnCompleted());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(bridge.asked, ['corre los tests', 'y ahora mira el historial']);

      await subscription.cancel();
    },
  );

  test(
    'una corrección que llega tarde no interrumpe: ya hablabas de otra cosa',
    () async {
      final session = _Session();
      // Claude tarda: para cuando contesta lo primero, el usuario ya preguntó
      // otra cosa. Es la sesión real del 13 ago, donde dos correcciones se
      // pisaron y la segunda dejó a la primera a medias.
      final bridge = _Bridge(tarda: const Duration(milliseconds: 120));
      final registro = <String>[];
      final conversation = _conversation(session, bridge, log: registro.add);

      final subscription = conversation().listen((_) {});
      await Future<void>.delayed(Duration.zero);

      // Turno 1: se pide algo que tenía que ir a Claude, y el modelo contesta
      // de memoria — así que arranca la corrección, que tardará.
      session.emit(const VoiceUserTranscript('dame un resumen de gitflow'));
      session.emit(const VoiceTurnCompleted());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Turno 2: el usuario no espera y pregunta otra cosa.
      session.emit(const VoiceUserTranscript('enséñame cómo es un flujo'));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(
        session.notes,
        isEmpty,
        reason:
            'la respuesta del turno 1 llegó cuando ya se hablaba del 2: '
            'entregarla hace que el modelo abandone lo que está diciendo',
      );
      expect(
        registro.where((l) => l.contains('descartada por vieja')),
        hasLength(1),
        reason: 'y se cuenta, para saber cuántas veces pasa de verdad',
      );

      await subscription.cancel();
    },
  );

  test(
    'la corrección sí entra si sigues callado: no se pierde por ir lenta',
    () async {
      final session = _Session();
      final bridge = _Bridge(tarda: const Duration(milliseconds: 120));
      final conversation = _conversation(session, bridge);

      final subscription = conversation().listen((_) {});
      await Future<void>.delayed(Duration.zero);

      session.emit(const VoiceUserTranscript('dame un resumen de gitflow'));
      session.emit(const VoiceTurnCompleted());
      // Nadie habla encima: el turno sigue siendo el mismo cuando Claude vuelve.
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(session.notes, hasLength(1));
      expect(session.notes.single, contains('dame un resumen de gitflow'));

      await subscription.cancel();
    },
  );

  test(
    'un saludo suelto sigue sin ir a Claude, aunque ahora se acumule',
    () async {
      final session = _Session();
      final bridge = _Bridge();
      final conversation = HoldVoiceConversation(
        _Mic(),
        _Gateway(session),
        _Speaker(),
        _askClaude(bridge),
        (_) {},
      );

      final subscription = conversation().listen((_) {});
      await Future<void>.delayed(Duration.zero);

      session.emit(const VoiceUserTranscript('hola'));
      session.emit(const VoiceTurnCompleted());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(bridge.asked, isEmpty);

      await subscription.cancel();
    },
  );

  test('antes de la primera señal se espera más de los 6 s de siempre (b11)', () {
    // La carrera, medida en una sesión real: el `setupComplete` llegó a los
    // 2453 ms —y como es un evento, reinició la cuenta— y la primera señal de
    // que el servicio te oía, a los 7251 ms. Con el plazo corto la sesión moría
    // a los 8453: se salvó por 1,2 s, y las que fallaban perdían esa carrera.
    //
    // Se mira **el registro** y no el cierre del stream: la cadena de apagado
    // no se asienta bajo `fakeAsync`, así que esperar al `onDone` daba una
    // prueba que pasaba con el plazo viejo y con el nuevo — o sea, ninguna.
    // La línea de cierre, en cambio, se emite en cuanto vence el plazo.
    fakeAsync((async) {
      final session = _Session();
      final registro = <String>[];
      final conversation = _conversation(session, _Bridge(), log: registro.add);
      conversation().listen((_) {});
      async.flushMicrotasks();

      session.emit(const VoiceSessionReady());
      async
        ..flushMicrotasks()
        ..elapse(const Duration(seconds: 7))
        ..flushMicrotasks();

      expect(
        registro.where((l) => l.contains('cierre por inactividad')),
        isEmpty,
        reason: 'a los 7 s se cerraba, justo antes de que el servicio hablara',
      );

      // Y sigue siendo un plazo: sin señal, el micrófono no queda abierto para
      // siempre.
      async
        ..elapse(const Duration(seconds: 15))
        ..flushMicrotasks();
      expect(
        registro.where((l) => l.contains('cierre por inactividad')),
        hasLength(1),
      );
    });
  });

  test('hablando, el fin del encargo lleva el modelo y no solo los tokens', () async {
    // La prueba que faltaba, y que se echó en falta de la peor manera: el arreglo
    // se dio por hecho con el cableado muerto. Las pruebas de entonces miraban el
    // medidor y la entidad —los dos correctos— mientras el evento que trae el
    // modelo seguía descartándose con un `break`.
    //
    // Sin el modelo, `contextWindow` da por hecha una ventana de 200k: los 175.922
    // tokens de una sesión de un millón salían como 88 % en vez de 18 %.
    final session = _Session();
    final conversation = HoldVoiceConversation(
      _Mic(),
      _Gateway(session),
      _Speaker(),
      _askClaude2(_BridgeQueDiceElModelo('claude-opus-5[1m]')),
      (_) {},
    );

    final vistos = <VoiceEvent>[];
    final subscription = conversation().listen(vistos.add);
    await Future<void>.delayed(Duration.zero);

    session.emit(const VoiceUserTranscript('corre los tests'));
    session.emit(const VoiceTurnCompleted());
    await Future<void>.delayed(const Duration(milliseconds: 40));

    final fin = vistos.whereType<VoiceToolFinished>().singleOrNull;
    expect(fin, isNotNull, reason: 'el encargo tiene que terminar');
    expect(
      fin!.model,
      'claude-opus-5[1m]',
      reason:
          'el modelo del `init` tiene que viajar con el fin del encargo: sin '
          'él el medidor asume 200k y el porcentaje sale por cinco',
    );
    expect(fin.contextTokens, 175922);

    // Y aplicado como lo aplica el controlador, la ventana sale bien.
    final medidor = const SessionMeter().copyWith(
      model: fin.model,
      contextTokens: fin.contextTokens,
    );
    expect(medidor.contextWindow, 1000000);
    expect(medidor.contextPercent, 18);

    await subscription.cancel();
  });
}
