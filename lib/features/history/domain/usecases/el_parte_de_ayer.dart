import 'package:nexus/features/history/domain/entities/conversation_summary.dart';

/// El parte del día anterior: qué se hizo con Claude, para contarlo en el daily.
///
/// **Lo escribe Claude, no esto.** Aquí solo se decide qué día se cuenta y qué
/// material se le pone delante — que es donde está el criterio, porque un parte
/// se estropea por dos sitios: contando el día equivocado, o dejando que quien
/// lo redacta rellene los huecos.
abstract final class ElParteDeAyer {
  /// El día que se cuenta: **el último con actividad antes de hoy**, no ayer.
  ///
  /// Un lunes, «ayer» es domingo y el domingo no se trabajó: el parte saldría
  /// vacío justo el día que más se usa. Con esto, el lunes se cuenta el
  /// viernes; y volviendo de vacaciones, el último día que hubo algo.
  ///
  /// Nunca hoy, aunque haya actividad: el parte es de lo cerrado, y lo de esta
  /// mañana todavía se está haciendo.
  static DateTime? elDia(
    List<ConversationSummary> todas, {
    required DateTime hoy,
  }) {
    final deHoy = _soloElDia(hoy);
    DateTime? mejor;
    for (final ficha in todas) {
      final dia = _soloElDia(ficha.startedAt);
      if (!dia.isBefore(deHoy)) continue;
      if (mejor == null || dia.isAfter(mejor)) mejor = dia;
    }
    return mejor;
  }

  /// Lo que se le pide a Claude, con el material dentro. `null` si no hay nada
  /// que contar — **y eso se dice, no se pregunta**: pedirle un parte de un día
  /// vacío es pedirle que se lo invente.
  static String? instruccion(
    List<ConversationSummary> todas, {
    required DateTime hoy,
  }) {
    final dia = elDia(todas, hoy: hoy);
    if (dia == null) return null;

    final delDia =
        todas.where((ficha) => _soloElDia(ficha.startedAt) == dia).toList()
          ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    if (delDia.isEmpty) return null;

    final porCarpeta = <String, List<ConversationSummary>>{};
    for (final ficha in delDia) {
      porCarpeta.putIfAbsent(ficha.folderPath, () => []).add(ficha);
    }

    final material = StringBuffer();
    for (final entrada in porCarpeta.entries) {
      material.writeln('- ${_nombreDe(entrada.key)} (${entrada.key}):');
      for (final ficha in entrada.value) {
        material.writeln(
          '    · ${_hora(ficha.startedAt)} — «${ficha.title}» '
          '(${ficha.turns} ${ficha.turns == 1 ? 'turno' : 'turnos'})',
        );
      }
    }

    return '''
Escribe mi parte de trabajo del ${_fecha(dia)} para el daily del equipo.

Esto es lo que hice contigo ese día, sacado del historial de esta máquina:

$material
Con eso y con lo que puedas mirar en el repositorio donde estás —los commits de
ese día, la rama, los PR— redacta el parte.

Cómo lo quiero:
- Tres apartados: **Qué hice**, **Qué sigue** y **Bloqueos**. Si no hay bloqueos,
  escribe «ninguno» y no te inventes uno.
- En primera persona y en pasado, como lo diría yo en la reunión.
- Por resultado, no por actividad: «dejé el visor de cambios funcionando», no
  «trabajé en el visor de cambios».
- Corto. Esto se lee en voz alta en dos minutos.
- **No añadas nada que no puedas sostener** con el historial de arriba o con lo
  que veas en el repositorio. Si un título no te dice qué se hizo, dilo así en
  vez de rellenarlo.

Devuelve solo el parte, sin preámbulo ni despedida: va a Slack tal cual.''';
  }

  static DateTime _soloElDia(DateTime cuando) =>
      DateTime(cuando.year, cuando.month, cuando.day);

  static String _fecha(DateTime dia) =>
      '${dia.day.toString().padLeft(2, '0')}/'
      '${dia.month.toString().padLeft(2, '0')}/${dia.year}';

  static String _hora(DateTime cuando) =>
      '${cuando.hour.toString().padLeft(2, '0')}:'
      '${cuando.minute.toString().padLeft(2, '0')}';

  static String _nombreDe(String ruta) {
    final limpio = ruta.endsWith('/')
        ? ruta.substring(0, ruta.length - 1)
        : ruta;
    final barra = limpio.lastIndexOf('/');
    return barra == -1 ? limpio : limpio.substring(barra + 1);
  }
}
