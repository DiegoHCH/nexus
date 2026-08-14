import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/data/datasources/claude_cli_data_source.dart';
import 'package:nexus/features/assistant/data/repositories/claude_bridge_impl.dart';
import 'package:nexus/features/assistant/domain/entities/claude_event.dart';

/// Una sesión guardada que ya no existe donde se busca.
///
/// Pasa de verdad: la memoria guarda la sesión **por carpeta** y las sesiones
/// son de la pareja carpeta + cuenta, así que cambiarle el perfil a una carpeta
/// deja el identificador apuntando al almacén de otra cuenta.
///
/// La primera línea sale del binario, no de nuestra cabeza:
/// `test/fixtures/sesion_muerta.jsonl` se grabó corriendo `claude -p --resume`
/// con una sesión de otro perfil. Importa que sea la de verdad, porque **el
/// fallo llega por stdout antes de que el proceso muera** —un `result` con
/// `is_error`— y es justo esa forma la que desarmaba el reintento.
class _SesionMuerta extends ClaudeCliDataSource {
  _SesionMuerta();

  final resumeRecibidos = <String?>[];

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
  }) async* {
    resumeRecibidos.add(resumeSessionId);

    if (resumeSessionId != null) {
      yield jsonDecode(
            File('test/fixtures/sesion_muerta.jsonl').readAsStringSync().trim(),
          )
          as Map<String, dynamic>;
      throw const ClaudeProcessException(
        1,
        'No conversation found with session ID: '
            'fdb58ce5-1a35-4c1e-a749-e6c1d15be9c5',
      );
    }

    // Sin `--resume` arranca limpio: sesión nueva y respuesta.
    yield {
      'type': 'system',
      'subtype': 'init',
      'session_id': 'sesion-nueva',
      'model': 'claude-opus-5',
    };
    yield {
      'type': 'result',
      'is_error': false,
      'result': 'Gitflow va así.',
      'usage': <String, dynamic>{},
    };
  }
}

void main() {
  test(
    'una sesión que ya no existe se reintenta sin ella, y no se canta el fallo',
    () async {
      final source = _SesionMuerta();
      final events = await ClaudeBridgeImpl(source)
          .ask(
            'cómo funciona gitflow',
            workingDirectory: '/Users/alguien/General',
            canEdit: false,
            resumeSessionId: 'fdb58ce5-1a35-4c1e-a749-e6c1d15be9c5',
          )
          .toList();

      // Se intentó con la sesión muerta y después sin ella.
      expect(source.resumeRecibidos, [
        'fdb58ce5-1a35-4c1e-a749-e6c1d15be9c5',
        null,
      ]);

      expect(
        events.whereType<ClaudeFailed>(),
        isEmpty,
        reason:
            'el usuario no tiene por qué enterarse de una sesión caducada: se '
            'reintenta y se sigue',
      );
      expect(
        events.whereType<ClaudeTurnCompleted>().single.result,
        'Gitflow va así.',
      );

      // Y la sesión nueva sale hacia el dominio, que es lo que sustituye a la
      // muerta en la memoria de la carpeta: así se cura sola.
      expect(
        events.whereType<ClaudeSessionStarted>().single.sessionId,
        'sesion-nueva',
      );
    },
  );

  test('un fallo que no es de sesión sí se cuenta, y no se reintenta', () async {
    final source = _FalloDeVerdad();
    final events = await ClaudeBridgeImpl(source)
        .ask(
          'algo',
          workingDirectory: '/Users/alguien/General',
          canEdit: false,
          resumeSessionId: 'una-sesion',
        )
        .toList();

    expect(source.intentos, 2, reason: 'se reintenta una vez, no más');
    expect(events.whereType<ClaudeFailed>(), isNotEmpty);
  });
}

/// Falla siempre, con o sin sesión: aquí el reintento no puede tapar nada.
class _FalloDeVerdad extends ClaudeCliDataSource {
  _FalloDeVerdad();

  var intentos = 0;

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
  }) async* {
    intentos++;
    throw const ClaudeProcessException(1, 'el disco está lleno');
  }
}
