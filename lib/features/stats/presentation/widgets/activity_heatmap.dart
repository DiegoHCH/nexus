import 'package:flutter/material.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/stats/domain/entities/usage_stats.dart';

/// El calendario de actividad: una casilla por día, más encendida cuanto más
/// se trabajó.
///
/// Contesta una pregunta que ninguna cifra contesta —«¿cómo trabajo?»— y la
/// contesta de un vistazo: los huecos de los fines de semana, la semana que
/// desapareciste, el atracón de tres días seguidos. Una lista de días con su
/// número diría lo mismo y no lo diría nunca.
class ActivityHeatmap extends StatelessWidget {
  const ActivityHeatmap({super.key, required this.days});

  final List<DayActivity> days;

  static const _cell = 13.0;
  static const _gap = 3.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (days.isEmpty) return const SizedBox.shrink();

    final byDay = {for (final day in days) _key(day.day): day.messages};
    final busiest = days
        .map((day) => day.messages)
        .reduce((a, b) => a > b ? a : b);

    // Semanas completas de lunes a domingo: media semana suelta al principio
    // deja la primera columna coja y engaña sobre qué día es cada fila.
    final last = DateTime.now();
    final first = days.first.day;
    final start = first.subtract(Duration(days: (first.weekday - 1) % 7));
    final weeks = (last.difference(start).inDays / 7).ceil() + 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          // Al final: lo reciente es lo que se mira, y con un año de historial
          // la vista arrancaría en enero.
          reverse: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var week = weeks - 1; week >= 0; week--)
                Padding(
                  padding: const EdgeInsets.only(left: _gap),
                  child: Column(
                    children: [
                      for (var weekday = 0; weekday < 7; weekday++)
                        Builder(
                          builder: (context) {
                            final day = start.add(
                              Duration(days: week * 7 + weekday),
                            );
                            final count = byDay[_key(day)] ?? 0;
                            final future = day.isAfter(last);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: _gap),
                              child: Tooltip(
                                message: future
                                    ? ''
                                    : context.strings.statsDayTooltip(
                                        _label(day),
                                        count,
                                      ),
                                child: Container(
                                  width: _cell,
                                  height: _cell,
                                  decoration: BoxDecoration(
                                    color: future
                                        ? Colors.transparent
                                        : _shade(colors, count, busiest),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Cuatro escalones y no un degradado continuo: con la escala lineal, un día
  /// de mil mensajes deja el resto del año en negro. Lo que se quiere ver es
  /// «hubo trabajo / hubo mucho», no la cifra exacta — esa está en el tooltip.
  Color _shade(NexusColors colors, int count, int busiest) {
    if (count == 0) return colors.rule2.withValues(alpha: 0.25);
    final ratio = count / busiest;
    final alpha = switch (ratio) {
      > 0.6 => 1.0,
      > 0.3 => 0.7,
      > 0.1 => 0.45,
      _ => 0.25,
    };
    return colors.cyan.withValues(alpha: alpha);
  }

  static String _key(DateTime day) => '${day.year}-${day.month}-${day.day}';

  static String _label(DateTime day) =>
      '${day.day.toString().padLeft(2, '0')}/'
      '${day.month.toString().padLeft(2, '0')}/${day.year}';
}
