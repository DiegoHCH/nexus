import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/assistant/domain/entities/claude_event.dart';
import 'package:nexus/features/assistant/domain/entities/voice_event.dart';
import 'package:nexus/features/assistant/presentation/providers/claude_bridge_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/voice_session_providers.dart';
import 'package:nexus/features/assistant/presentation/state/assistant_hud_state.dart';
import 'package:nexus/features/assistant/presentation/state/chat_message.dart';
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';
import 'package:nexus/features/assistant/presentation/state/session_meter.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

/// El pegamento entre los dos modelos y la pantalla: traduce cada
/// [ClaudeEvent] y cada [VoiceEvent] al mismo [AssistantHudState] que el orbe,
/// el horizonte y la franja de subtítulos escuchan.
///
/// Los dos caminos comparten estado a propósito: para quien mira, hablar y
/// escribir son la misma conversación, aunque por dentro uno sea un proceso
/// y el otro un socket.
class AssistantController extends Notifier<AssistantHudState> {
  AssistantController(this.conversationId);

  /// La conversación a la que sirve este controlador. Hay uno por cada una y
  /// **corren a la vez**: cada uno con su proceso de Claude, su actividad y su
  /// memoria. Lo único que no se duplica es el micrófono.
  final String conversationId;

  String? get _folder => ref.read(conversationFolderProvider(conversationId));

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

    unawaited(_loadMemory());

    // Perder el foco cierra el micrófono: solo la conversación en foco puede
    // hablar, y dejarlo abierto en una que ya no miras sería exactamente el
    // estado que el proyecto lleva evitando desde 2.5.
    ref.listen(conversationsProvider, (previous, next) {
      if (state.voiceActive && next.focusedId != conversationId) {
        unawaited(stopVoice());
      }
    });

    // Y si a su carpeta le quitan el modo voz, también (i5).
    ref.listen(workspaceControllerProvider, (previous, next) {
      if (!state.voiceActive) return;
      final folder = _folder;
      final allowed = next.folders.any(
        (f) => f.path == folder && f.modality.allowsVoice,
      );
      if (!allowed) unawaited(stopVoice());
    });

    return const AssistantHudState();
  }

  /// El historial es de la carpeta, no de la ficha: dos conversaciones sobre
  /// el mismo repo comparten contexto, así que compartir también lo pedido es
  /// lo coherente — verían el mismo hilo desde dos sitios.
  Future<void> _loadMemory() async {
    final folder = _folder;
    if (folder == null) return;
    final memory = await ref.read(conversationMemoryProvider).read(folder);
    state = state.copyWith(history: memory.prompts);
  }

  /// Empezar de cero **en esta carpeta**: Claude deja de reanudar la sesión
  /// anterior. Afecta a las conversaciones que compartan carpeta, que es lo
  /// coherente si comparten contexto. El historial de lo pedido se conserva
  /// —sirve para repetir una petición— porque lo que estorba es el contexto
  /// arrastrado, no la lista.
  Future<void> forgetConversation() async {
    final folder = _folder;
    if (folder == null) return;
    await ref.read(conversationMemoryProvider).forget(folder);
    state = state.copyWith(
      subtitle: 'Conversación olvidada: la próxima empieza de cero.',
      meter: const SessionMeter(),
    );
  }

  /// Añade un turno a la conversación.
  void _say(ChatAuthor author, String text, {bool spoken = false}) {
    state = state.copyWith(
      messages: [
        ...state.messages,
        ChatMessage(
          author: author,
          text: text,
          spoken: spoken,
          streaming: true,
        ),
      ],
    );
  }

  /// Va completando el último turno de ese autor mientras llega.
  ///
  /// El texto entra a trozos —deltas de Claude, transcripción de Gemini— y
  /// crear un mensaje por trozo llenaría la ventana de fragmentos sueltos.
  void _appendTo(ChatAuthor author, String text, {bool spoken = false}) {
    final messages = [...state.messages];
    final last = messages.lastOrNull;
    if (last != null && last.author == author && last.streaming) {
      messages[messages.length - 1] = last.copyWith(text: last.text + text);
      state = state.copyWith(messages: messages);
      return;
    }
    _say(author, text, spoken: spoken);
  }

  /// Cierra el turno en curso: se le quita el cursor.
  void _sealLast() {
    final messages = [...state.messages];
    final last = messages.lastOrNull;
    if (last == null || !last.streaming) return;
    if (last.isEmpty) {
      // Un turno que no llegó a decir nada no se deja en la ventana.
      messages.removeLast();
    } else {
      messages[messages.length - 1] = last.copyWith(streaming: false);
    }
    state = state.copyWith(messages: messages);
  }

  Future<void> submit(String instruction) async {
    final trimmed = instruction.trim();
    if (trimmed.isEmpty) return;

    await _subscription?.cancel();
    _sealLast();
    final buffer = StringBuffer();
    state = state.copyWith(
      orbState: NexusOrbState.think,
      subtitle: '',
      isStreaming: true,
      activity: const [],
      errorMessage: null,
      history: _remember(trimmed),
    );
    _say(ChatAuthor.user, trimmed);
    _sealLast();

    final ask = ref.read(askClaudeProvider(conversationId));
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
          // El detalle se estaba tirando aquí: el lector lo traía y la fila no
          // lo recibía, así que un paso no se podía abrir hasta que terminara
          // —y entonces solo enseñaba lo que devolvió, nunca lo que se
          // ejecutó—. Es justo la mitad que 3.2 fue a buscar.
          detail: event.detail,
          parentId: event.parentId,
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
    _appendTo(ChatAuthor.nexus, event.text);
    state = state.copyWith(orbState: NexusOrbState.speak, isStreaming: true);
  }

  void _onTurnCompleted(ClaudeTurnCompleted event) {
    _sealLast();
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
    _sealLast();
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
    // Sobre **la carpeta de esta conversación**, no sobre una «activa» global:
    // con varias abiertas, esa noción ya no existe, y consultarla haría que el
    // permiso de una decidiera por otra.
    final folder = _folder;
    final paired = ref
        .read(workspaceControllerProvider)
        .folders
        .where((item) => item.path == folder)
        .firstOrNull;
    if (paired == null) {
      state = state.copyWith(
        errorMessage:
            'Esta conversación no tiene carpeta emparejada: no hay dónde trabajar.',
      );
      return;
    }
    if (!paired.modality.allowsVoice) {
      state = state.copyWith(
        errorMessage:
            'La carpeta ${paired.name} está en modo solo texto, así que no se '
            'abre el micrófono. Escríbele por abajo o cambia el modo en Ajustes.',
      );
      return;
    }

    // Hablar es del foco: si esta conversación no lo tiene, se lo lleva.
    unawaited(ref.read(conversationsProvider.notifier).focus(conversationId));

    _heard.clear();
    _reply.clear();
    state = const AssistantHudState(
      orbState: NexusOrbState.think,
      voiceActive: true,
    );

    final conversation = ref.read(
      holdVoiceConversationProvider(conversationId),
    );
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

  /// Quita el aviso ya leído. Un error que no se puede cerrar obliga a
  /// convivir con él el resto de la sesión.
  void dismissError() => state = state.copyWith(errorMessage: null);

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
    if (_reply.isNotEmpty) {
      _reply.clear();
      _heard.clear();
      _sealLast();
    }
    _heard.write(text);
    _appendTo(ChatAuthor.user, text, spoken: true);
    state = state.copyWith(orbState: NexusOrbState.listen, isStreaming: true);
  }

  void _onReply(String text) {
    if (_reply.isEmpty) _sealLast();
    _reply.write(text);
    _appendTo(ChatAuthor.nexus, text, spoken: true);
    state = state.copyWith(orbState: NexusOrbState.speak, isStreaming: true);
  }

  void _onInterrupted() {
    _reply.clear();
    state = state.copyWith(orbState: NexusOrbState.listen, isStreaming: false);
  }

  void _onVoiceTurnCompleted() {
    // Si Claude está trabajando, el turno hablado que acaba es el "voy a
    // mirarlo": el orbe tiene que seguir en trabajando, no volver a escuchar.
    if (state.orbState == NexusOrbState.think) return;
    _sealLast();
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
    NotifierProvider.family<AssistantController, AssistantHudState, String>(
      AssistantController.new,
    );
