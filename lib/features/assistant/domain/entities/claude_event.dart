/// Un evento del bridge headless a Claude Code, ya traducido del
/// `stream-json` crudo del CLI a algo que el dominio entiende.
sealed class ClaudeEvent {
  const ClaudeEvent();
}

/// El encargo espera turno: otra conversación está trabajando sobre la misma
/// carpeta, y esa sesión de Claude no admite dos a la vez.
///
/// Se anuncia en vez de esperar en silencio porque un turno de cola y un cuelgue
/// se ven exactamente igual desde fuera.
final class ClaudeQueued extends ClaudeEvent {
  const ClaudeQueued();
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

/// Claude va a usar una herramienta: leer un archivo, correr un comando.
///
/// Es lo que convierte «pensando…» en algo que se puede mirar. Sin esto, dos
/// minutos de trabajo son indistinguibles de estar colgado.
final class ClaudeToolUsed extends ClaudeEvent {
  const ClaudeToolUsed({
    required this.id,
    required this.description,
    required this.writes,
    this.detail,
    this.parentId,
  });

  /// Identificador de la llamada, para poder marcarla como terminada cuando
  /// llegue su resultado.
  final String id;

  /// Ya en lenguaje humano: «Leyendo lib/main.dart», «Corriendo git status».
  final String description;

  /// La herramienta modifica archivos. La interfaz lo marca aparte porque
  /// escribir es la parte que da miedo con razón, y el permiso y su
  /// consecuencia tienen que verse juntos.
  final bool writes;

  /// Lo que se ejecuta de verdad: el comando entero, la ruta completa. La
  /// línea de arriba está recortada para leerse de un vistazo; esto es para
  /// cuando quieres saber qué pasó exactamente.
  final String? detail;

  /// Si este paso lo dio un subagente, el identificador de la delegación que
  /// lo creó; `null` cuando lo dio Claude directamente.
  ///
  /// Sin esto los pasos del subagente caen al mismo nivel que los del
  /// principal y el rastro deja de contar quién hizo qué: se ve a quien delegó
  /// haciendo el trabajo que acaba de repartir.
  final String? parentId;
}

/// Terminó una herramienta: la actividad pasa de «en curso» a «hecha».
final class ClaudeToolFinished extends ClaudeEvent {
  const ClaudeToolFinished(this.id, {this.output});

  final String id;

  /// Lo que devolvió la herramienta, recortado. Sin esto la columna dice qué
  /// se hizo pero no qué salió, que es justo la mitad interesante.
  final String? output;
}

/// El turno terminó bien.
final class ClaudeTurnCompleted extends ClaudeEvent {
  const ClaudeTurnCompleted({
    required this.result,
    this.costUsd,
    this.durationMs,
    this.turnTokens,
    this.contextTokens,
  });

  final String result;
  final double? costUsd;
  final int? durationMs;

  /// Todo lo que consumió el turno, entrada y salida.
  final int? turnTokens;

  /// Lo que ocupa la conversación en la ventana de contexto. Es distinto de
  /// [turnTokens]: aquí no cuenta lo generado, cuenta lo que hay que arrastrar.
  final int? contextTokens;
}

/// El turno falló: el proceso salió con error, el CLI reportó `is_error`, o
/// no se pudo ni lanzar `claude`.
final class ClaudeFailed extends ClaudeEvent {
  const ClaudeFailed(this.message);

  final String message;
}
