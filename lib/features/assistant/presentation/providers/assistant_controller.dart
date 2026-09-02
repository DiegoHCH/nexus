import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/i18n/language_preference.dart';
import 'package:nexus/core/platform/notifications_channel.dart';
import 'package:nexus/features/assistant/domain/usecases/attached_files.dart';
import 'package:nexus/features/agenda/domain/usecases/lo_que_se_pregunta_de_la_agenda.dart';
import 'package:nexus/features/agenda/presentation/providers/el_vigilante_de_la_agenda.dart';
import 'package:nexus/features/artifacts/presentation/providers/artifacts_providers.dart';
import 'package:nexus/features/artifacts/presentation/providers/generar_una_imagen.dart';
import 'package:nexus/features/artifacts/domain/usecases/lo_que_se_pide_dibujar.dart';
import 'package:nexus/features/assistant/domain/entities/claude_event.dart';
import 'package:nexus/features/assistant/domain/entities/voice_event.dart';
import 'package:nexus/features/assistant/domain/repositories/microphone_access.dart';
import 'package:nexus/features/assistant/presentation/providers/voice_input_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/claude_bridge_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/model_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/voice_session_providers.dart';
import 'package:nexus/features/assistant/presentation/state/assistant_hud_state.dart';
import 'package:nexus/features/assistant/presentation/state/chat_message.dart';
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';
import 'package:nexus/features/assistant/presentation/state/session_meter.dart';
import 'package:nexus/features/history/domain/entities/conversation_record.dart';
import 'package:nexus/features/history/domain/entities/conversation_summary.dart';
import 'package:nexus/features/history/domain/repositories/conversation_archive.dart';
import 'package:nexus/features/assistant/domain/usecases/por_que_murio_claude.dart';
import 'package:nexus/features/history/domain/usecases/el_parte_de_ayer.dart';
import 'package:nexus/features/history/presentation/providers/archive_providers.dart';
import 'package:nexus/features/history/presentation/providers/el_parte_desde_la_voz.dart';
import 'package:nexus/features/run/domain/usecases/decision_de_recarga.dart';
import 'package:nexus/features/run/presentation/providers/corridas_providers.dart';
import 'package:nexus/features/run/presentation/providers/run_providers.dart';
import 'package:nexus/features/workspace/data/datasources/git_data_source.dart';
import 'package:nexus/features/workspace/data/datasources/claude_auth_data_source.dart';
import 'package:nexus/features/workspace/data/datasources/claude_profiles_data_source.dart';
import 'package:nexus/features/workspace/domain/usecases/el_comando_directo.dart';
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

  /// Lo que se escribió mientras había un encargo corriendo.
  ///
  /// 🔴 **Enviar no interrumpe.** Antes cada mensaje nuevo cancelaba el encargo
  /// en curso, así que escribir tres cosas seguidas dejaba dos sin respuesta —y
  /// sin decir por qué: las tres se quedaban pintadas como si esperasen turno.
  /// Se reportó como «se me trabó, escribí varias veces y cuando reaccionó
  /// tenía los mensajes encolados»; no estaban encolados, estaban muertos.
  ///
  /// Se hace como el CLI, que es la referencia que la gente ya tiene en las
  /// manos: escribir mientras trabaja **encola**, y para interrumpir está el
  /// botón de Detener —el `esc to interrupt` de la terminal—. Son dos gestos
  /// distintos porque son dos intenciones distintas, y unirlos hacía que la
  /// intención más común, seguir hablando, ejecutara la más destructiva.
  final _enCola = <_Encargo>[];

  /// La pregunta que contesta el encargo en curso, si esperó turno.
  ///
  /// Solo se llena para lo que salió de la cola. En un intercambio normal la
  /// respuesta va pegada a su pregunta y citarla sería ruido; al encolar, entre
  /// las dos hay otros mensajes y el orden deja de decir a cuál contesta cada
  /// una. La cita devuelve lo que la cola se llevó.
  String? _respondiendoA;
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
    unawaited(_recuperarLoDicho());

    // Perder el foco cierra el micrófono: solo la conversación en foco puede
    // hablar, y dejarlo abierto en una que ya no miras sería exactamente el
    // estado que el proyecto lleva evitando desde 2.5.
    ref.listen(conversationsProvider, (previous, next) {
      // **Solo si el foco está en otra**, no cuando no hay foco. Sin ese matiz,
      // cualquier estado sin foco —la lista todavía sin leer, o vacía— cerraba el
      // micrófono a mitad de un turno: se veía como que la voz se corta sola, y el
      // encargo se quedaba sin terminar.
      if (!next.cargado || next.focusedId == null) return;
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
    // Sale con `unawaited`: si la pantalla se fue mientras tanto, el proveedor
    // ya no existe y esto lanzaria en vez de no hacer nada.
    if (!_vive) return;
    state = state.copyWith(history: memory.prompts);
  }

  /// Vuelve a pintar lo que ya se había dicho en esta conversación.
  ///
  /// Al reabrir la app, las conversaciones abiertas volvían **vacías**: la lista se
  /// guardaba —ids y carpetas— y los turnos no se recuperaban, aunque estuvieran en
  /// disco desde el primer encargo. El efecto es peor que perderlos: la ficha sigue
  /// ahí, con su nombre, invitando a seguir una conversación de la que no se ve nada.
  ///
  /// Lo guardado se busca **por el id de esta conversación**, que es con el que se
  /// guarda —el archivo se llama así—. Se reusa `resume`, que es exactamente esto:
  /// pintar un registro entero y seguir escribiendo en él.
  ///
  /// **Solo si no ha llegado nada todavía.** Esto es asíncrono y el usuario puede
  /// haber empezado a hablar mientras se leía el disco; sobrescribir entonces sería
  /// borrarle lo que acaba de decir.
  Future<void> _recuperarLoDicho() async {
    final folder = _folder;
    if (folder == null) return;

    // El almacén se coge **antes de cualquier espera**. Después ya no se puede:
    // esta conversación puede haberse cerrado mientras se leía el disco, y
    // preguntarle nada a un `ref` desechado revienta.
    final almacen = ref.read(localConversationStoreProvider);

    final List<ConversationSummary> guardadas;
    try {
      guardadas = await almacen.list(folder);
    } catch (error) {
      // Un historial ilegible no puede impedir abrir la conversación: se sigue en
      // blanco, que es lo que había antes de esto.
      debugPrint('archivo · no se pudo leer lo dicho: $error');
      return;
    }

    // **Que la pestaña siga viva.** Entre pedir el disco y volver puede haberse
    // cerrado, y a un `ref` desechado no se le puede preguntar nada. Recuperar
    // lo dicho en una conversación que ya no está no le sirve a nadie.
    if (!ref.mounted) return;

    // La lista, leída del disco antes de preguntarle nada: recién construida está
    // vacía, y preguntar ahí devolvía «no adoptó ningún registro» siempre.
    await ref.read(conversationsProvider.notifier).asegurarCargado();
    if (!ref.mounted) return;

    // **El registro adoptado primero.** Una conversación retomada del archivo escribe
    // en el id de ese registro, no en el suyo: buscar por el propio no encontraba nada
    // y la pestaña salía vacía.
    final buscado =
        ref
            .read(conversationsProvider)
            .items
            .where((c) => c.id == conversationId)
            .firstOrNull
            ?.recordId ??
        conversationId;
    final ficha = guardadas.where((r) => r.id == buscado).firstOrNull;
    if (ficha == null) return;
    if (state.messages.isNotEmpty) return;

    // Los mensajes se leen **solo de la que se busca**. La lista trae fichas
    // sin turnos dentro; pintar esta necesita la conversación entera, y es una
    // lectura, no todas.
    final ConversationRecord? mia;
    try {
      mia = await almacen.read(ficha);
    } catch (error) {
      debugPrint('archivo · no se pudo leer lo dicho: $error');
      return;
    }
    if (mia == null || mia.messages.isEmpty) return;
    // 🔴 Y que la pestaña siga viva, igual que arriba. Este salto se quedó sin
    // el guardia que sí tienen los dos anteriores: leer `state` de un notifier
    // desechado lanza lo mismo que escribirlo.
    if (!ref.mounted) return;
    // Se vuelve a mirar después de leer: entre una cosa y otra ha habido una
    // espera, y en ese hueco el usuario puede haber empezado a hablar.
    if (state.messages.isNotEmpty) return;

    resume(mia);
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
  void _say(
    ChatAuthor author,
    String text, {
    bool spoken = false,
    List<String> attachments = const [],
    String? respondeA,
  }) {
    state = state.copyWith(
      messages: [
        ...state.messages,
        ChatMessage(
          author: author,
          text: text,
          spoken: spoken,
          streaming: true,
          attachments: attachments,
          respondeA: respondeA,
          // Solo la respuesta, no lo que se pidió: el botón de enviar va bajo
          // el parte, y lo que se pidió es la instrucción que lo generó.
          esElParte: author == ChatAuthor.nexus && _elParteEnCurso,
        ),
      ],
    );
  }

  /// Va completando el último turno de ese autor mientras llega.
  ///
  /// El texto entra a trozos —deltas de Claude, transcripción de Gemini— y
  /// crear un mensaje por trozo llenaría la ventana de fragmentos sueltos.
  void _appendTo(
    ChatAuthor author,
    String text, {
    bool spoken = false,
    String? respondeA,
  }) {
    final messages = [...state.messages];
    final last = messages.lastOrNull;
    if (last != null && last.author == author && last.streaming) {
      messages[messages.length - 1] = last.copyWith(text: last.text + text);
      state = state.copyWith(messages: messages);
      return;
    }
    _say(author, text, spoken: spoken, respondeA: respondeA);
  }

  /// Cierra el turno en curso: se le quita el cursor.
  /// Corre lo que se pidió con `!` y enseña lo que git contestó.
  ///
  /// 🔴 **La lista de comandos vetados de la carpeta no ata aquí, y es
  /// deliberado.** Esa lista existe para lo contrario: su propio texto le dice a
  /// Claude «no los ejecutes, y termina diciendo el comando exacto que tiene que
  /// lanzar el usuario». O sea que está pensada para acabar justo aquí. Si el
  /// `!` la respetara, Claude te pasaría un comando que la caja de texto te
  /// niega, y el círculo se cerraría en el sitio equivocado.
  ///
  /// No es un agujero en la promesa del repo: lo que `.nexus/config.json`
  /// declara es qué **no hace Claude solo**, y eso sigue intacto. Lo que tú
  /// escribes con un `!` delante lo has escrito tú.
  Future<void> _correrloYo(
    ({String comando, List<String> argumentos}) directo, {
    required String loQueSeVe,
  }) async {
    final s = ref.read(stringsProvider);
    _say(ChatAuthor.user, loQueSeVe);
    _sealLast();

    if (directo.comando != ElComandoDirecto.soloEste) {
      _say(ChatAuthor.nexus, s.soloGit(directo.comando));
      _sealLast();
      return;
    }

    final carpeta = _workingDirectory;
    if (carpeta == null) {
      _say(ChatAuthor.nexus, s.sinCarpetaDondeCorrer);
      _sealLast();
      return;
    }

    // 🔴 **Dónde se corrió, dicho siempre.** La salida de git no lo dice, y la
    // primera vez que esto se usó de verdad contestó sobre un repo que no era
    // el que se esperaba —la conversación en foco iba de otra carpeta— y lo
    // único que lo delató fue que el nombre de una rama sonaba a otro
    // proyecto. Con `!git log` o `!git stash` no habría habido ni esa pista, y
    // ahí lo que está en juego es un stash en el repo equivocado.
    //
    // Y es además lo único que se puede decir en español: git en este Mac no
    // trae traducciones, así que sus palabras van a seguir siendo inglesas
    // haga lo que haga el `LC_ALL`. Lo que Nexus pone alrededor sí es tuyo.
    final donde = await const GitDataSource().read(carpeta);
    final hecho = await const GitDataSource().correr(
      carpeta,
      directo.argumentos,
    );
    if (!ref.mounted) return;

    final cabecera = s.dondeSeCorrio(
      donde?.repository ?? carpeta.split('/').last,
      donde?.branch ?? '—',
    );

    // **Lo de git dentro del bloque, lo de Nexus fuera.** La salida va literal
    // y monoespaciada porque es lo que se vino a ver —`git log --oneline` es una
    // tabla y se lee alineada o no se lee—, y las frases de Nexus van en prosa
    // porque no son salida de nada: son la cabecera que dice dónde se corrió y,
    // si hizo falta, el aviso de que git terminó con error. Un código distinto
    // de cero con la salida en blanco es un fallo mudo, y eso se lee como que
    // la app no hizo nada.
    _say(
      ChatAuthor.nexus,
      [
        '**$cabecera**',
        if (hecho.tardoDemasiado)
          s.tardoDemasiado
        else ...[
          if (hecho.codigo != 0) s.gitFallo(hecho.codigo),
          if (hecho.salida.isEmpty)
            if (hecho.codigo == 0) s.sinNadaQueDecir else ''
          else
            ElComandoDirecto.enBloque(hecho.salida),
        ],
      ].where((linea) => linea.isNotEmpty).join('\n\n'),
    );
    _sealLast();

    // 🔴 **Y se archiva, como los otros tres caminos.** Faltaba, y el síntoma no
    // se parecía a la causa: una conversación cuyos únicos turnos fueran `!`
    // volvía **vacía** al relanzar la app, y eso se lee como «Nexus no guarda
    // las conversaciones» y no como «este camino se olvidó de guardar».
    //
    // Los otros tres —el encargo, la imagen, la voz— llaman a [_archive] al
    // terminar su turno. Este copió de ahí el `_say` y el `_sealLast` y se dejó
    // justo la línea que persiste, que es la única que no se nota hasta que
    // reinicias.
    unawaited(_archive());
  }

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

  /// [allowWrites] es un **tope y no un permiso**: baja lo que la carpeta concede,
  /// nunca lo sube. Lo usa el canal del teléfono, que manda `false` mientras no
  /// tenga abierta la frase de escritura.
  Future<void> submit(
    String instruction, {
    List<String> attachments = const [],
    bool allowWrites = true,
    bool esElParte = false,
    String? loQueSeVe,
    bool reintento = false,
    bool yaEstaDicho = false,
  }) async {
    final trimmed = instruction.trim();
    if (trimmed.isEmpty && attachments.isEmpty) return;

    // Escribir «dame el daily» es pedir el parte, no encargarle esa frase a
    // Claude: él no tiene delante lo de ayer, así que contestaba algo con cara
    // de parte que no lo era —y sin el botón para mandarlo—. Se desvía aquí y
    // no en el compositor porque por escrito también se pide desde el móvil, y
    // el atajo tiene que valer por los dos sitios.
    // `/imagen una cosa` no es un encargo para Claude: **no pasa por él**.
    // Va derecho a Gemini, que es quien dibuja, y el resultado cae en la
    // carpeta de documentos como cualquier otra cosa que produce Nexus.
    //
    // Se desvía aquí y no en el compositor por lo mismo que el parte: por
    // escrito también se pide desde el móvil, y el atajo tiene que valer por
    // los dos sitios.
    // **Con adjuntos vale igual**, y por eso no se exige que no los haya: lo
    // que se suelta en la caja son las imágenes de referencia —«este estilo»,
    // «cámbiale esto»—, así que aquí son material y no un motivo para no
    // reconocer el atajo.
    // `!git status` no es un encargo: **no pasa por Claude**. Va derecho a git y
    // la salida se enseña literal, que es lo que uno quiere de git — no un
    // resumen de la salida de git.
    //
    // Va antes que los demás atajos porque es el único que no puede colisionar
    // con nada: `!` no empieza ninguna frase que alguien escriba en serio.
    if (!esElParte) {
      if (ElComandoDirecto.deLaFrase(trimmed) case final directo?) {
        await _correrloYo(directo, loQueSeVe: loQueSeVe ?? trimmed);
        return;
      }
    }

    if (!esElParte) {
      if (LoQueSePideDibujar.deLaFrase(trimmed) case final descripcion?) {
        await _dibujar(
          descripcion,
          loQueSeVe: loQueSeVe ?? trimmed,
          referencias: attachments,
          reintento: reintento,
        );
        return;
      }
      if (LoQueSePideDibujar.loQueSeCambia(trimmed) case final cambio?) {
        // Sin nada anterior no hay qué editar, y decirlo es mejor que dibujar
        // desde cero algo que no era lo que se pidió — y cobrarlo.
        if (_laUltimaImagen == null) {
          _say(ChatAuthor.user, loQueSeVe ?? trimmed);
          _sealLast();
          _say(ChatAuthor.nexus, ref.read(stringsProvider).noImageToEdit);
          _sealLast();
          return;
        }
        await _dibujar(
          cambio,
          loQueSeVe: loQueSeVe ?? trimmed,
          referencias: attachments,
          siguiendo: true,
          reintento: reintento,
        );
        return;
      }
    }

    // «¿Qué reuniones tengo hoy?» **no vuelve a Claude**: la app ya leyó el
    // calendario para poder avisar, así que la respuesta está en memoria.
    // Mandar un encargo para releer lo mismo cuesta un minuto de espera y
    // tokens de la suscripción, y devuelve exactamente lo que ya se tiene.
    //
    // Si no hay agenda que mirar —avisos apagados, sin carpeta— devuelve `null`
    // y esto sigue de largo hacia Claude, que sí puede salir a preguntarlo.
    if (!esElParte &&
        attachments.isEmpty &&
        LoQueSePreguntaDeLaAgenda.loEstanPidiendo(trimmed)) {
      // 🔴 La misma espera que hablando: si la lectura del día va en vuelo,
      // esto son los 32 s del `claude -p` con el conector. Escribiendo no mata
      // ninguna sesión, pero sí puede volver a una conversación ya cerrada.
      final agendaDeHoy = await ref.read(laAgendaDeHoyProvider).deHoy();
      if (!_vive) return;
      if (agendaDeHoy case final agenda?) {
        _say(ChatAuthor.user, loQueSeVe ?? trimmed);
        _sealLast();
        _say(ChatAuthor.nexus, agenda);
        _sealLast();
        return;
      }
    }

    if (!esElParte &&
        attachments.isEmpty &&
        ElParteDeAyer.loEstanPidiendo(trimmed)) {
      if (await pedirElParte(loQueSeVe: trimmed)) return;
      // Sin día que contar se dice y no se le pide a Claude que se lo invente:
      // un parte de la nada se lee igual de convincente que uno de verdad.
      _say(ChatAuthor.user, trimmed);
      _sealLast();
      _say(ChatAuthor.nexus, ref.read(stringsProvider).parteSinDia);
      _sealLast();
      return;
    }

    // Lo que se le manda a Claude lleva las rutas detrás —las necesita para
    // abrir los archivos—; lo que se enseña en la conversación, no. Antes eran
    // el mismo texto y por eso el chat mostraba rutas absolutas en vez del
    // archivo.
    final paraClaude = AttachedFiles.instruction(
      trimmed,
      attachments,
      label: ref.read(stringsProvider).attachedFilesLabel,
    );

    // Hay algo corriendo: se encola y se sale. Un reintento no, que es
    // precisamente volver a lanzar lo que acaba de fallar.
    if (_subscription != null && !reintento && !yaEstaDicho) {
      _say(ChatAuthor.user, loQueSeVe ?? trimmed, attachments: attachments);
      _sealLast();
      _enCola.add(
        _Encargo(
          instruction: instruction,
          attachments: attachments,
          allowWrites: allowWrites,
          esElParte: esElParte,
          loQueSeVe: loQueSeVe,
        ),
      );
      return;
    }

    _sealLast();
    _respondiendoA = yaEstaDicho ? (loQueSeVe ?? trimmed) : null;
    _elParteEnCurso = esElParte;
    final buffer = StringBuffer();
    state = state.copyWith(
      orbState: NexusOrbState.think,
      subtitle: '',
      isStreaming: true,
      activity: const [],
      errorMessage: null,
      laSesionCaduco: false,
      // El aviso también es del turno anterior. Si las reglas siguen
      // cambiadas, este encargo lo vuelve a decir; si no, ya se leyó.
      notice: null,
      // Los cambios del turno anterior se van con él: son de esa tarea.
      changes: null,
      history: _remember(paraClaude),
    );
    // Lo que se ve puede no ser lo que se manda: quien escribe «dame el daily»
    // pidió dos palabras, y enseñarle en su sitio las cuarenta líneas de
    // material que salieron hacia Claude no le dice nada.
    // **Un reintento no se vuelve a escribir**: el mensaje ya está en la
    // conversación, y añadirlo otra vez dejaría la misma petición dos veces
    // seguidas con una sola respuesta debajo. Lo que se pidió fue reintentar
    // *eso*, no mandarlo de nuevo.
    if (reintento) {
      _quitaLaMarcaDeFallo();
    } else if (!yaEstaDicho) {
      _say(ChatAuthor.user, loQueSeVe ?? trimmed, attachments: attachments);
      _sealLast();
    }
    // La marca se toma **antes** de que Claude toque nada: es lo que hace que
    // al terminar se pueda enseñar lo de esta tarea y no lo de toda la tarde.
    unawaited(_markRepo());

    final ask = ref.read(askClaudeProvider(conversationId));
    _subscription = ask(paraClaude, allowWrites: allowWrites).listen(
      (event) => switch (event) {
        ClaudeQueued() => _onQueued(),
        ClaudeRulesChanged() => _onRulesChanged(event.paths),
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

  /// El paso que se enseña mientras se dibuja. Uno solo: no hay herramientas
  /// que listar, hay una espera — pero una espera de veinte segundos sin nada
  /// en pantalla se lee igual que un cuelgue.
  static const _dibujoId = 'dibujando';

  /// `/imagen …`: se genera, se guarda y se enseña. Sin pasar por Claude.
  /// La última imagen que salió de esta conversación.
  ///
  /// Es lo que permite `/edita`: a la API se le manda **el identificador** de
  /// aquella interacción en vez del PNG entero, así que encadenar cambios no
  /// cuesta resubir la imagen en cada vuelta.
  ///
  /// Vive en el controlador y no en el estado porque no se pinta: es una pista
  /// para la petición siguiente. Y por conversación, que es lo que hace que
  /// «la anterior» signifique algo — con una global, editar en una pestaña
  /// seguiría de lo que se dibujó en otra.
  String? _laUltimaImagen;

  Future<void> _dibujar(
    String descripcion, {
    required String loQueSeVe,
    List<String> referencias = const [],
    bool siguiendo = false,
    bool reintento = false,
  }) async {
    await _subscription?.cancel();
    // Cancelar **espera a que el generador llegue a un punto donde pueda
    // parar**, y uno detenido en un `await` que no vuelve tarda lo que tarde:
    // está medido y escrito en `stopWork`. Ese es el hueco.
    if (!_vive) return;
    _sealLast();
    final strings = ref.read(stringsProvider);

    state = state.copyWith(
      orbState: NexusOrbState.think,
      subtitle: '',
      isStreaming: false,
      errorMessage: null,
      notice: null,
      // Los cambios del turno anterior se van con él, igual que en un encargo.
      changes: null,
      activity: [
        ActivityItem(
          id: _dibujoId,
          description: strings.drawingIt,
          writes: true,
        ),
      ],
    );
    // 🔴 **Un reintento no se vuelve a escribir.** El desvío de `/imagen` ocurre
    // antes de donde `submit` decide eso, así que si no se trae la bandera hasta
    // aquí, pulsar «reintentar» dejaba la misma petición dos veces seguidas con
    // una sola respuesta debajo. Y con las imágenes pasa más que con nada: el
    // modelo se satura y contesta «vuelve a intentarlo más tarde».
    //
    // Los adjuntos van en el mensaje: son parte de lo que se pidió y se ven en
    // su miniatura, igual que en un encargo normal.
    if (reintento) {
      _quitaLaMarcaDeFallo();
    } else {
      _say(ChatAuthor.user, loQueSeVe, attachments: referencias);
      _sealLast();
    }

    // Con la cuenta de la carpeta donde se está trabajando: la llave de
    // imágenes es por cuenta, así que pedir un dibujo desde una carpeta del
    // trabajo no puede gastar del saldo personal.
    final carpeta = _folder;
    final salio = await ref.read(generarUnaImagenProvider)((
      descripcion: descripcion,
      perfil: carpeta == null ? null : _cuentaDe(carpeta),
      seguirDe: siguiendo ? _laUltimaImagen : null,
      referencias: referencias,
    ));
    // La generación tarda, y en ese rato la pestaña se puede haber cerrado.
    if (!_vive) return;

    // Se apunta antes de pintar nada: es lo que hace que el siguiente `/edita`
    // siga de ésta. Solo si salió — encadenar sobre una que falló no existe.
    if (salio.id case final id?) _laUltimaImagen = id;

    final texto = switch (salio.problema) {
      null => strings.imageDone(salio.ruta!.split('/').last),
      'sin-llave' => strings.imageNeedsKey,
      'sin-carpeta' => strings.imageNeedsFolder,
      final motivo => strings.imageFailed(motivo),
    };

    state = state.copyWith(
      orbState: NexusOrbState.sleep,
      isStreaming: false,
      activity: [for (final paso in state.activity) paso.asDone()],
      // Lo que falló se marca en tu mensaje, igual que un encargo caído: el
      // botón de reintentar vale aquí exactamente igual — y con más motivo,
      // porque volver a escribir la descripción es lo caro.
    );
    _say(ChatAuthor.nexus, texto);
    _sealLast();
    if (salio.ruta case final ruta?) {
      _sellarEnElMensaje(documento: ruta);
    } else {
      _marcaElFallo();
    }

    // 🔴 Se archiva, pero **no se llama a `_afterErrand`**: ahí dentro está el
    // diff de la tarea, y esto no tocó el repositorio. Con la marca de git de un
    // encargo anterior todavía en memoria, enseñaría los cambios de aquél como
    // si los hubiera hecho el dibujo.
    unawaited(_archive());
  }

  /// Vuelve a mandar un encargo que no llegó a hacerse.
  ///
  /// Pedido mirándolo: cuando algo falla, la única salida era **copiar el
  /// mensaje y pegarlo otra vez**. La petición ya está escrita ahí; volver a
  /// teclearla es trabajo que la app puede ahorrarse.
  ///
  /// Se reconstruye desde lo que se ve más los adjuntos, y no desde el texto
  /// que salió hacia Claude —que llevaba las rutas pegadas detrás y no se
  /// guarda—: `submit` lo vuelve a componer igual que la primera vez, así que
  /// el reintento manda exactamente lo mismo.
  Future<void> reintentar(ChatMessage fallido) =>
      submit(fallido.text, attachments: fallido.attachments, reintento: true);

  /// La marca se quita de **todos**, no solo del que se reintenta.
  ///
  /// Solo puede haber un encargo en marcha, así que un intento nuevo deja sin
  /// sentido cualquier «esto se quedó a medias» anterior. Quitarla de uno solo
  /// dejaría botones de reintentar por la conversación que ya no reintentan
  /// nada.
  void _quitaLaMarcaDeFallo() {
    if (!state.messages.any((mensaje) => mensaje.fallo)) return;
    state = state.copyWith(
      messages: [
        for (final mensaje in state.messages)
          mensaje.fallo ? mensaje.copyWith(fallo: false) : mensaje,
      ],
    );
  }

  /// Lo que se pidió y no se hizo, marcado en su propio mensaje.
  ///
  /// El tuyo y no el suyo: un fallo no deja respuesta que marcar, y lo que se
  /// reintenta es la petición. Se busca el último tuyo porque un fallo puede
  /// llegar con texto a medias ya escrito debajo, y entonces el último mensaje
  /// de la lista es de Nexus.
  void _marcaElFallo() {
    final mensajes = [...state.messages];
    final donde = mensajes.lastIndexWhere(
      (mensaje) => mensaje.author == ChatAuthor.user,
    );
    if (donde == -1) return;
    mensajes[donde] = mensajes[donde].copyWith(fallo: true);
    state = state.copyWith(messages: mensajes);
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
    // La cita solo cuaja al **crear** el mensaje: `_appendTo` la ignora cuando
    // está alargando el que ya hay, así que las porciones siguientes no la
    // repiten ni la borran.
    _appendTo(ChatAuthor.nexus, event.text, respondeA: _respondiendoA);
    state = state.copyWith(orbState: NexusOrbState.speak, isStreaming: true);
  }

  /// Dónde estaba el repositorio antes de este encargo.
  String? _repoBase;

  /// Y qué documentos había antes, para saber cuál salió de aquí.
  Set<String> _documentosAntes = const {};

  /// Y qué archivos había ya sin trackear. La marca de git tiene dos mitades y
  /// esta faltaba: `stash create` no ve lo que git no sigue, así que sin esto
  /// cualquier archivo suelto de ayer contaba como creado por este encargo.
  Set<String> _sinTrackearAntes = const {};

  /// ¿Sigue existiendo esta conversación?
  ///
  /// 🔴 **Media docena de cosas del final de un encargo salen con `unawaited`**
  /// —la marca del repo, el diff, el archivado, mirar si salió un documento— y
  /// todas tocan `ref` o `state` **después de un `await`**. Si la pestaña se
  /// cierra mientras tanto, el proveedor ya no existe y eso lanza en vez de no
  /// hacer nada.
  ///
  /// Lo destapó el CI, no la máquina de nadie: en local el trabajo pendiente
  /// solía terminar antes de que se desmontara el proveedor y no se veía. Es la
  /// clase de fallo que solo asoma cuando la máquina va lenta — o cuando el
  /// usuario cierra la pestaña justo después de mandar algo, que es exactamente
  /// cuando esto ocurre de verdad.
  bool get _vive => ref.mounted;

  Future<void> _markRepo() async {
    final folder = _workingDirectory;
    if (folder == null) {
      _repoBase = null;
      _sinTrackearAntes = const {};
    } else {
      const git = GitDataSource();
      _repoBase = await git.snapshot(folder);
      _sinTrackearAntes = await git.sinTrackear(folder);
    }
    if (!_vive) return;
    _documentosAntes = await _documentosAhora();
  }

  /// Las rutas de los documentos que hay ahora mismo en el cajón.
  ///
  /// Se comparan antes y después por la misma razón que el repositorio: lo que
  /// interesa es **lo que dejó este encargo**, no todo lo que hay en la carpeta.
  Future<Set<String>> _documentosAhora() async {
    if (!_vive) return const {};
    final carpeta = ref.read(artifactsFolderProvider);
    if (carpeta == null) return const {};
    final cuentas = ref
        .read(claudeProfilesProvider)
        .value
        ?.map((perfil) => perfil.name)
        .toSet();
    final lista = await ref
        .read(artifactsDataSourceProvider)
        .list(carpeta, cuentas: cuentas ?? const {});
    return {for (final documento in lista) documento.path};
  }

  /// Qué dejó tocado, si tocó algo.
  Future<void> _readChanges() async {
    final folder = _workingDirectory;
    final base = _repoBase;
    if (folder == null || base == null) return;
    final cambios = await const GitDataSource().changesSince(
      folder,
      base,
      yaEstaban: _sinTrackearAntes,
    );
    if (cambios == null || !_vive) return;
    state = state.copyWith(changes: cambios);
    _sellarEnElMensaje(cambios: cambios);

    // **Y si hay una app corriendo de este proyecto, se recarga sola.**
    //
    // Aquí y no al guardar cada archivo: quien guarda es Claude, veinte
    // ediciones en un encargo, y una recarga por escritura sería un bucle de
    // recompilaciones sobre código a medio escribir. Al terminar el encargo el
    // cambio está completo, que es cuando tiene sentido mirarlo.
    //
    // Se aprovecha el diff que este método ya calculaba para el resumen: pedirlo
    // otra vez sería un `git diff` más por el mismo dato.
    if (!ref.read(autoRecargaProvider)) return;
    await ref
        .read(corridasProvider.notifier)
        .alTerminarUnEncargo(
          proyecto: folder,
          rutas: [
            ...QueHacerConElCambio.rutasDelDiff(cambios.diff),
            ...cambios.newFiles,
          ],
          diff: cambios.diff,
        );
  }

  /// Donde trabaja Claude: el repo elegido dentro de la carpeta, o la carpeta.
  String? get _workingDirectory {
    final folder = _folder;
    if (folder == null) return null;
    return ref
            .read(workspaceControllerProvider)
            .folders
            .where((item) => item.path == folder)
            .firstOrNull
            ?.workingDirectory ??
        folder;
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
    _afterErrand();
  }

  /// Si el encargo en curso es el parte del día.
  ///
  /// **Se pone al empezar y se lee al crear el mensaje**, no minutos después al
  /// sellarlo. La primera versión lo consumía en `_afterErrand` —a un turno
  /// entero de distancia— y el botón no aparecía: entre medias cabe cualquier
  /// cosa que reconstruya el estado, y una marca que depende de sobrevivir a
  /// eso no es una marca. Naciendo marcado, el botón está desde la primera
  /// palabra de la respuesta.
  bool _elParteEnCurso = false;

  /// Pide el parte del último día con trabajo.
  ///
  /// **Lo redacta Claude**: aquí solo se junta el material —qué conversaciones
  /// hubo ese día, en qué carpetas y con cuántos turnos— y se le pone delante.
  /// Devuelve `false` si no hay ningún día anterior que contar, que es distinto
  /// de fallar: se dice y no se le pide un parte de la nada.
  Future<bool> pedirElParte({String? loQueSeVe}) async {
    final instruccion = await laInstruccionDelParte(ref);
    if (instruccion == null) return false;

    // Sin escritura: un parte se escribe leyendo, y esto lo puede pedir alguien
    // que no tiene por qué darle permiso de escribir para contar lo que hizo.
    await submit(
      instruccion,
      allowWrites: false,
      esElParte: true,
      loQueSeVe: loQueSeVe,
    );
    return true;
  }

  /// Deja en la conversación un parte que se pidió **hablando**.
  ///
  /// Hace falta un camino aparte porque hablando el encargo no pasa por
  /// [submit]: lo lleva la conversación de voz, y lo que Claude devuelve
  /// alimenta la narración, no el chat. Sin esto el parte se oiría y no
  /// quedaría en ninguna parte — ni el texto, ni el botón para mandarlo.
  ///
  /// Se sella lo anterior y lo siguiente: entre medias llega la narración del
  /// modelo de voz, que es otro turno y no puede acabar pegada al parte.
  void dejarElParte(String parte) {
    _sealLast();
    _elParteEnCurso = true;
    _say(ChatAuthor.nexus, parte);
    _sealLast();
    _elParteEnCurso = false;
  }

  /// Deja en el último mensaje de Nexus lo que este encargo produjo.
  ///
  /// **En el mensaje y no solo en la pantalla**, que es donde vivía: el estado
  /// guarda uno y lo pisa el siguiente, así que al subir por la conversación el
  /// segundo encargo borraba de la vista lo que había hecho el primero. Cada
  /// turno se queda con lo suyo.
  void _sellarEnElMensaje({
    GitChanges? cambios,
    String? documento,
    List<ActivityItem>? actividad,
  }) {
    final mensajes = [...state.messages];
    final donde = mensajes.lastIndexWhere(
      (mensaje) => mensaje.author == ChatAuthor.nexus,
    );
    if (donde == -1) return;
    mensajes[donde] = mensajes[donde].copyWith(
      cambios: cambios,
      documento: documento,
      actividad: actividad,
    );
    state = state.copyWith(messages: mensajes);
  }

  /// El documento que salió de este encargo, si salió alguno.
  ///
  /// El más reciente de los que no estaban antes. Si un encargo produjo dos, se
  /// ofrece el último: son las notas de la misma tarea y el botón lleva a la
  /// carpeta igual, con el resto al lado.
  Future<void> _mirarSiHayDocumento() async {
    final ahora = await _documentosAhora();
    final nuevos = ahora.difference(_documentosAntes);
    if (nuevos.isEmpty || !_vive) return;
    ref.invalidate(artifactsProvider);
    _sellarEnElMensaje(documento: nuevos.last);
  }

  /// Lo que hay que hacer cuando un encargo termina, **venga de donde venga**.
  ///
  /// Vivía dentro de [_onTurnCompleted], que solo corre escribiendo: hablando,
  /// los turnos de Claude los consume el caso de uso de voz y no llegan aquí.
  /// El resultado era que una conversación entera por voz no releía la rama, no
  /// miraba los cambios y —lo peor— **no se guardaba en el historial**, porque
  /// `_archive` colgaba de aquí y de ningún otro sitio.
  void _afterErrand() {
    // **Los pasos se cuelgan del mensaje antes que nada**, y por eso van
    // síncronos: `_archive()` sale unas líneas más abajo, y si el sellado
    // esperara a un `await` el registro se guardaría sin ellos y solo los
    // recogería el turno siguiente. Es el mismo cuidado que ya pedían los
    // cambios, con el agravante de que la actividad se borra al empezar el
    // encargo que viene — lo que no quede sellado aquí no existe después.
    if (state.activity.isNotEmpty) {
      _sellarEnElMensaje(actividad: state.activity);
    }
    // La rama puede haber cambiado durante el encargo —se lo pediste tú, o
    // Claude hizo checkout—, así que se relee en vez de dejar la de antes.
    if (_folder case final folder?) ref.invalidate(gitInfoProvider(folder));
    unawaited(_readChanges());
    unawaited(_mirarSiHayDocumento());
    _elParteEnCurso = false;
    // Lo que se escribió mientras trabajaba, ahora. Uno cada vez y por orden:
    // soltarlos todos de golpe volvería a ser el fallo de antes con otra cara,
    // porque cada uno cancelaría al anterior.
    //
    // La suscripción se suelta antes de lanzar el siguiente, o la guarda de
    // `submit` lo tomaría por «hay algo corriendo» y lo volvería a encolar
    // para siempre.
    if (_enCola.isNotEmpty) {
      final siguiente = _enCola.removeAt(0);
      _subscription = null;
      unawaited(
        submit(
          siguiente.instruction,
          attachments: siguiente.attachments,
          allowWrites: siguiente.allowWrites,
          esElParte: siguiente.esElParte,
          loQueSeVe: siguiente.loQueSeVe,
          yaEstaDicho: true,
        ),
      );
    }
    unawaited(_archive());
    unawaited(_compactIfNeeded());
    unawaited(_avisar(ref.read(stringsProvider).errandDone));
  }

  /// El aviso de que ya está, con **el nombre de la carpeta y nada más**.
  ///
  /// No va ni un trozo de la respuesta: lo que se escribe en un aviso acaba en la
  /// base de datos de notificaciones del sistema, y meter ahí lo que Claude leyó
  /// de tu repo sería sacarlo de la app por una puerta que nadie ha mirado. Es la
  /// misma idea que i5, aplicada a otro sitio.
  Future<void> _avisar(String texto) async {
    final folder = _folder;
    await NotificationsChannel.notify(
      title: folder == null ? 'Nexus' : folder.split('/').last,
      body: texto,
    );
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
    // Los dos fallos se recogen y se cuentan **al final, en un solo aviso**.
    // Antes cada uno solo hacía `debugPrint`: si el vault ya no existía, la
    // conversación se perdía y la app no decía nada — te enterabas el día que
    // ibas a buscar la nota, cuando ya no había forma de recuperarla. Y es la
    // peor clase de silencio, porque no se repite: la conversación ya terminó.
    var falloLocal = false;

    try {
      await ref.read(localConversationStoreProvider).save(record);
      if (!_vive) return;
      ref.invalidate(savedConversationsProvider(folder));
    } catch (error) {
      falloLocal = true;
      debugPrint('archivo · no se pudo guardar en local: $error');
    }

    // **Resolver el destino también va dentro del try.** Estaba fuera, y eso
    // contradecía el párrafo de arriba: si averiguar cuál es el destino
    // externo fallaba —un vault que ya no está, una preferencia a medio
    // escribir—, `_archive` lanzaba desde dentro de un `unawaited` y quedaba
    // como error sin atrapar. El historial local ya estaba guardado, así que
    // no se perdía nada; lo que se llevaba por delante era el silencio.
    var falloElDestino = false;
    try {
      final archive = await ref.read(conversationArchiveProvider.future);
      if (archive != null) await archive.save(record);
    } catch (error) {
      // Que falle guardar no puede tumbar la conversación: la carpeta puede
      // haberse desconectado, o el vault puede no existir ya. Se dice y se
      // sigue — el historial de la app nunca depende del destino externo.
      falloElDestino = true;
      debugPrint('archivo · no se pudo archivar: $error');
    }

    // 🔴 **Un solo `if (!_vive)` y aquí abajo, que es donde faltaba.**
    //
    // Todo lo que queda necesita `ref` —el nombre del destino, los textos, el
    // estado— y esto corre después de dos `await` que pueden tardar: si la
    // conversación se cerró mientras se archivaba, el proveedor ya no existe y
    // leerlo lanza «Cannot use the Ref … after it has been disposed». Y lanza
    // desde dentro de un `unawaited`, así que no lo atrapa nadie.
    //
    // Arriba ya había un guardia igual, pero **cubría solo la escritura local**
    // y se quedó a medio camino: el destino externo es justo el que más tarda,
    // porque sale de la máquina. Salió en CI, donde la carrera se pierde.
    //
    // Sin aviso no se pierde nada: si el proveedor está muerto no hay pantalla
    // donde ponerlo, y el historial local ya está escrito o ya se dijo por qué
    // no.
    if (!_vive) return;
    _reportArchiveFailure(
      local: falloLocal,
      destination: falloElDestino ? _destinationName() : null,
    );
  }

  /// El aviso, uno solo y con **dónde** se intentó guardar.
  ///
  /// «No se pudo archivar» a secas no sirve de nada: lo que hace falta saber es
  /// si la conversación está a salvo en el historial de la app o si se ha
  /// perdido del todo, porque una cosa se arregla luego y la otra no.
  void _reportArchiveFailure({required bool local, String? destination}) {
    if (!local && destination == null) return;

    final strings = ref.read(stringsProvider);
    state = state.copyWith(
      errorMessage: switch ((local, destination)) {
        (true, final destino?) => strings.archiveFailedBoth(destino),
        (true, _) => strings.archiveFailedLocal,
        // Solo el externo: el historial de la app lo tiene, y decirlo es la
        // mitad útil del aviso.
        (_, final destino?) => strings.archiveFailedExternal(destino),
        _ => null,
      },
    );
  }

  /// Cómo se llama el destino elegido, tal como se lee en Ajustes.
  String _destinationName() {
    final strings = ref.read(stringsProvider);
    return switch (ref.read(archiveControllerProvider).destination) {
      ArchiveDestination.folder => strings.archiveFolder,
      ArchiveDestination.obsidian => strings.archiveObsidian,
      ArchiveDestination.notion => strings.archiveNotion,
      ArchiveDestination.none => strings.archiveNone,
    };
  }

  /// `work`, `private`… tal como se llama la cuenta elegida para esta carpeta.
  /// La cuenta de Claude de esa carpeta, con la derivación canónica.
  ///
  /// 🔴 No se reusa [_profileName], que es la del vault y **no es la misma**:
  /// aquella devuelve `.claude` para la cuenta de siempre y ésta devuelve
  /// `null`, que es lo que espera el llavero. Con la otra, la llave se
  /// guardaría bajo un nombre y se buscaría bajo otro.
  String? _cuentaDe(String folder) => ClaudeProfile.nameFromPath(
    ref
        .read(workspaceControllerProvider)
        .folders
        .where((item) => item.path == folder)
        .firstOrNull
        ?.claudeProfile,
  );

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
    // **Y se apunta en la lista guardada.** Adoptar el registro solo en memoria era lo
    // que hacía que al reabrir la app la conversación volviera vacía: la recuperación
    // buscaba un fichero con el id de la conversación, y esta escribe en el del
    // registro adoptado.
    unawaited(
      ref
          .read(conversationsProvider.notifier)
          .apuntarRegistro(conversationId, record.id),
    );
    _startedAt = record.startedAt;
    state = state.copyWith(
      messages: record.messages,
      subtitle: '',
      activity: const [],
      errorMessage: null,
      notice: null,
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
    int? medido;
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
          medido = contextTokens;
          if (!_vive) return;
          state = state.copyWith(
            meter: state.meter.copyWith(contextTokens: contextTokens),
          );
        }
      }
      // 🔴 **El plazo más largo de todos los `unawaited` de esta clase.**
      // `/compact` es un turno entero de Claude —un minuto largo— y no cuelga
      // de `_subscription`, así que el `onDispose` que cancela las
      // suscripciones no lo alcanza: cerrar la conversación mientras comprime
      // dejaba todo lo de abajo tocando `state` sobre un proveedor muerto.
      if (!_vive) return;
      _onClaudeToolFinished(_compactItemId);

      // **Solo se anuncia una bajada si de verdad se midió otra vez.**
      //
      // `copyWith` conserva el valor anterior cuando le llega `null`, así que
      // un `/compact` que no reporta contexto dejaba el medidor intacto — y el
      // aviso salía como «el contexto baja del 132 % al 132 %», que además de
      // no decir nada hacía dudar de si la compresión había hecho algo. Sí la
      // hizo: lo que faltaba era la medida nueva, que llega con el turno
      // siguiente.
      final after = medido == null ? null : state.meter.contextPercent;
      if (after != null && after != before) {
        _say(ChatAuthor.nexus, strings.compacted(before, after));
        _sealLast();
      } else {
        _say(ChatAuthor.nexus, strings.compactedUnknown);
        _sealLast();
      }
    } catch (error) {
      // Que falle la compresión no puede tumbar la conversación: se sigue con
      // el contexto lleno, que es exactamente como se estaba antes. Y el mismo
      // guardia: por aquí también se pasa después del turno.
      if (!_vive) return;
      _onClaudeToolFinished(_compactItemId);
    } finally {
      // Fuera del guardia a propósito: es un campo, no el estado, y dejarlo en
      // `true` bloquearía la compresión de la siguiente conversación que use
      // este mismo notifier.
      _compacting = false;
    }
  }

  static const _compactItemId = 'comprimiendo';

  void _onFailed(String message) {
    _sealLast();
    _marcaElFallo();
    state = state.copyWith(
      orbState: NexusOrbState.sleep,
      isStreaming: false,
      errorMessage: _loQuePaso(message),
      laSesionCaduco: PorQueMurioClaude.esSesionCaducada(message),
    );
    // También cuando falla, y sobre todo cuando falla: si te fuiste a otra cosa,
    // enterarte tarde de que no se hizo es peor que enterarte tarde de que sí.
    unawaited(_avisar(ref.read(stringsProvider).errandFailed));
  }

  /// Entra en la cuenta de esta carpeta, abriendo el navegador.
  ///
  /// **Aquí y no en Ajustes** porque es aquí donde te enteras: el fallo dice
  /// qué cuenta caducó y el botón está debajo. Mandar a buscar la pantalla de
  /// cuentas sería dejar a medias justo el paso que se puede dar solo.
  Future<void> entrarConLaCuenta() async {
    final strings = ref.read(stringsProvider);
    final perfil = _perfilDeLaCarpeta();
    final cuenta =
        ClaudeProfile.nameFromPath(perfil) ?? strings.laCuentaDeSiempre;

    state = state.copyWith(
      errorMessage: null,
      laSesionCaduco: false,
      notice: strings.entrandoEnLaCuenta(cuenta),
    );

    final resultado = await ref.read(claudeAuthProvider).entrar(perfil);
    if (!ref.mounted) return;

    // Las cuentas se leyeron una vez al abrir Ajustes; si ahí decía «sin
    // sesión», ahora dice otra cosa.
    ref.invalidate(claudeProfilesProvider);
    state = switch (resultado.como) {
      ComoAcabo.entro => state.copyWith(notice: strings.entroLaCuenta),
      ComoAcabo.seAgotoElPlazo => state.copyWith(
        notice: null,
        errorMessage: strings.nadieTerminoDeEntrar,
      ),
      ComoAcabo.fallo => state.copyWith(
        notice: null,
        errorMessage: resultado.detalle,
      ),
    };
  }

  /// La cuenta con la que corre esta carpeta, o `null` si usa la de siempre.
  String? _perfilDeLaCarpeta() {
    final carpeta = _folder;
    if (carpeta == null) return null;
    return ref
        .read(workspaceControllerProvider)
        .folders
        .where((item) => item.path == carpeta)
        .firstOrNull
        ?.claudeProfile;
  }

  /// El fallo, dicho de forma que se pueda hacer algo con él.
  ///
  /// Solo se traduce lo que se reconoce; el resto sale literal, que es lo que
  /// ya hacía y sigue siendo lo correcto: el CLI dice cosas accionables y
  /// taparlas con un «no se pudo» obliga a abrir la terminal.
  ///
  /// **La cuenta se nombra**, y no es un adorno: las carpetas usan cuentas
  /// distintas y quien lee esto no tiene por qué acordarse de cuál lleva la
  /// suya. Un «entra otra vez» sin decir dónde deja el mismo trabajo de
  /// averiguación que había antes.
  String _loQuePaso(String message) {
    if (!PorQueMurioClaude.esSesionCaducada(message)) return message;
    final strings = ref.read(stringsProvider);
    return strings.sesionCaducada(
      ClaudeProfile.nameFromPath(_perfilDeLaCarpeta()) ??
          strings.laCuentaDeSiempre,
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

    // El micrófono, antes de montar nada.
    //
    // Nadie lo comprobaba: con el permiso revocado en Ajustes del sistema —algo
    // que pasa meses después de concederlo— el orbe respondía al clic, la sesión
    // intentaba abrirse y lo que salía era el error del motor de audio, que no
    // dice a dónde ir. Y en «sin decidir» hay que **preguntar**, no rendirse:
    // ahí sí toca el diálogo del sistema, que es lo que hace `hasPermission`.
    // 🔴 **Los dos guardias son porque aquí se espera a una persona.** Esto se
    // llama desde el `onTap` del orbe, sin que nadie lo espere, y en «sin
    // decidir» lo que hay en medio es el diálogo del sistema: tarda lo que
    // tarde quien lo lea, y puede cerrar la conversación antes de contestarlo.
    final permiso = await ref.read(microphoneAccessProvider).status();
    if (!_vive) return;
    switch (permiso) {
      case MicrophoneStatus.denied:
        state = state.copyWith(
          errorMessage: ref.read(stringsProvider).microphoneBlocked,
        );
        return;
      case MicrophoneStatus.notAsked:
        final concedido = await ref.read(voiceInputProvider).hasPermission();
        if (!_vive) return;
        if (!concedido) {
          state = state.copyWith(
            errorMessage: ref.read(stringsProvider).microphoneBlocked,
          );
          return;
        }
      case MicrophoneStatus.granted:
        break;
    }

    // Y la carpeta de artefactos, que es el único hueco que le quedaba a i5.
    //
    // Es la única excepción a «ninguna otra carpeta»: viaja como `--add-dir` en
    // todos los encargos, así que si cae dentro de una emparejada en solo texto,
    // esta conversación podría leer de ahí y Gemini narrarlo. La sesión no se
    // abre, que es más estricto que avisar al elegir el cajón — el aviso se
    // ignora y la puerta se queda abierta.
    final cajon = ref
        .read(workspaceControllerProvider)
        .textOnlyOwnerOf(ref.read(artifactsFolderProvider));
    if (cajon != null) {
      state = state.copyWith(
        errorMessage: ref
            .read(stringsProvider)
            .textOnlyArtifactsFolder(cajon.name),
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
        VoiceToolFinished() => _onToolFinished(event),
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
    // **La voz y el encargo se paran los dos**, no uno u otro. Esto salía aquí
    // con un `return` en cuanto había voz, así que con una sesión abierta
    // —o con la marca colgada— el botón paraba el micrófono y dejaba a Claude
    // trabajando. Detener es detener.
    if (state.voiceActive) await stopVoice();
    if (!_vive) return;

    // Y se tira lo que esperaba turno. Detener es «para», no «pausa»: dejar la
    // cola viva haría que al soltar el botón arrancara solo lo siguiente, que
    // es lo contrario de lo que se acaba de pedir.
    _enCola.clear();

    // 🔴 **El estado primero, y la cancelación sin esperarla.**
    //
    // Esto era `await _subscription?.cancel()` con el `copyWith` detrás, y ahí
    // estaba «el detener no hace acción»: cancelar una suscripción **espera a
    // que el generador llegue a un punto donde pueda parar**, y uno detenido en
    // un `await` que no vuelve no llega nunca. Con el `await` delante, la línea
    // que apaga el orbe no se ejecutaba: el botón se pulsaba, no pasaba nada, y
    // no había forma de distinguirlo de un botón muerto.
    //
    // Medido con una prueba: `stopWork` se quedaba colgada los 30 s del tope
    // del test. Ahora el botón responde siempre y la cancelación —con su
    // `finally`, que es quien mata el proceso— sigue su curso por detrás.
    final enVuelo = _subscription;
    _subscription = null;
    state = state.copyWith(orbState: NexusOrbState.sleep, isStreaming: false);
    unawaited(enVuelo?.cancel() ?? Future<void>.value());
  }

  /// Las reglas del repositorio cambiaron desde el encargo anterior.
  ///
  /// No detiene nada ni pinta un error: el encargo ya está en marcha y el
  /// cambio puede ser perfectamente normal —un `git pull`, cambiar de rama—.
  /// Lo que no puede ser es que pase sin que se vea, porque ese texto entra en
  /// el prompt de sistema de **cada** encargo.
  void _onRulesChanged(List<String> paths) {
    state = state.copyWith(
      notice: ref.read(stringsProvider).rulesChanged(paths),
    );
  }

  /// Quita el aviso ya leído. Un error que no se puede cerrar obliga a
  /// convivir con él el resto de la sesión.
  void dismissError() => state = state.copyWith(errorMessage: null);

  /// Lo mismo para el aviso que no es un fallo.
  void dismissNotice() => state = state.copyWith(notice: null);

  Future<void> stopVoice() async {
    await _voiceSubscription?.cancel();
    _voiceSubscription = null;
    if (!_vive) return;
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
    // Se guarda también cuando el turno lo contestó Gemini solo, sin pasar por
    // Claude: eso sigue siendo una conversación con mensajes, y era el caso que
    // desaparecía entero del historial. Guardar es reescribir el mismo registro,
    // así que hacerlo cada turno es barato e idempotente — la misma razón por
    // la que ya se hacía turno a turno escribiendo.
    unawaited(_archive());
  }

  /// Se muestra la instrucción que redactó Gemini, no lo que dijo el usuario:
  /// es lo que se va a ejecutar de verdad, y es la única parte revisable
  /// antes de que pase.
  void _onToolStarted(String instruction) {
    _heard.clear();
    _reply.clear();
    // 🔴 **La misma marca que toma `submit`, y aquí faltaba.**
    //
    // Este es el arranque de un encargo hablado, el gemelo de `submit`, y
    // `_afterErrand` —que corre por los dos caminos— compara contra lo marcado
    // aquí. Sin esta línea, hablando la lista de partida se quedaba vacía para
    // siempre: `_mirarSiHayDocumento` restaba contra el conjunto vacío, así que
    // **todos** los documentos de la carpeta contaban como recién salidos y
    // cada turno se colgaba uno cualquiera. Se vio en pantalla con un resumen
    // viejo pegado a dos respuestas que no tenían nada que ver, y de nuevo con
    // el mismo patrón: se arregló la mitad de después para la voz y la de antes
    // se quedó en el camino de escribir.
    unawaited(_markRepo());
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

  /// El resultado ya viajó de vuelta al modelo, y lo siguiente que llegue será
  /// su narración hablada.
  ///
  /// 🔴 **Sigue en TRABAJANDO, y eso es el cambio.** Soltar el estado aquí era
  /// prometer un turno que todavía no existe: al modelo le queda lo que más
  /// tarda —generar la respuesta hablada, medido entre 5 y 11 s— y en ese rato
  /// la cabecera decía ESCUCHANDO con el orbe en reposo. Quien está delante lee
  /// «te toca», habla encima de una respuesta que venía en camino, y el modelo
  /// se interrumpe a sí mismo.
  ///
  /// Se suelta cuando hay algo de verdad que enseñar: `_onReply` lo pasa a
  /// hablando en cuanto llega la primera palabra, `_onHeard` a escuchando si
  /// hablas tú primero, y si la respuesta no llega nunca la sesión se cierra
  /// sola por inactividad y el orbe se duerme. Ninguno de los tres necesita que
  /// esto adivine el estado por ellos.
  void _onToolFinished(VoiceToolFinished event) {
    _reply.clear();
    state = state.copyWith(
      // Las cifras del turno de Claude, que hablando llegan por aquí. Sin
      // ellas la ventana de contexto se quedaba en «Sin dato» toda la
      // conversación, mientras que escribiendo lo mismo sí se veía.
      //
      // **Y el modelo con ellas**, que era la mitad que faltaba: sin él la
      // ventana se da por 200k, así que hablando con un modelo de un millón el
      // porcentaje salía multiplicado por cinco. Se arregló el numerador y se
      // olvidó el denominador.
      meter: state.meter.copyWith(
        model: event.model,
        turnTokens: event.turnTokens,
        contextTokens: event.contextTokens,
      ),
    );
    _afterErrand();
  }

  Future<void> _onVoiceFailed(String message) async {
    await _voiceSubscription?.cancel();
    _voiceSubscription = null;
    if (!_vive) return;
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

/// Un encargo que espera turno.
///
/// Guarda **lo que hacía falta para lanzarlo**, no el texto suelto: los
/// adjuntos, el tope de escritura y si era el parte cambian lo que se manda, y
/// perderlos al encolar habría convertido «espera un momento» en «se envía otra
/// cosa».
class _Encargo {
  const _Encargo({
    required this.instruction,
    required this.attachments,
    required this.allowWrites,
    required this.esElParte,
    required this.loQueSeVe,
  });

  final String instruction;
  final List<String> attachments;
  final bool allowWrites;
  final bool esElParte;
  final String? loQueSeVe;
}
