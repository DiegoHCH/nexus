import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/assistant/data/datasources/claude_cli_data_source.dart';
import 'package:nexus/features/assistant/data/repositories/claude_bridge_impl.dart';
import 'package:nexus/features/assistant/domain/entities/claude_event.dart';

/// El CLI, sustituido por las líneas que se le quieran dar.
class _Cli extends ClaudeCliDataSource {
  const _Cli(this._lines, {this.failFirst = false});

  final List<Map<String, dynamic>> _lines;

  /// Falla mientras se le pida reanudar una sesión, como cuando la guardada ya
  /// caducó.
  final bool failFirst;

  @override
  Stream<Map<String, dynamic>> run(
    String instruction, {
    required String workingDirectory,
    required String permissionMode,
    List<String> extraDirectories = const [],
    String? resumeSessionId,
  }) async* {
    if (failFirst && resumeSessionId != null) {
      throw const ClaudeProcessException(1, 'no such session');
    }
    for (final line in _lines) {
      yield line;
    }
  }
}

Map<String, dynamic> assistantTool(String id, String name, Object input) => {
  'type': 'assistant',
  'message': {
    'content': [
      {'type': 'tool_use', 'id': id, 'name': name, 'input': input},
    ],
  },
};

Future<List<ClaudeEvent>> decode(
  List<Map<String, dynamic>> lines, {
  bool failFirst = false,
  String? resume,
}) => ClaudeBridgeImpl(_Cli(lines, failFirst: failFirst))
    .ask(
      'da igual',
      workingDirectory: '/repo',
      canEdit: false,
      resumeSessionId: resume,
    )
    .toList();

void main() {
  test('el arranque trae sesión y modelo', () async {
    final events = await decode([
      {
        'type': 'system',
        'subtype': 'init',
        'session_id': 'abc',
        'model': 'claude-opus-5[1m]',
      },
      // Los demás `system` son ruido para la interfaz: estados intermedios,
      // avisos de cuota. Si se dejaran pasar, cada uno sería un evento sin
      // nada que enseñar.
      {'type': 'system', 'subtype': 'status'},
      {'type': 'rate_limit_event'},
    ]);

    expect(events, hasLength(1));
    final started = events.single as ClaudeSessionStarted;
    expect(started.sessionId, 'abc');
    expect(started.model, 'claude-opus-5[1m]');
  });

  test('la respuesta llega por deltas, no por el mensaje entero', () async {
    final events = await decode([
      {
        'type': 'stream_event',
        'event': {
          'type': 'content_block_delta',
          'delta': {'type': 'text_delta', 'text': 'Hola'},
        },
      },
      // Un delta de otro tipo —el contador de «thinking»— no es texto que
      // enseñar.
      {
        'type': 'stream_event',
        'event': {
          'type': 'content_block_delta',
          'delta': {'type': 'thinking_delta', 'thinking': 'mmm'},
        },
      },
      {
        'type': 'assistant',
        'message': {
          'content': [
            {'type': 'text', 'text': 'Hola'},
          ],
        },
      },
    ]);

    expect(events.whereType<ClaudeTextDelta>().map((e) => e.text), ['Hola']);
  });

  // Un mismo mensaje puede pedir tres herramientas a la vez: si el decodificador
  // devolviera una sola, dos pasos desaparecerían de la columna.
  test('varias herramientas en un mensaje salen todas', () async {
    final events = await decode([
      {
        'type': 'assistant',
        'message': {
          'content': [
            {
              'type': 'tool_use',
              'id': 't1',
              'name': 'Read',
              'input': {'file_path': '/repo/a.dart'},
            },
            {
              'type': 'tool_use',
              'id': 't2',
              'name': 'Read',
              'input': {'file_path': '/repo/b.dart'},
            },
          ],
        },
      },
    ]);

    expect(events.whereType<ClaudeToolUsed>().map((e) => e.id), ['t1', 't2']);
  });

  test('el resultado de una herramienta la cierra, con su salida', () async {
    final events = await decode([
      assistantTool('t1', 'Bash', {'command': 'git status'}),
      {
        'type': 'user',
        'message': {
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': 't1',
              'content': 'nothing to commit',
            },
          ],
        },
      },
    ]);

    final finished = events.whereType<ClaudeToolFinished>().single;
    expect(finished.id, 't1');
    expect(finished.output, 'nothing to commit');
  });

  test('una salida enorme se recorta antes de llegar a la pantalla', () async {
    final events = await decode([
      {
        'type': 'user',
        'message': {
          'content': [
            {'type': 'tool_result', 'tool_use_id': 't1', 'content': 'x' * 5000},
          ],
        },
      },
    ]);

    final output = events.whereType<ClaudeToolFinished>().single.output!;
    expect(output.length, lessThan(1300));
    expect(output, endsWith('…'));
  });

  group('el medidor', () {
    test('la caché cuenta como contexto ocupado', () async {
      final events = await decode([
        {
          'type': 'result',
          'result': 'listo',
          'usage': {
            'input_tokens': 100,
            'cache_creation_input_tokens': 200,
            'cache_read_input_tokens': 300,
            'output_tokens': 50,
          },
        },
      ]);

      final done = events.whereType<ClaudeTurnCompleted>().single;
      // Son tokens que ya están en la ventana aunque no se reenvíen: sin
      // contarlos, una conversación larga parecería vacía.
      expect(done.contextTokens, 600);
      expect(done.turnTokens, 650);
      expect(done.result, 'listo');
    });

    test('un turno fallido se cuenta como fallo, no como respuesta', () async {
      final events = await decode([
        {'type': 'result', 'is_error': true, 'result': 'se rompió'},
      ]);

      expect(events.single, isA<ClaudeFailed>());
      expect((events.single as ClaudeFailed).message, 'se rompió');
    });
  });

  // Una sesión guardada puede haber caducado. Perder la memoria es molesto;
  // quedarse sin respuesta por eso, inaceptable.
  test('si la sesión guardada ya no vale, se reintenta sin ella', () async {
    final events = await decode(
      [
        {
          'type': 'system',
          'subtype': 'init',
          'session_id': 'nueva',
          'model': 'x',
        },
      ],
      failFirst: true,
      resume: 'sesion-vieja',
    );

    expect(events.whereType<ClaudeSessionStarted>().single.sessionId, 'nueva');
    expect(events.whereType<ClaudeFailed>(), isEmpty);
  });
}
