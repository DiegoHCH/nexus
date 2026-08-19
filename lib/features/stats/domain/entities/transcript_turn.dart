/// Un turno de una conversación de Claude, reducido a lo que se cuenta.
///
/// Los transcritos ocupan cientos de megas —186 MB solo la cuenta de trabajo—
/// porque llevan dentro el contenido entero de cada mensaje y cada archivo
/// leído. Nada de eso hace falta para unas estadísticas, así que del disco solo
/// sale esto: cuándo, de qué sesión, con qué modelo y cuántos tokens.
class TranscriptTurn {
  const TranscriptTurn({
    required this.at,
    required this.sessionId,
    required this.fromAssistant,
    this.model,
    this.input = 0,
    this.output = 0,
    this.cached = 0,
  });

  final DateTime at;
  final String sessionId;
  final bool fromAssistant;

  /// Solo en los turnos del asistente: los del usuario no eligen modelo.
  final String? model;

  final int input;
  final int output;

  /// Lo que se leyó o escribió en la caché de contexto. Se guarda aparte y **no
  /// se suma al total** porque distorsiona todo lo demás: en la cuenta de
  /// trabajo son 4 967 M frente a 15 M de salida real, así que sumarlo
  /// convertiría cualquier gráfico en una sola barra.
  final int cached;

  int get tokens => input + output;
}
