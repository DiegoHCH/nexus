/// Un evento del bridge headless a Claude Code, ya traducido del
/// `stream-json` crudo del CLI a algo que el dominio entiende.
sealed class ClaudeEvent {
  const ClaudeEvent();
}

/// Arrancó la sesión: llega una sola vez, al principio.
final class ClaudeSessionStarted extends ClaudeEvent {
  const ClaudeSessionStarted({required this.sessionId, required this.model});

  final String sessionId;
  final String model;
}

/// Un fragmento de texto de la respuesta, en el orden en que Claude lo va
/// generando (requiere `--include-partial-messages`).
final class ClaudeTextDelta extends ClaudeEvent {
  const ClaudeTextDelta(this.text);

  final String text;
}

/// El turno terminó bien.
final class ClaudeTurnCompleted extends ClaudeEvent {
  const ClaudeTurnCompleted({required this.result, this.costUsd, this.durationMs});

  final String result;
  final double? costUsd;
  final int? durationMs;
}

/// El turno falló: el proceso salió con error, el CLI reportó `is_error`, o
/// no se pudo ni lanzar `claude`.
final class ClaudeFailed extends ClaudeEvent {
  const ClaudeFailed(this.message);

  final String message;
}
