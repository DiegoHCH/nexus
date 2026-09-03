import 'package:nexus/features/assistant/domain/entities/claude_event.dart';
import 'package:nexus/features/assistant/domain/entities/peticion_de_permiso.dart';
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
  List<String> comandosPermitidos,
  String? constraintsNotice,
  String? artifactsFolder,
  String? carpetaDePruebas,

  /// Cómo se llama quien contesta y cómo llamar a quien pregunta, ya compuesto
  /// para el prompt. Viaja en el contexto y no como parámetro suelto porque es
  /// lo mismo que el idioma: una preferencia de la app, no del encargo.
  String? nombres,
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
  /// [allowWrites] es un **tope, no un permiso**: puede bajar lo que la carpeta
  /// concede, nunca subirlo. Lo usa el canal del teléfono, que manda encargos con
  /// `false` mientras no tenga la frase de escritura.
  ///
  /// Viaja con el encargo y no en un ajuste global porque si no, capar al teléfono
  /// caparía también los encargos que se lanzan desde el escritorio — y entonces
  /// tener el móvil conectado te quitaría permisos a ti.
  /// [alPedirPermiso] es **quién está mirando**. Con alguien delante, lo que
  /// Claude no tenga concedido se pregunta en vez de concederse o negarse solo.
  /// Sin nadie —la agenda, el canal del teléfono, la cola de la carpeta— va
  /// `null` y el encargo se comporta como siempre.
  Stream<ClaudeEvent> call(
    String instruction, {
    bool remember = true,
    bool allowWrites = true,
    Future<RespuestaDePermiso> Function(PeticionDePermiso peticion)?
    alPedirPermiso,
  }) async* {
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
        // La sesión se pide **para esta cuenta**: la misma carpeta abierta
        // con otro perfil no tiene la del anterior, y reanudarla fallaba.
        final memory = await _memory.read(
          folder,
          claudeProfile: context.claudeProfile,
        );
        if (remember) await _memory.rememberPrompt(folder, instruction);

        await for (final event in _bridge.ask(
          // **El encargo va tal cual, sin una coma de Nexus encima.** Aquí se le pegaba
          // la preferencia de idioma y eso rompía cualquier herramienta que lea el
          // prompt como un comando — el plugin del marco abrió una tarea titulada con
          // esa frase. Ahora viaja en el prompt de sistema, que es donde vive una
          // preferencia.
          instruction,
          workingDirectory: folder,
          // El AND, y **el único sitio donde se decide**: lo que concede la
          // carpeta y lo que el origen del encargo permite. Gana el más estricto.
          canEdit: context.canEdit && allowWrites,
          extraDirectories: context.extraDirectories,
          resumeSessionId: memory.sessionId,
          claudeProfile: context.claudeProfile,
          model: context.model,
          effort: context.effort,
          disallowedTools: context.disallowedTools,
          // **El AND otra vez**: lo que la carpeta autoriza solo vale si este
          // encargo puede escribir. Un parte del día, que se pide sin escritura,
          // no ejecuta nada aunque la carpeta tenga permitido el mundo entero.
          comandosPermitidos: context.canEdit && allowWrites
              ? context.comandosPermitidos
              : const [],
          constraintsNotice: context.constraintsNotice,
          nombres: context.nombres,
          language: context.language,
          artifactsFolder: context.artifactsFolder,
          carpetaDePruebas: context.carpetaDePruebas,
          // **Solo si el encargo ya podía escribir.** Preguntar es dar la
          // oportunidad de conceder, así que ofrecérselo a un encargo que llegó
          // con la escritura capada —el teléfono sin la frase— le devolvería
          // por el diálogo justo lo que el tope le quitó.
          alPedirPermiso: context.canEdit && allowWrites
              ? alPedirPermiso
              : null,
        )) {
          // El identificador se guarda en cuanto arranca, no al terminar: si el
          // encargo se cancela a media ejecución —cerrar la conversación mata el
          // proceso— lo hablado hasta ahí sigue formando parte de la sesión, y
          // olvidarlo dejaría a Claude repitiendo trabajo ya hecho.
          if (event case ClaudeSessionStarted(
            :final sessionId,
          ) when sessionId.isNotEmpty) {
            await _memory.rememberSession(
              folder,
              sessionId,
              claudeProfile: context.claudeProfile,
            );
          }
          yield event;

          // 🔴 **El turno se suelta cuando acaba el turno, no cuando muere el
          // proceso.** Eran lo mismo hasta que se midió que no: un `claude -p`
          // no sale hasta que mueren sus servidores MCP, y con un MCP en JVM o
          // en `uvx` eso son minutos después de haber contestado.
          //
          // Medido en la máquina: encargo arrancado a las 23:15:00, turno
          // archivado a las 23:15:09, y el proceso todavía vivo a las 23:18:25
          // con cinco hijos —dos `context7`, `engram`, la JVM de Maestro y el
          // proxy de AWS—. Soltando en el `finally`, la carpeta se quedaba
          // tomada esos tres minutos por un encargo que ya había terminado, y
          // lo siguiente que escribías contestaba «esperando a la otra
          // conversación sobre esta carpeta»: sin otra conversación, y sin
          // nadie trabajando. Se ve igual que un cuelgue porque lo es.
          //
          // Soltar aquí es correcto y no un atajo: la cola existe para que dos
          // `--resume` simultáneos no se pierdan un turno de la sesión, y con
          // el `result` ya emitido este proceso no va a escribir más en ella.
          // Lo que queda por hacer es apagar hijos, que no toca la sesión.
          if (event is ClaudeTurnCompleted || event is ClaudeFailed) release();
        }
      } finally {
        // Y aquí también, que es el otro final: un encargo cancelado —cerrar la
        // conversación a media ejecución— no llega a emitir final ninguno, y no
        // soltar el turno dejaría la carpeta bloqueada para siempre.
        //
        // Llamarlo dos veces es gratis y está previsto: `release` se guarda con
        // su propio `released` justo para poder ponerlo en los dos sitios sin
        // pensar en cuál llegó primero.
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
