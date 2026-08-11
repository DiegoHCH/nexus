import 'package:nexus/features/assistant/data/datasources/claude_cli_data_source.dart';
import 'package:nexus/features/assistant/domain/entities/claude_event.dart';
import 'package:nexus/features/assistant/domain/repositories/claude_bridge.dart';

class ClaudeBridgeImpl implements ClaudeBridge {
  const ClaudeBridgeImpl(this._dataSource);

  final ClaudeCliDataSource _dataSource;

  @override
  Stream<ClaudeEvent> ask(String instruction) async* {
    try {
      await for (final json in _dataSource.run(instruction)) {
        final event = _decode(json);
        if (event != null) yield event;
      }
    } catch (e) {
      yield ClaudeFailed(e.toString());
    }
  }

  /// Traduce una línea de `stream-json` a un [ClaudeEvent], o `null` si es
  /// un evento que el HUD de la Fase 1 no necesita todavía (rate limits,
  /// contador de tokens de "thinking", los mensajes "assistant" completos
  /// —ya cubiertos por los `text_delta`— o el estado "requesting").
  ClaudeEvent? _decode(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'system':
        if (json['subtype'] != 'init') return null;
        return ClaudeSessionStarted(
          sessionId: json['session_id'] as String? ?? '',
          model: json['model'] as String? ?? '',
        );

      case 'stream_event':
        final event = json['event'] as Map<String, dynamic>?;
        if (event?['type'] != 'content_block_delta') return null;
        final delta = event?['delta'] as Map<String, dynamic>?;
        if (delta?['type'] != 'text_delta') return null;
        return ClaudeTextDelta(delta?['text'] as String? ?? '');

      case 'result':
        if (json['is_error'] == true) {
          return ClaudeFailed(json['result'] as String? ?? 'Error desconocido');
        }
        return ClaudeTurnCompleted(
          result: json['result'] as String? ?? '',
          costUsd: (json['total_cost_usd'] as num?)?.toDouble(),
          durationMs: json['duration_ms'] as int?,
        );

      default:
        return null;
    }
  }
}
