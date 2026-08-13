import 'package:nexus/features/assistant/domain/entities/claude_event.dart';
import 'package:nexus/features/assistant/domain/repositories/claude_bridge.dart';
import 'package:nexus/features/assistant/domain/repositories/conversation_memory.dart';
import 'package:nexus/features/assistant/domain/repositories/stays_awake.dart';
import 'package:nexus/features/assistant/domain/usecases/folder_errand_queue.dart';

/// Dónde trabaja Claude y con cuánta mano suelta. Lo resuelve quien cablea la
/// app, no esta feature: así `assistant` no necesita saber que existen
/// carpetas emparejadas ni cómo se guardan.
typedef ClaudeWorkContext = ({
  String workingDirectory,
  bool canEdit,
  List<String> extraDirectories,
  String language,
  String? claudeProfile,
  String? model,
  String? effort,
  List<String> disallowedTools,
  String? constraintsNotice,
  String? artifactsFolder,
});

/// No extiende `UseCase<ReturnType, Params>`: ese contrato es para trabajo
/// de una sola respuesta (`Future`), y esto es un turno completo emitido
/// como stream — forzarlo al contrato existente escondería justamente lo
/// que la interfaz necesita escuchar en vivo.
class AskClaude {
  const AskClaude(
    this._bridge,
    this._readContext,
    this._memory,
    this._queue,
    this._awake,
  );

  final ClaudeBridge _bridge;

  /// Lo que Claude recuerda de esta carpeta. Se consulta al empezar cada
  /// encargo y se actualiza al arrancar la sesión, de modo que el siguiente
  /// continúe donde quedó el anterior.
  final ConversationMemory _memory;

  /// Se consulta en cada turno, no se guarda: cambiar de carpeta o mover el
  /// interruptor de permisos tiene que valer para el siguiente encargo sin
  /// reconstruir nada.
  ///
  /// Recibe **el encargo** porque hay una decisión que depende de lo que se
  /// pide: con una raíz de varios repos, nombrar uno debería colocar a Claude
  /// dentro de él.
  final Future<ClaudeWorkContext?> Function(String instruction) _readContext;

  /// Un encargo a la vez por carpeta. Compartido entre conversaciones: es lo
  /// único que impide que dos hilos sobre el mismo repo se pisen la sesión.
  final FolderErrandQueue _queue;

  /// Mientras dure el encargo, el Mac no se suspende solo. Un encargo largo es
  /// exactamente el rato en que nadie toca el teclado, así que el contador de
  /// inactividad del sistema corre entero y se lo lleva por delante.
  final StaysAwake _awake;

  /// [remember] a `false` para lo que no es una petición del usuario —hoy,
  /// comprimir la conversación—: eso no debe aparecer en «lo que le has
  /// pedido», donde la lista sirve para repetir una petición anterior.
  Stream<ClaudeEvent> call(String instruction, {bool remember = true}) async* {
    final context = await _readContext(instruction);
    // Sin carpeta emparejada no hay dónde trabajar, y lo honesto es decirlo:
    // antes se lanzaba igual y Claude respondía sobre la raíz del disco.
    if (context == null) {
      yield const ClaudeFailed(
        'No hay ninguna carpeta emparejada, así que no hay dónde trabajar. '
        'Empareja una carpeta y vuelve a pedírmelo.',
      );
      return;
    }

    final folder = context.workingDirectory;

    // Antes de la cola y no después: esperar turno también es tiempo de
    // encargo, y son los minutos en los que el usuario se ha ido a por un café
    // confiando en que a la vuelta esté hecho.
    final awake = await _awake.hold('Nexus: $folder');

    try {
      // Turno para esta carpeta. Si la otra conversación sigue trabajando sobre
      // ella, se avisa antes de esperar: quedarse callado mientras llega el turno
      // se ve exactamente igual que estar colgado.
      if (_queue.isBusy(folder)) {
        yield const ClaudeQueued();
      }
      final release = await _queue.acquire(folder);
      try {
        // La memoria va **por carpeta**, no por conversación: es la regla del
        // producto. Dos chats sobre el mismo repo comparten contexto —reanudan
        // la misma sesión de Claude— y dos sobre repos distintos no se enteran el
        // uno del otro. La carpeta es la frontera.
        final memory = await _memory.read(folder);
        if (remember) await _memory.rememberPrompt(folder, instruction);

        await for (final event in _bridge.ask(
          // La preferencia de idioma va como preferencia, no como orden: si
          // escribes en otro idioma, gana lo que escribiste. Imponerlo haría que
          // preguntar algo en español con la app en inglés te contestara en
          // inglés, que es exactamente lo contrario de lo que se pidió.
          '$instruction\n\n(Si no se te pide otra cosa, responde en '
          '${context.language}.)',
          workingDirectory: folder,
          canEdit: context.canEdit,
          extraDirectories: context.extraDirectories,
          resumeSessionId: memory.sessionId,
          claudeProfile: context.claudeProfile,
          model: context.model,
          effort: context.effort,
          disallowedTools: context.disallowedTools,
          artifactsFolder: context.artifactsFolder,
        )) {
          // El identificador se guarda en cuanto arranca, no al terminar: si el
          // encargo se cancela a media ejecución —cerrar la conversación mata el
          // proceso— lo hablado hasta ahí sigue formando parte de la sesión, y
          // olvidarlo dejaría a Claude repitiendo trabajo ya hecho.
          if (event case ClaudeSessionStarted(
            :final sessionId,
          ) when sessionId.isNotEmpty) {
            await _memory.rememberSession(folder, sessionId);
          }
          yield event;
        }
      } finally {
        // También al cancelar: cerrar la conversación a media ejecución pasa por
        // aquí, y no soltar el turno dejaría la carpeta bloqueada para siempre.
        release();
      }
    } finally {
      // Lo mismo pero peor si se olvida: una petición al sistema que no se
      // suelta deja el Mac sin poder dormirse **el resto de la sesión**, y
      // desde fuera eso no se parece a un fallo de esta app.
      awake();
    }
  }
}
