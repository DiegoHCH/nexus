/// El tramo de tiempo que se está mirando.
enum StatsRange {
  all(null),
  days30(30),
  days7(7);

  const StatsRange(this.days);

  /// `null` en «todo»: no hay corte que aplicar.
  final int? days;
}

/// Lo que se ha gastado con un modelo.
class ModelUsage {
  const ModelUsage({
    required this.model,
    required this.input,
    required this.output,
    required this.share,
  });

  final String model;
  final int input;
  final int output;

  /// Su parte del total, de 0 a 1.
  final double share;

  int get tokens => input + output;
}

/// Cuánto se trabajó un día. La unidad del mapa de calor.
class DayActivity {
  const DayActivity({required this.day, required this.messages});

  final DateTime day;
  final int messages;
}

/// Todo lo que se enseña de una cuenta en un tramo.
class UsageStats {
  const UsageStats({
    required this.sessions,
    required this.messages,
    required this.input,
    required this.output,
    required this.cached,
    required this.activeDays,
    required this.currentStreak,
    required this.longestStreak,
    required this.peakHour,
    required this.models,
    required this.days,
  });

  static const empty = UsageStats(
    sessions: 0,
    messages: 0,
    input: 0,
    output: 0,
    cached: 0,
    activeDays: 0,
    currentStreak: 0,
    longestStreak: 0,
    peakHour: null,
    models: [],
    days: [],
  );

  final int sessions;
  final int messages;
  final int input;
  final int output;
  final int cached;
  final int activeDays;

  /// Días seguidos trabajando hasta hoy. Cero si ayer y hoy están vacíos.
  final int currentStreak;
  final int longestStreak;

  /// La hora del día con más actividad, de 0 a 23. `null` si no hay nada.
  final int? peakHour;

  /// De más gastado a menos.
  final List<ModelUsage> models;

  /// Un día por jornada con actividad, en orden.
  final List<DayActivity> days;

  int get tokens => input + output;

  /// El más usado por tokens, que es la pregunta que contesta la ficha: no
  /// «cuál abriste más veces» sino «en cuál se te va el trabajo».
  String? get favoriteModel => models.isEmpty ? null : models.first.model;

  bool get isEmpty => messages == 0;
}
