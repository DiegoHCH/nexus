import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/assistant/domain/entities/claude_event.dart';
import 'package:nexus/features/assistant/domain/entities/voice_event.dart';
import 'package:nexus/features/assistant/presentation/providers/claude_bridge_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/voice_session_providers.dart';
import 'package:nexus/features/assistant/presentation/state/assistant_hud_state.dart';
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

/// El pegamento entre los dos modelos y la pantalla: traduce cada
/// [ClaudeEvent] y cada [VoiceEvent] al mismo [AssistantHudState] que el orbe,
/// el horizonte y la franja de subtítulos escuchan.
///
/// Los dos caminos comparten estado a propósito: para quien mira, hablar y
/// escribir son la misma conversación, aunque por dentro uno sea un proceso
/// y el otro un socket.
class AssistantController extends Notifier<AssistantHudState> {
  StreamSubscription<ClaudeEvent>? _subscription;
  StreamSubscription<VoiceEvent>? _voiceSubscription;

  /// Lo que va diciendo el usuario y lo que va respondiendo el modelo, por
  /// separado: la franja muestra uno u otro según quién tenga el turno.
  final _heard = StringBuffer();
  final _reply = StringBuffer();

  @override
  AssistantHudState build() {
    ref.onDispose(() {
      _subscription?.cancel();
      _voiceSubscription?.cancel();
    });

    // Cambiar de carpeta con la sesión viva la cierra (i5). El audio abierto
    // bajo una carpeta permisiva no puede seguir fluyendo al saltar a una
    // restringida solo porque nadie miró.
    ref.listen(workspaceControllerProvider, (previous, next) {
      if (!state.voiceActive) return;
      final changedFolder = previous?.activePath != next.activePath;
      if (changedFolder || !next.allowsVoice) unawaited(stopVoice());
    });

    return const AssistantHudState();
  }

  Future<void> submit(String instruction) async {
    final trimmed = instruction.trim();
    if (trimmed.isEmpty) return;

    await _subscription?.cancel();
    final buffer = StringBuffer();
    state = const AssistantHudState(
      orbState: NexusOrbState.think,
      isStreaming: true,
      activity: [],
    );

    final ask = ref.read(askClaudeProvider);
    _subscription = ask(trimmed).listen(
      (event) => switch (event) {
        ClaudeSessionStarted() => _onSessionStarted(event.model),
        ClaudeTextDelta() => _onTextDelta(buffer, event),
        ClaudeToolUsed() => _onClaudeToolUsed(event),
        ClaudeToolFinished() => _onClaudeToolFinished(event.id, event.output),
        ClaudeTurnCompleted() => _onTurnCompleted(event),
        ClaudeFailed() => _onFailed(event.message),
      },
      onError: (Object error) => _onFailed(error.toString()),
    );
  }

  void _onSessionStarted(String model) {
    if (model.isEmpty) return;
    state = state.copyWith(meter: state.meter.copyWith(model: model));
  }

  /// La actividad se acumula en el turno y se vacía al empezar el siguiente:
  /// la columna se llama «Ahora mismo», no «historial».
  void _onClaudeToolUsed(ClaudeToolUsed event) {
    state = state.copyWith(
      orbState: NexusOrbState.think,
      activity: [
        ...state.activity,
        ActivityItem(
          id: event.id,
          description: event.description,
          writes: event.writes,
        ),
      ],
    );
  }

  void _onClaudeToolFinished(String id, [String? output]) {
    state = state.copyWith(
      activity: [
        for (final item in state.activity)
          if (item.id == id) item.asDone(output: output) else item,
      ],
    );
  }

  void _onTextDelta(StringBuffer buffer, ClaudeTextDelta event) {
    buffer.write(event.text);
    state = state.copyWith(
      orbState: NexusOrbState.speak,
      subtitle: buffer.toString(),
      isStreaming: true,
    );
  }

  void _onTurnCompleted(ClaudeTurnCompleted event) {
    state = state.copyWith(
      orbState: NexusOrbState.sleep,
      isStreaming: false,
      meter: state.meter.copyWith(
        turnTokens: event.turnTokens,
        contextTokens: event.contextTokens,
      ),
    );
  }

  void _onFailed(String message) {
    state = state.copyWith(
      orbState: NexusOrbState.sleep,
      isStreaming: false,
      errorMessage: message,
    );
  }

  /// Mientras no hay sesión de voz, el campo de texto enfocado es la señal
  /// más cercana a "te estoy escuchando" que hay — solo mientras no haya
  /// nada en curso.
  void setListening(bool isListening) {
    if (state.voiceActive) return;
    final idle =
        state.orbState == NexusOrbState.sleep ||
        state.orbState == NexusOrbState.listen;
    if (!idle) return;
    state = state.copyWith(
      orbState: isListening ? NexusOrbState.listen : NexusOrbState.sleep,
    );
  }

  /// Abre o cierra la conversación por voz. Es un interruptor y no dos
  /// métodos porque el mando en la interfaz es uno solo: el orbe.
  Future<void> toggleVoice() async {
    if (state.voiceActive) {
      await stopVoice();
      return;
    }

    // El guardia de i5, y va aquí —donde se abre la sesión— y no en un botón
    // deshabilitado: si viviera en la interfaz, cualquier otro camino que
    // abriera sesión (el atajo global, sin ir más lejos) se lo saltaría.
    final workspace = ref.read(workspaceControllerProvider);
    if (workspace.active == null) {
      state = state.copyWith(
        errorMessage:
            'Empareja una carpeta antes de hablarle: sin eso no hay dónde trabajar.',
      );
      return;
    }
    if (!workspace.allowsVoice) {
      state = state.copyWith(
        errorMessage:
            'La carpeta ${workspace.active!.name} está en modo solo texto, así que no se '
            'abre el micrófono. Escríbele por abajo o cambia el modo en Ajustes.',
      );
      return;
    }

    _heard.clear();
    _reply.clear();
    state = const AssistantHudState(
      orbState: NexusOrbState.think,
      voiceActive: true,
    );

    final conversation = ref.read(holdVoiceConversationProvider);
    _voiceSubscription = conversation().listen(
      (event) => switch (event) {
        VoiceSessionReady() => _onVoiceReady(),
        VoiceUserTranscript() => _onHeard(event.text),
        VoiceReplyTranscript() => _onReply(event.text),
        VoiceInterrupted() => _onInterrupted(),
        VoiceTurnCompleted() => _onVoiceTurnCompleted(),
        VoiceToolStarted() => _onToolStarted(event.instruction),
        VoiceToolProgress() => _onToolProgress(event.text),
        VoiceToolActivity() => _onVoiceActivity(event),
        VoiceToolFinished() => _onToolFinished(),
        VoiceSessionFailed() => unawaited(_onVoiceFailed(event.message)),
        // El audio no llega hasta aquí: lo reproduce el caso de uso. La
        // interfaz solo necesita el texto y el estado.
        VoiceReplyAudio() => null,
        // La petición la atiende el caso de uso; la pantalla ve el trabajo,
        // no la fontanería.
        VoiceToolRequested() => null,
      },
      onError: (Object error) => unawaited(_onVoiceFailed(error.toString())),
      onDone: () => state = state.copyWith(
        voiceActive: false,
        orbState: NexusOrbState.sleep,
      ),
    );
  }

  /// Detiene lo que esté en curso, venga de la voz o del teclado. Es el
  /// «Detener ⌘.» del diseño: un encargo puede durar minutos y quedarse sin
  /// salida visible sería lo peor que puede pasarte.
  Future<void> stopWork() async {
    if (state.voiceActive) {
      await stopVoice();
      return;
    }
    await _subscription?.cancel();
    _subscription = null;
    state = state.copyWith(orbState: NexusOrbState.sleep, isStreaming: false);
  }

  Future<void> stopVoice() async {
    await _voiceSubscription?.cancel();
    _voiceSubscription = null;
    state = state.copyWith(
      voiceActive: false,
      orbState: NexusOrbState.sleep,
      isStreaming: false,
    );
  }

  void _onVoiceReady() {
    state = state.copyWith(orbState: NexusOrbState.listen, subtitle: '');
  }

  /// Lo pedido antes, lo más reciente primero y sin repetir el turno en curso.
  List<String> _remember(String prompt) {
    const keep = 6;
    final rest = state.history.where((item) => item != prompt);
    return [prompt, ...rest].take(keep).toList();
  }

  void _onHeard(String text) {
    // Si el usuario vuelve a hablar, lo anterior deja de ser el turno actual.
    if (_reply.isNotEmpty) {
      _reply.clear();
      _heard.clear();
    }
    _heard.write(text);
    state = state.copyWith(
      orbState: NexusOrbState.listen,
      subtitle: _heard.toString(),
      isStreaming: true,
    );
  }

  void _onReply(String text) {
    _reply.write(text);
    state = state.copyWith(
      orbState: NexusOrbState.speak,
      subtitle: _reply.toString(),
      isStreaming: true,
    );
  }

  void _onInterrupted() {
    _reply.clear();
    state = state.copyWith(orbState: NexusOrbState.listen, isStreaming: false);
  }

  void _onVoiceTurnCompleted() {
    // Si Claude está trabajando, el turno hablado que acaba es el "voy a
    // mirarlo": el orbe tiene que seguir en trabajando, no volver a escuchar.
    if (state.orbState == NexusOrbState.think) return;
    _heard.clear();
    _reply.clear();
    state = state.copyWith(orbState: NexusOrbState.listen, isStreaming: false);
  }

  /// Se muestra la instrucción que redactó Gemini, no lo que dijo el usuario:
  /// es lo que se va a ejecutar de verdad, y es la única parte revisable
  /// antes de que pase.
  void _onToolStarted(String instruction) {
    _heard.clear();
    _reply.clear();
    state = state.copyWith(
      orbState: NexusOrbState.think,
      subtitle: instruction,
      isStreaming: true,
      activity: const [],
      history: _remember(instruction),
    );
  }

  /// Una acción marcada como terminada llega sin descripción: solo dice
  /// «aquella ya está», así que se conserva el texto que ya se mostraba.
  void _onVoiceActivity(VoiceToolActivity event) {
    if (event.done) {
      _onClaudeToolFinished(event.id);
      return;
    }
    _onClaudeToolUsed(
      ClaudeToolUsed(
        id: event.id,
        description: event.description,
        writes: event.writes,
      ),
    );
  }

  void _onToolProgress(String text) {
    _reply.write(text);
    state = state.copyWith(
      orbState: NexusOrbState.think,
      subtitle: _reply.toString(),
      isStreaming: true,
    );
  }

  /// El resultado ya viajó de vuelta al modelo: lo siguiente que llegue será
  /// su narración hablada, así que aquí solo se suelta el estado de trabajo.
  void _onToolFinished() {
    _reply.clear();
    state = state.copyWith(orbState: NexusOrbState.listen, isStreaming: false);
  }

  Future<void> _onVoiceFailed(String message) async {
    await _voiceSubscription?.cancel();
    _voiceSubscription = null;
    state = state.copyWith(
      voiceActive: false,
      orbState: NexusOrbState.sleep,
      isStreaming: false,
      errorMessage: message,
    );
  }
}

final assistantControllerProvider =
    NotifierProvider<AssistantController, AssistantHudState>(
      AssistantController.new,
    );
