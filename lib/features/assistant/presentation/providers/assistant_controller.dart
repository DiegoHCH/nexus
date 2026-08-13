import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/i18n/language_preference.dart';
import 'package:nexus/features/assistant/domain/entities/claude_event.dart';
import 'package:nexus/features/assistant/domain/entities/voice_event.dart';
import 'package:nexus/features/assistant/presentation/providers/claude_bridge_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/model_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/voice_session_providers.dart';
import 'package:nexus/features/assistant/presentation/state/assistant_hud_state.dart';
import 'package:nexus/features/assistant/presentation/state/chat_message.dart';
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';
import 'package:nexus/features/assistant/presentation/state/session_meter.dart';
import 'package:nexus/features/history/domain/entities/conversation_record.dart';
import 'package:nexus/features/history/presentation/providers/archive_providers.dart';
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
      subtitle: ref.read(stringsProvider).conversationForgotten,
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
        ClaudeQueued() => _onQueued(),
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

  /// Esperando turno: la otra conversación sobre esta misma carpeta sigue
  /// trabajando. Se pinta como un paso más porque lo es —el encargo ya está
  /// aceptado— y porque esperar sin decirlo se ve igual que un cuelgue.
  void _onQueued() {
    state = state.copyWith(
      orbState: NexusOrbState.think,
      activity: [
        ...state.activity,
        ActivityItem(
          id: _queueItemId,
          description: ref.read(stringsProvider).waitingForOtherConversation,
          writes: false,
        ),
      ],
    );
  }

  void _onSessionStarted(String model) {
    // Le llegó el turno: la espera se da por terminada en cuanto arranca.
    _onClaudeToolFinished(_queueItemId);
    if (model.isEmpty) return;
    // Se apunta con qué cuenta corrió: es lo único que permite enseñar el
    // modelo de un perfil que no fija ninguno en su configuración.
    final folder = _folder;
    if (folder != null) {
      final paired = ref
          .read(workspaceControllerProvider)
          .folders
          .where((item) => item.path == folder)
          .firstOrNull;
      unawaited(
        ref
            .read(seenModelsProvider.notifier)
            .remember(paired?.claudeProfile, model),
      );
    }
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

  /// Identificador fijo: solo puede haber una espera por turno, y así se cierra
  /// sin tener que recordar cuál era.
  static const _queueItemId = 'esperando-turno';

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
    // La rama puede haber cambiado durante el encargo —se lo pediste tú, o
    // Claude hizo checkout—, así que se relee en vez de dejar la de antes.
    if (_folder case final folder?) ref.invalidate(gitInfoProvider(folder));
    unawaited(_archive());
    unawaited(_compactIfNeeded());
  }

  /// Deja la conversación guardada donde el usuario haya dicho.
  ///
  /// Se escribe **al terminar cada turno**, no al cerrar: cerrar puede no
  /// ocurrir nunca —se cierra la app, se va la luz— y entonces lo hablado se
  /// perdería entero. Reescribir el archivo cada vez es barato y deja el mismo
  /// resultado, que es justo lo que se quiere de un archivo idempotente.
  Future<void> _archive() async {
    final folder = _folder;
    if (folder == null) return;
    final record = ConversationRecord(
      id: _recordId,
      folderPath: folder,
      startedAt: _startedAt,
      messages: state.messages,
      // El perfil es el primer nivel del vault: `work/proyecto/…`. Sale de la
      // carpeta, que es donde se elige la cuenta.
      profileName: _profileName(folder),
      model: state.meter.model,
      contextTokens: state.meter.contextTokens,
    );

    // Primero el historial de la app, que no depende de nada externo. Si
    // dependiera del vault o de Notion, elegir «en ningún sitio» dejaría a
    // Nexus sin memoria de lo que hiciste.
    try {
      await ref.read(localConversationStoreProvider).save(record);
      ref.invalidate(savedConversationsProvider(folder));
    } catch (error) {
      developer.log(
        'no se pudo guardar en local: $error',
        name: 'nexus.archivo',
      );
    }

    final archive = await ref.read(conversationArchiveProvider.future);
    if (archive == null) return;
    try {
      await archive.save(record);
    } catch (error) {
      // Que falle guardar no puede tumbar la conversación: la carpeta puede
      // haberse desconectado, o el vault puede no existir ya. Se dice y se
      // sigue — el historial de la app nunca depende del destino externo.
      developer.log('no se pudo archivar: $error', name: 'nexus.archivo');
    }
  }

  /// `work`, `private`… tal como se llama la cuenta elegida para esta carpeta.
  String? _profileName(String folder) {
    final paired = ref
        .read(workspaceControllerProvider)
        .folders
        .where((item) => item.path == folder)
        .firstOrNull;
    final profile = paired?.claudeProfile;
    if (profile == null || profile.isEmpty) return null;
    final name = profile.split('/').last;
    return name.startsWith('.claude-') ? name.substring(8) : name;
  }

  /// Cuándo empezó, para fechar el archivo. Se fija al construir el
  /// controlador: la conversación existe desde que se abre, no desde que
  /// alguien dice algo.
  DateTime _startedAt = DateTime.now();

  /// Con qué identidad se guarda. Es la de esta conversación salvo que se
  /// retome una del historial: entonces se adopta la suya, o la siguiente
  /// respuesta crearía un archivo nuevo en vez de continuar el que estás
  /// leyendo.
  late String _recordId = conversationId;

  /// Si esta conversación es la que se está viendo de ese archivo. Se compara
  /// con el identificador del registro y no con el de la conversación: al
  /// retomar una del historial, la conversación adopta el suyo.
  bool isShowing(String recordId) => _recordId == recordId;

  /// Vuelve a abrir una conversación guardada: se pinta entera y lo que sigas
  /// diciendo se añade a ella.
  void resume(ConversationRecord record) {
    _recordId = record.id;
    _startedAt = record.startedAt;
    state = state.copyWith(
      messages: record.messages,
      subtitle: '',
      activity: const [],
      errorMessage: null,
      // Con lo que decía el medidor al guardarla. Si no, retomar una
      // conversación dejaba la barra superior en blanco hasta el siguiente
      // turno, como si el contexto se hubiera perdido — y no se ha perdido:
      // Claude reanuda su sesión con todo dentro.
      meter: SessionMeter(
        model: record.model ?? state.meter.model,
        contextTokens: record.contextTokens ?? state.meter.contextTokens,
      ),
    );
  }

  /// A partir de aquí se comprime la conversación.
  ///
  /// Antes del tope a propósito: al llenarse, Claude resume solo y **se pierde
  /// el detalle sin que nadie lo decida**. Con margen, la compresión ocurre
  /// cuando conviene y se puede contar.
  static const _compactAtPercent = 85;

  bool _compacting = false;

  /// Comprime la conversación con `/compact`, el mismo comando de la terminal.
  ///
  /// Medido contra el binario antes de cablearlo, porque no era obvio que
  /// funcionara en modo headless: en una sesión de 39.890 tokens de contexto,
  /// después de `/compact` el siguiente turno arrancó con 31.841 — y seguía
  /// recordando un dato del principio. No baja a cero: el suelo son las
  /// instrucciones y las reglas del proyecto, que viajan en cada encargo y no
  /// se pueden resumir.
  ///
  /// Se lanza **al terminar un turno**, nunca en medio: comprimir mientras
  /// Claude trabaja sería cambiarle el suelo bajo los pies.
  /// Dos conversaciones sobre la misma carpeta comparten sesión, así que las
  /// dos podrían pedir compresión casi a la vez. No se coordina a propósito:
  /// la cola por carpeta las serializa y la segunda encuentra el contexto ya
  /// bajado, así que lo peor que pasa es un turno de más — bastante menos
  /// aparato que un candado compartido para un caso raro e inofensivo.
  Future<void> _compactIfNeeded() async {
    if (_compacting) return;
    final before = state.meter.contextPercent;
    if (before == null || before < _compactAtPercent) return;

    _compacting = true;
    final strings = ref.read(stringsProvider);
    state = state.copyWith(
      activity: [
        ...state.activity,
        ActivityItem(
          id: _compactItemId,
          description: strings.compacting(before),
          writes: false,
        ),
      ],
    );

    try {
      await for (final event in ref.read(askClaudeProvider(conversationId))(
        '/compact',
        remember: false,
      )) {
        if (event case ClaudeTurnCompleted(:final contextTokens)) {
          state = state.copyWith(
            meter: state.meter.copyWith(contextTokens: contextTokens),
          );
        }
      }
      _onClaudeToolFinished(_compactItemId);
      final after = state.meter.contextPercent;
      if (after != null) {
        _say(ChatAuthor.nexus, strings.compacted(before, after));
        _sealLast();
      }
    } catch (error) {
      // Que falle la compresión no puede tumbar la conversación: se sigue con
      // el contexto lleno, que es exactamente como se estaba antes.
      _onClaudeToolFinished(_compactItemId);
    } finally {
      _compacting = false;
    }
  }

  static const _compactItemId = 'comprimiendo';

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
        errorMessage: ref.read(stringsProvider).noFolderForConversation,
      );
      return;
    }
    if (!paired.modality.allowsVoice) {
      state = state.copyWith(
        errorMessage: ref.read(stringsProvider).textOnlyFolder(paired.name),
      );
      return;
    }

    // Hablar es del foco: si esta conversación no lo tiene, se lo lleva.
    unawaited(ref.read(conversationsProvider.notifier).focus(conversationId));

    _heard.clear();
    _reply.clear();
    // `copyWith` y no un estado nuevo: construirlo de cero **borraba la
    // conversación entera**. Al tocar el orbe para hablar, los mensajes
    // desaparecían y con ellos la ventana de la derecha, así que el orbe se
    // volvía a poner en medio como si nunca hubieras dicho nada. Lo único que
    // empieza de cero al abrir la voz es la actividad de este turno.
    state = state.copyWith(
      orbState: NexusOrbState.think,
      voiceActive: true,
      isStreaming: false,
      subtitle: '',
      activity: const [],
      errorMessage: null,
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
