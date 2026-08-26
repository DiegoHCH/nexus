import 'package:flutter/foundation.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/features/workspace/data/datasources/cierre_de_la_corrida_data_source.dart';

/// Una tarea de punta a punta, armada con lo que ya quedó registrado.
///
/// **No guarda nada suyo.** El plan firmado, la corrida del gate y el cierre viven cada
/// uno en su archivo porque cada uno lo escribe un momento distinto; esto solo los pone
/// uno al lado del otro y saca los tramos. Un cuarto archivo que repitiera esas fechas
/// sería un cuarto sitio del que dudar cuando dos no coincidan.
///
/// Recibe fechas y no objetos de la capa de datos a propósito: así los tramos —que es lo
/// único con reglas de verdad aquí— se prueban sin tocar el disco.
@immutable
class LaCorrida {
  const LaCorrida({
    this.rama,
    this.plan,
    this.firmado,
    this.gateVerde,
    this.gateCorrio,
    this.cierres = const [],
  });

  final String? rama;

  /// Lo que se dijo que se iba a hacer, y cuándo se firmó.
  final String? plan;
  final DateTime? firmado;

  /// Cuándo corrió el gate por última vez, y si salió verde.
  final DateTime? gateCorrio;
  final bool? gateVerde;

  /// Todos, del más antiguo al más reciente. Una rama se cierra más de una vez: el PR
  /// vuelve con observaciones y lo que sigue es otra corrida del mismo trabajo.
  final List<Cierre> cierres;

  /// El cierre que manda, si esta corrida ya terminó.
  ///
  /// **Firmar un plan después de cerrar abre una corrida nueva.** No hace falta declararlo
  /// en ninguna parte, y ese es el punto: cuando el PR rebota, lo primero que se hace es
  /// decir qué se va a corregir — que es exactamente firmar. Pedir además un «empezar de
  /// nuevo» sería un trámite para informar de algo que ya se ve.
  Cierre? get cierre {
    if (cierres.isEmpty) return null;
    final ultimo = cierres.last;
    if (firmado != null && firmado!.isAfter(ultimo.cuando)) return null;
    return ultimo;
  }

  bool get abierta => cierre == null;

  /// Las corridas anteriores de esta misma rama, ya archivadas.
  ///
  /// Se archivan solas al firmar de nuevo, así que un rebote no pisa lo de antes: son dos
  /// corridas del mismo trabajo y la primera suele ser la más larga.
  List<Cierre> get anteriores =>
      abierta ? cierres : cierres.sublist(0, cierres.length - 1);

  /// Cuándo empezó, o `null` si no hay por dónde saberlo.
  ///
  /// La firma del plan es el arranque porque es el primer acto deliberado de la tarea. En
  /// una carpeta que no exige plan no hay tal acto, y entonces vale la primera señal que
  /// haya — el gate. Y si tampoco, esta corrida no se puede medir: se dice, no se
  /// rellena con la hora del cierre para que la resta dé cero.
  DateTime? get empezo => firmado ?? gateCorrio;

  /// De firmar el plan a correr el gate.
  Duration? get construyendo {
    final inicio = firmado;
    final fin = gateCorrio;
    if (inicio == null || fin == null || fin.isBefore(inicio)) return null;
    return fin.difference(inicio);
  }

  /// Del gate al cierre. Es lo que cuesta publicar, y suele sorprender.
  Duration? get cerrando {
    final inicio = gateCorrio;
    final fin = cierre?.cuando;
    if (inicio == null || fin == null || fin.isBefore(inicio)) return null;
    return fin.difference(inicio);
  }

  Duration? get total {
    final inicio = empezo;
    final fin = cierre?.cuando;
    if (inicio == null || fin == null || fin.isBefore(inicio)) return null;
    return fin.difference(inicio);
  }

  /// Cuánto lleva abierta, para poder decirlo mientras dura.
  Duration? llevaEn(DateTime ahora) {
    final inicio = empezo;
    if (inicio == null || !abierta) return null;
    final va = ahora.toUtc().difference(inicio);
    return va.isNegative ? Duration.zero : va;
  }

  /// El resumen de la corrida, en llano y para quien no programa.
  ///
  /// **Lo arma el código, no el asistente.** Sale siempre y sale igual: con lo mismo
  /// registrado dice lo mismo, así que se puede pegar en un ticket sin releerlo. Un
  /// resumen redactado por el modelo sería más bonito y no serviría para lo que sirve
  /// este, que es que dos tareas se puedan comparar.
  ///
  /// Y lo que no se sabe **se dice que no se sabe**. Un tramo sin medir escrito como cero
  /// convierte «no lo registramos» en «no costó nada».
  String resumen(NexusStrings strings) {
    final cerrada = cierre;
    final lineas = <String>[
      if (rama case final r? when r.isNotEmpty) strings.corridaSummaryBranch(r),
      if (cerrada != null)
        strings.corridaSummaryWhat(cerrada.narrativa)
      else
        strings.corridaSummaryStillOpen,
      if (plan case final p? when p.trim().isNotEmpty)
        strings.corridaSummaryPlan(p.trim()),
      switch (gateVerde) {
        true => strings.corridaSummaryGateGreen,
        false => strings.corridaSummaryGateRed,
        null => strings.corridaSummaryGateNever,
      },
      if (total case final t?)
        strings.corridaSummaryTotal(_enLlano(t, strings))
      else
        strings.corridaSummaryTotalUnknown,
      if (construyendo case final c?)
        strings.corridaSummaryBuilding(_enLlano(c, strings)),
      if (cerrando case final c?)
        strings.corridaSummaryClosing(_enLlano(c, strings)),
      if (cerrada != null && cerrada.como == ComoTermino.sinProduccion)
        strings.corridaSummaryNoProd,
      if (cerrada != null && cerrada.como == ComoTermino.cancelada)
        strings.corridaSummaryCancelled,
    ];
    return lineas.join('\n');
  }

  static String _enLlano(Duration cuanto, NexusStrings strings) {
    final horas = cuanto.inHours;
    final minutos = cuanto.inMinutes % 60;
    return horas > 0
        ? strings.durationHoursMinutes(horas, minutos)
        : strings.durationMinutes(cuanto.inMinutes);
  }
}
