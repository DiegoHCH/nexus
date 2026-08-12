import 'package:nexus/features/assistant/domain/entities/claude_event.dart';
import 'package:nexus/features/assistant/domain/repositories/claude_bridge.dart';

/// Dónde trabaja Claude y con cuánta mano suelta. Lo resuelve quien cablea la
/// app, no esta feature: así `assistant` no necesita saber que existen
/// carpetas emparejadas ni cómo se guardan.
typedef ClaudeWorkContext = ({String workingDirectory, bool canEdit, List<String> extraDirectories});

/// No extiende `UseCase<ReturnType, Params>`: ese contrato es para trabajo
/// de una sola respuesta (`Future`), y esto es un turno completo emitido
/// como stream — forzarlo al contrato existente escondería justamente lo
/// que la interfaz necesita escuchar en vivo.
class AskClaude {
  const AskClaude(this._bridge, this._readContext);

  final ClaudeBridge _bridge;

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

    yield* _bridge.ask(
      instruction,
      workingDirectory: context.workingDirectory,
      canEdit: context.canEdit,
      extraDirectories: context.extraDirectories,
    );
  }
}
