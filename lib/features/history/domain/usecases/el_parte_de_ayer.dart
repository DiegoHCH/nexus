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
  /// Solo lo de un proyecto, si se pide.
  ///
  /// **No es un filtro de comodidad: es de sitio.** El parte va al Slack de un
  /// equipo concreto, y sin esto lo que hiciste en tus proyectos personales
  /// —o en otro repo del mismo trabajo— acabaría contado en ese daily.
  ///
  /// Por carpeta y no por cuenta de Claude, que era lo primero que se pensó:
  /// una carpeta ya implica su cuenta, así que filtrar por proyecto excluye lo
  /// personal por construcción **y además** deja fuera los demás repos del
  /// trabajo, que tampoco van a ese daily.
  /// Si lo que se escribió en el compositor es pedir el parte.
  ///
  /// Hablando lo decide el modelo, que entiende la frase que sea; escribiendo no
  /// hay quien lo decida, y «dame el daily» acababa siendo un encargo suelto
  /// para Claude — que no tiene delante lo de ayer, así que contestaba algo con
  /// cara de parte que no lo era.
  ///
  /// **Se compara la frase entera, no un trozo.** Buscando «daily» dentro del
  /// texto, «mira por qué falla el job del daily» dejaría de ser un encargo y
  /// se convertiría en un resumen: secuestrar trabajo de verdad es mucho peor
  /// que no reconocer una forma de pedirlo. Por eso la lista es corta y
  /// cerrada, y lo que no encaje sigue su camino de siempre.
  static bool loEstanPidiendo(String frase) =>
      _comoSePide.contains(_sinAdornos(frase));

  /// Las formas que se reconocen. Cortas a propósito: son las que se escriben
  /// **para pedir esto y nada más**.
  static const _comoSePide = {
    'daily',
    'el daily',
    'dame el daily',
    'damos el daily',
    'daily de ayer',
    'el daily de ayer',
    'parte',
    'el parte',
    'dame el parte',
    'parte del dia',
    'el parte del dia',
    'dame el parte del dia',
    'standup',
    'el standup',
    'dame el standup',
    'que hice ayer',
    'que hice el dia anterior',
    'resumen de ayer',
    'cuentame lo de ayer',
  };

  /// Minúsculas, sin acentos y sin signos: se escribe con prisa, y «¿Qué hice
  /// ayer?» es la misma petición que «que hice ayer».
  static String _sinAdornos(String frase) {
    const acentos = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n',
    };
    var limpia = frase.toLowerCase().trim();
    acentos.forEach((con, sin) => limpia = limpia.replaceAll(con, sin));
    return limpia
        .replaceAll(RegExp(r'[¿?¡!.,;:]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static List<ConversationSummary> _delProyecto(
    List<ConversationSummary> todas,
    String? carpeta,
  ) {
    if (carpeta == null || carpeta.isEmpty) return todas;
    return todas.where((ficha) => ficha.folderPath == carpeta).toList();
  }

  static DateTime? elDia(
    List<ConversationSummary> todas, {
    required DateTime hoy,
    String? soloDelProyecto,
  }) {
    final miradas = _delProyecto(todas, soloDelProyecto);
    final deHoy = _soloElDia(hoy);
    DateTime? mejor;
    for (final ficha in miradas) {
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
    String? soloDelProyecto,
  }) {
    final miradas = _delProyecto(todas, soloDelProyecto);
    final dia = elDia(todas, hoy: hoy, soloDelProyecto: soloDelProyecto);
    if (dia == null) return null;

    final delDia =
        miradas.where((ficha) => _soloElDia(ficha.startedAt) == dia).toList()
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
