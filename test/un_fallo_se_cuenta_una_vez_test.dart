import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/data/datasources/claude_cli_data_source.dart';
import 'package:nexus/features/assistant/data/repositories/claude_bridge_impl.dart';
import 'package:nexus/features/assistant/domain/entities/claude_event.dart';
import 'package:nexus/features/assistant/domain/entities/peticion_de_permiso.dart';

/// Un fallo que llega por dos caminos y acababa contado dos veces.
///
/// El CLI cuenta el motivo por stdout —una línea `result` con `is_error`— y
/// **después** sale con 1. Ese segundo camino no trae motivo: si ya lo dijo por
/// stdout, su stderr viene vacío. Se emitían dos `ClaudeFailed`, y quien los
/// pinta sobreescribe `errorMessage`, así que en pantalla quedaba «claude
/// terminó con código 1:» y nada detrás. El motivo real estuvo ahí un instante
/// y lo tapó su propia secuela.
///
/// Se prueba **sin sesión guardada** a propósito: con `--resume` el fallo se
/// retiene para poder reintentar, y ese camino ya lo cubre
/// `sesion_muerta_test.dart`. Aquí interesa el caso normal.
class _MotivoYLuegoCodigo extends ClaudeCliDataSource {
  _MotivoYLuegoCodigo(this.stderr);

  /// Lo que el proceso deja en stderr al morir. Vacío es el caso de verdad.
  final String stderr;

  @override
  Stream<Map<String, dynamic>> run(
    String instruction, {
    required String workingDirectory,
    required String permissionMode,
    List<String> extraDirectories = const [],
    String? resumeSessionId,
    String? appendSystemPrompt,
    String? configDir,
    String? model,
    String? effort,
    List<String> disallowedTools = const [],
    List<String> herramientasMcp = const [],
    // Nadie contesta permisos aquí: esta prueba va de cómo muere el proceso.
    Future<RespuestaDePermiso> Function(PeticionDePermiso peticion)?
    alPedirPermiso,
  }) async* {
    yield {
      'type': 'system',
      'subtype': 'init',
      'session_id': 'una-sesion',
      'model': 'claude-opus-5',
    };
    // El motivo, con las palabras del CLI.
    yield {
      'type': 'result',
      'is_error': true,
      'result': 'Claude usage limit reached. Your limit will reset at 3pm.',
    };
    // Y acto seguido, la muerte del proceso sin nada que añadir.
    throw ClaudeProcessException(1, stderr);
  }
}

void main() {
  test('el motivo del fallo sobrevive al código de salida', () async {
    final events = await ClaudeBridgeImpl(_MotivoYLuegoCodigo(''))
        .ask(
          'que puede hacer nexus que no puedo en una terminal de claude',
          workingDirectory: '/Users/alguien/General',
          canEdit: false,
        )
        .toList();

    final fallos = events.whereType<ClaudeFailed>().toList();
    expect(
      fallos,
      hasLength(1),
      reason:
          'un solo fallo se cuenta una vez: el segundo sobreescribía al '
          'primero y dejaba el recuadro vacío',
    );
    expect(
      fallos.single.message,
      contains('usage limit reached'),
      reason: 'lo que queda en pantalla tiene que ser accionable',
    );
  });

  test('un stderr con texto sí se cuenta, porque trae algo nuevo', () async {
    final events =
        await ClaudeBridgeImpl(
              _MotivoYLuegoCodigo('el hook PostToolUse se cayó'),
            )
            .ask(
              'algo',
              workingDirectory: '/Users/alguien/General',
              canEdit: false,
            )
            .toList();

    final fallos = events.whereType<ClaudeFailed>().toList();
    expect(
      fallos,
      hasLength(2),
      reason:
          'son dos fallos distintos en el mismo turno, no el mismo dos veces: '
          'tirar el segundo perdería lo que solo dice stderr',
    );
    expect(fallos.last.message, contains('el hook PostToolUse se cayó'));
  });
}
