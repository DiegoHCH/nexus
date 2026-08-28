import 'package:nexus/features/e2e/domain/entities/pasada_de_prueba.dart';

/// Qué se puede decir de las pruebas **con un número**, y qué no.
///
/// Nace de un encargo concreto de la propuesta de valor: «los argumentos de
/// adopción se mueren sin una medición, y este repo mide absolutamente todo lo
/// demás». La frase que se quería llevar a una reunión era «el suite pasó de
/// correrlo una persona al mes a correrlo cualquiera a diario».
///
/// **La mitad de esa frase no se puede medir desde aquí y no se finge.** Nexus
/// ve las pasadas de *esta* máquina: sabe cuántas veces y en cuántos días
/// distintos, y no sabe cuánta gente. Un contador que dijera «cualquiera»
/// estaría contando una sola persona y llamándola equipo, y una pantalla que se
/// equivoca en esto es peor que no tenerla: se lee como una promesa.
///
/// Así que lo que se da es lo que se sabe: **cuántas, en cuántos días, y contra
/// el mes anterior**. Es un número honesto y sigue sirviendo para la reunión —
/// «pasó de 3 pasadas en 11 días a 47 en 22» dice lo mismo sin inventarse a
/// nadie.
typedef NumeroDeLasPruebas = ({
  /// Pasadas de los últimos 30 días, y las de los 30 anteriores.
  int ultimos30,
  int previos30,

  /// Cuántas veces más que el mes anterior. `null` cuando no hay con qué
  /// comparar, que es distinto de «no creció».
  double? veces,

  /// Días **distintos** con al menos una pasada, de los últimos 30. Es el dato
  /// que separa «se corre» de «se corrió»: 40 pasadas en un solo día es una
  /// tarde de alguien peleándose con un flow, no una costumbre.
  int dias,

  /// De las que acabaron en los últimos 30. Las que siguen en marcha y las que
  /// no dejaron rastro no cuentan a ningún lado: no son un resultado.
  int bien,
  int mal,

  /// Cuántos proyectos distintos se probaron en los últimos 30.
  int proyectos,

  /// Desde cuándo hay registro. Sin esto, «47 pasadas» no dice nada: no es lo
  /// mismo en dos semanas que en dos años.
  DateTime? desde,
});

abstract final class ElNumeroDeLasPruebas {
  /// La ventana, en días. Treinta y no siete porque una semana mala —una
  /// release, unas vacaciones— movería el número entero, y este número existe
  /// para llevarlo a una reunión y no para mirarlo cada mañana.
  static const ventana = 30;

  static NumeroDeLasPruebas de(
    List<PasadaDePrueba> pasadas, {
    required DateTime ahora,
  }) {
    final corte = ahora.subtract(const Duration(days: ventana));
    final corteAnterior = ahora.subtract(const Duration(days: ventana * 2));

    var ultimos30 = 0;
    var previos30 = 0;
    var bien = 0;
    var mal = 0;
    final dias = <String>{};
    final proyectos = <String>{};
    DateTime? desde;

    for (final pasada in pasadas) {
      final cuando = pasada.cuando;
      if (desde == null || cuando.isBefore(desde)) desde = cuando;

      if (cuando.isBefore(corteAnterior)) continue;
      if (cuando.isBefore(corte)) {
        previos30++;
        continue;
      }

      ultimos30++;
      dias.add('${cuando.year}-${cuando.month}-${cuando.day}');
      if (pasada.proyecto case final proyecto?) proyectos.add(proyecto);
      switch (pasada.comoAcabo) {
        case ComoAcabo.bien:
          bien++;
        case ComoAcabo.mal:
          mal++;
        // En marcha todavía no es un resultado, y sin `commands.json` no se
        // sabe: contarlas como fallo inflaría el único número que nadie quiere
        // inflado.
        case ComoAcabo.enMarcha:
        case ComoAcabo.vayaUstedASaber:
          break;
      }
    }

    return (
      ultimos30: ultimos30,
      previos30: previos30,
      veces: previos30 == 0 ? null : ultimos30 / previos30,
      dias: dias.length,
      bien: bien,
      mal: mal,
      proyectos: proyectos.length,
      desde: desde,
    );
  }
}
