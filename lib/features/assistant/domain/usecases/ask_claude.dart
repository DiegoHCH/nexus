import 'package:nexus/features/assistant/domain/entities/claude_event.dart';
import 'package:nexus/features/assistant/domain/repositories/claude_bridge.dart';
import 'package:nexus/features/assistant/domain/repositories/conversation_memory.dart';

/// Dónde trabaja Claude y con cuánta mano suelta. Lo resuelve quien cablea la
/// app, no esta feature: así `assistant` no necesita saber que existen
/// carpetas emparejadas ni cómo se guardan.
typedef ClaudeWorkContext = ({
  String workingDirectory,
  bool canEdit,
  List<String> extraDirectories,
});

/// No extiende `UseCase<ReturnType, Params>`: ese contrato es para trabajo
/// de una sola respuesta (`Future`), y esto es un turno completo emitido
/// como stream — forzarlo al contrato existente escondería justamente lo
/// que la interfaz necesita escuchar en vivo.
class AskClaude {
  const AskClaude(this._bridge, this._readContext, this._memory);

  final ClaudeBridge _bridge;

  /// Lo que Claude recuerda de esta carpeta. Se consulta al empezar cada
  /// encargo y se actualiza al arrancar la sesión, de modo que el siguiente
  /// continúe donde quedó el anterior.
  final ConversationMemory _memory;

  /// Se consulta en cada turno, no se guarda: cambiar de carpeta o mover el
  /// interruptor de permisos tiene que valer para el siguiente encargo sin
  /// reconstruir nada.
  final Future<ClaudeWorkContext?> Function() _readContext;

  Stream<ClaudeEvent> call(String instruction) async* {
    final context = await _readContext();
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
    // La memoria va **por carpeta**, no por conversación: es la regla del
    // producto. Dos chats sobre el mismo repo comparten contexto —reanudan la
    // misma sesión de Claude— y dos sobre repos distintos no se enteran el uno
    // del otro. La carpeta es la frontera.
    final memory = await _memory.read(folder);
    await _memory.rememberPrompt(folder, instruction);

    await for (final event in _bridge.ask(
      instruction,
      workingDirectory: folder,
      canEdit: context.canEdit,
      extraDirectories: context.extraDirectories,
      resumeSessionId: memory.sessionId,
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
  }
}
