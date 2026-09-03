import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/data/datasources/claude_cli_data_source.dart';
import 'package:nexus/features/assistant/data/repositories/claude_bridge_impl.dart';
import 'package:nexus/features/assistant/domain/entities/claude_event.dart';
import 'package:nexus/features/assistant/domain/entities/peticion_de_permiso.dart';

/// Cuánto contexto lleva ocupado la sesión, que **no** es lo que suma el turno.
///
/// Un turno con herramientas hace varias peticiones a la API y cada una reenvía
/// el contexto entero. El `usage` del `result` viene acumulado, así que usarlo
/// como contexto cuenta lo mismo varias veces — y con turnos largos pasa del
/// 100 % de la ventana. Se vio un **132 %** en una conversación real, que es lo
/// que destapó esto.
///
/// Las cifras de aquí salen de un turno medido contra el binario: cuatro
/// peticiones, la última pidiendo 32.898 tokens, y el `result` reportando
/// 61.594. El contexto es el primero.
class _TurnoConHerramientas extends ClaudeCliDataSource {
  const _TurnoConHerramientas();

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
    Future<RespuestaDePermiso> Function(PeticionDePermiso)? alPedirPermiso,
  }) async* {
    yield {
      'type': 'system',
      'subtype': 'init',
      'session_id': 's1',
      'model': 'claude-opus-5',
    };
    // Tres peticiones con el mismo contexto y una cuarta ya crecida: es la
    // forma que tiene un turno que usa herramientas.
    for (final prompt in [28696, 28696, 28696, 32898]) {
      yield {
        'type': 'assistant',
        'message': {
          'content': <dynamic>[],
          'usage': {
            'input_tokens': 4,
            'cache_creation_input_tokens': 1000,
            'cache_read_input_tokens': prompt - 1004,
          },
        },
      };
    }
    yield {
      'type': 'result',
      'is_error': false,
      'result': 'listo',
      // Acumulado del turno, que es lo que la app usaba antes.
      'usage': {
        'input_tokens': 16,
        'cache_creation_input_tokens': 4000,
        'cache_read_input_tokens': 57578,
      },
    };
  }
}

void main() {
  test('el contexto es el de la última petición, no el del turno', () async {
    final events = await const ClaudeBridgeImpl(_TurnoConHerramientas())
        .ask('algo con herramientas', workingDirectory: '/repo', canEdit: false)
        .toList();

    final fin = events.whereType<ClaudeTurnCompleted>().single;
    expect(
      fin.contextTokens,
      32898,
      reason:
          'con el acumulado del result daban 61.594, casi el doble, y con '
          'turnos largos eso pasaba del 100 % de la ventana',
    );
  });

  test('y el gasto del turno sí es el acumulado, que es otra cosa', () async {
    final events = await const ClaudeBridgeImpl(
      _TurnoConHerramientas(),
    ).ask('algo', workingDirectory: '/repo', canEdit: false).toList();

    // `turnTokens` mide lo que costó el turno; `contextTokens`, cuánta ventana
    // queda ocupada. Son dos preguntas distintas y por eso no comparten cifra.
    final fin = events.whereType<ClaudeTurnCompleted>().single;
    expect(fin.turnTokens, greaterThan(fin.contextTokens!));
  });

  test('sin peticiones intermedias se queda con lo que haya', () async {
    // Un turno sin herramientas: el `result` es la única fuente y sigue siendo
    // correcta, porque ahí hubo una sola petición.
    final events = await const ClaudeBridgeImpl(
      _TurnoDirecto(),
    ).ask('hola', workingDirectory: '/repo', canEdit: false).toList();

    expect(events.whereType<ClaudeTurnCompleted>().single.contextTokens, 5000);
  });
}

class _TurnoDirecto extends ClaudeCliDataSource {
  const _TurnoDirecto();

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
    Future<RespuestaDePermiso> Function(PeticionDePermiso)? alPedirPermiso,
  }) async* {
    yield {
      'type': 'result',
      'is_error': false,
      'result': 'hola',
      'usage': {'input_tokens': 5000},
    };
  }
}
