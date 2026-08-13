import 'package:flutter/foundation.dart';
import 'package:nexus/features/assistant/presentation/state/assistant_hud_state.dart';

/// Una fila de la columna «Ahora mismo», ya colocada: el paso y a qué altura
/// va.
@immutable
class ActivityRow {
  const ActivityRow({
    required this.item,
    required this.depth,
    required this.running,
  });

  final ActivityItem item;

  /// 0 para lo que hizo Claude; 1 para lo que hizo un subagente por encargo
  /// suyo. No hay más niveles: un subagente no delega.
  final int depth;

  /// El paso que está ocurriendo ahora mismo — uno solo, el más profundo.
  /// Mientras un subagente trabaja, quien está haciendo algo es él, no la
  /// delegación que lo espera.
  final bool running;
}

/// Coloca los pasos del turno para poder pintarlos: cada delegación seguida de
/// lo que hizo su subagente.
///
/// Vive fuera del widget porque son reglas, no pintura, y estas ya se
/// equivocaron una vez: **agrupar por orden de llegada no vale**. Claude puede
/// abrir dos delegaciones en el mismo mensaje, y entonces los pasos de una y
/// otra llegan intercalados; colocarlos según llegan mezclaría los dos
/// trabajos bajo la primera línea.
List<ActivityRow> layoutActivity(List<ActivityItem> items) {
  final children = <String, List<ActivityItem>>{};
  for (final item in items) {
    final parent = item.parentId;
    if (parent != null) children.putIfAbsent(parent, () => []).add(item);
  }

  // El que corre es el último sin terminar, mirando el orden de llegada: una
  // delegación sigue «sin terminar» mientras su subagente trabaja, y marcarla
  // a ella dejaría el punto encendido en la línea equivocada.
  String? runningId;
  for (final item in items) {
    if (!item.done) runningId = item.id;
  }

  final rows = <ActivityRow>[];
  for (final item in items) {
    // Los hijos se emiten con su padre, no cuando les toca por llegada.
    if (item.parentId != null) continue;
    rows.add(ActivityRow(item: item, depth: 0, running: item.id == runningId));
    for (final child in children[item.id] ?? const <ActivityItem>[]) {
      rows.add(
        ActivityRow(item: child, depth: 1, running: child.id == runningId),
      );
    }
  }

  // Un paso cuyo padre nunca llegó no se pierde: se pinta al final y al nivel
  // de arriba. Pasaría si el mensaje de la delegación se perdiera, y quedarse
  // sin enseñar lo que se hizo sería peor que enseñarlo descolocado.
  final shown = {for (final row in rows) row.item.id};
  for (final item in items) {
    if (shown.contains(item.id)) continue;
    rows.add(ActivityRow(item: item, depth: 0, running: item.id == runningId));
  }

  return rows;
}
