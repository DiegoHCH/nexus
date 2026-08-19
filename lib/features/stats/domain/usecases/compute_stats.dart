import 'package:nexus/features/stats/domain/entities/transcript_turn.dart';
import 'package:nexus/features/stats/domain/entities/usage_stats.dart';

/// Las cuentas, aparte de dónde salen los datos y de cómo se pintan.
///
/// Está separado de la lectura del disco a propósito: leer 250 archivos tarda
/// segundos y cambiar de tramo —todo, 30 días, 7 días— no puede volver a
/// leerlos. Se lee una vez, se cuenta tantas veces como haga falta.
abstract final class ComputeStats {
  /// [now] entra como parámetro porque las rachas se miden **contra hoy**, y
  /// una función que mira el reloj por su cuenta no se puede probar.
  static UsageStats from(
    List<TranscriptTurn> turns,
    StatsRange range, {
    required DateTime now,
  }) {
    final since = range.days == null
        ? null
        : _dayOf(now).subtract(Duration(days: range.days! - 1));
    final inRange = since == null
        ? turns
        : turns.where((turn) => !turn.at.isBefore(since)).toList();
    if (inRange.isEmpty) return UsageStats.empty;

    final sessions = <String>{};
    final byHour = List.filled(24, 0);
    final byDay = <DateTime, int>{};
    final input = <String, int>{};
    final output = <String, int>{};
    var totalInput = 0;
    var totalOutput = 0;
    var totalCached = 0;

    for (final turn in inRange) {
      sessions.add(turn.sessionId);
      byHour[turn.at.hour]++;
      byDay.update(_dayOf(turn.at), (n) => n + 1, ifAbsent: () => 1);
      totalInput += turn.input;
      totalOutput += turn.output;
      totalCached += turn.cached;
      final model = turn.model;
      if (model != null) {
        input.update(model, (n) => n + turn.input, ifAbsent: () => turn.input);
        output.update(
          model,
          (n) => n + turn.output,
          ifAbsent: () => turn.output,
        );
      }
    }

    final total = totalInput + totalOutput;
    final models =
        input.keys
            .map(
              (model) => ModelUsage(
                model: model,
                input: input[model] ?? 0,
                output: output[model] ?? 0,
                share: total == 0
                    ? 0
                    : ((input[model] ?? 0) + (output[model] ?? 0)) / total,
              ),
            )
            .where((usage) => usage.tokens > 0)
            .toList()
          ..sort((a, b) => b.tokens.compareTo(a.tokens));

    final days = byDay.keys.toList()..sort();
    var peak = 0;
    for (var hour = 1; hour < 24; hour++) {
      if (byHour[hour] > byHour[peak]) peak = hour;
    }

    return UsageStats(
      sessions: sessions.length,
      messages: inRange.length,
      input: totalInput,
      output: totalOutput,
      cached: totalCached,
      activeDays: days.length,
      currentStreak: _currentStreak(byDay.keys.toSet(), _dayOf(now)),
      longestStreak: _longestStreak(days),
      peakHour: byHour[peak] == 0 ? null : peak,
      models: models,
      days: [
        for (final day in days) DayActivity(day: day, messages: byDay[day]!),
      ],
    );
  }

  static DateTime _dayOf(DateTime at) => DateTime(at.year, at.month, at.day);

  /// Cuenta hacia atrás desde hoy.
  ///
  /// Si hoy no hay nada todavía se empieza por ayer, en vez de dar cero: a las
  /// nueve de la mañana, una racha de doce días no se ha roto — es que aún no
  /// has empezado. Cortarla ahí sería contar el día antes de que ocurra.
  static int _currentStreak(Set<DateTime> days, DateTime today) {
    var cursor = days.contains(today)
        ? today
        : today.subtract(const Duration(days: 1));
    var streak = 0;
    while (days.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  static int _longestStreak(List<DateTime> days) {
    if (days.isEmpty) return 0;
    var longest = 1;
    var run = 1;
    for (var i = 1; i < days.length; i++) {
      final gap = days[i].difference(days[i - 1]).inDays;
      run = gap == 1 ? run + 1 : 1;
      if (run > longest) longest = run;
    }
    return longest;
  }
}
