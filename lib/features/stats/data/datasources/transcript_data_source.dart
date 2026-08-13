import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:nexus/features/stats/domain/entities/transcript_turn.dart';

/// Los transcritos que Claude Code deja en el disco, leídos para contar.
///
/// Cada cuenta guarda los suyos en `<configDir>/projects/<proyecto>/<sesión>.jsonl`,
/// una línea por evento. Es la única fuente que hay: el endpoint de cuota dice
/// cuánto te queda de la suscripción, no qué has hecho.
class TranscriptDataSource {
  const TranscriptDataSource();

  /// Lee todo lo de una cuenta. [configDir] es `~/.claude-work` o similar.
  ///
  /// Va **en otro isolate** porque no es poca cosa: 250 archivos y 186 MB en la
  /// cuenta de trabajo. Hacerlo en el hilo de la interfaz congelaría la ventana
  /// —el orbe incluido— durante segundos, y justo al abrir una pantalla.
  Future<List<TranscriptTurn>> read(String configDir) =>
      Isolate.run(() => _readSync(configDir));
}

List<TranscriptTurn> _readSync(String configDir) {
  final root = Directory('$configDir/projects');
  if (!root.existsSync()) return const [];

  final turns = <TranscriptTurn>[];
  for (final entry in root.listSync(recursive: true, followLinks: false)) {
    if (entry is! File || !entry.path.endsWith('.jsonl')) continue;
    try {
      for (final line in const LineSplitter().convert(
        entry.readAsStringSync(),
      )) {
        final turn = _turnOf(line);
        if (turn != null) turns.add(turn);
      }
    } on FileSystemException {
      // Un transcrito ilegible no puede tumbar las estadísticas de los otros
      // 249: se salta y ya está.
      continue;
    }
  }
  turns.sort((a, b) => a.at.compareTo(b.at));
  return turns;
}

/// Se mira la línea **antes** de parsearla.
///
/// La mayoría no son turnos —adjuntos, instantáneas de archivos, cambios de
/// modo— y algunas pesan 160 KB. Descartarlas con una búsqueda de texto evita
/// construir el árbol JSON de todo lo que no se va a contar, que es de lejos lo
/// más caro del proceso.
TranscriptTurn? _turnOf(String line) {
  final isAssistant = line.contains('"type":"assistant"');
  if (!isAssistant && !line.contains('"type":"user"')) return null;

  try {
    final event = jsonDecode(line);
    if (event is! Map) return null;
    final at = DateTime.tryParse(event['timestamp'] as String? ?? '');
    final session = event['sessionId'] as String?;
    if (at == null || session == null) return null;

    final message = event['message'];
    final usage = message is Map ? message['usage'] : null;
    final model = message is Map ? message['model'] as String? : null;

    return TranscriptTurn(
      // En local: los transcritos guardan UTC, y una estadística de «hora
      // punta» en UTC diría que trabajas a las cuatro de la mañana.
      at: at.toLocal(),
      sessionId: session,
      fromAssistant: isAssistant,
      // `<synthetic>` es lo que Claude anota cuando la respuesta no salió de un
      // modelo —un aviso del propio CLI—, y contarlo como uno más metería en la
      // lista un modelo que no existe.
      model: model == '<synthetic>' ? null : model,
      input: _int(usage, 'input_tokens'),
      output: _int(usage, 'output_tokens'),
      cached:
          _int(usage, 'cache_read_input_tokens') +
          _int(usage, 'cache_creation_input_tokens'),
    );
  } on FormatException {
    return null;
  }
}

int _int(Object? usage, String key) =>
    usage is Map ? (usage[key] as num?)?.toInt() ?? 0 : 0;
