import 'package:flutter/foundation.dart';
import 'package:nexus/features/history/domain/entities/conversation_summary.dart';

/// De cuándo es un día del historial, para poder titularlo.
enum CuandoFue {
  hoy,
  ayer,

  /// Cualquier otro: se titula con su fecha, porque «hace tres días» obliga a
  /// contar hacia atrás y una fecha no.
  antes,
}

/// Un día del historial: su fecha, lo que se hizo ese día y de cuándo es.
@immutable
class UnDiaDelHistorial {
  const UnDiaDelHistorial({
    required this.dia,
    required this.fichas,
    required this.cuando,
  });

  /// El día a las 00:00, que es lo que identifica al grupo.
  final DateTime dia;

  final List<ConversationSummary> fichas;
  final CuandoFue cuando;
}

/// El historial **por días**.
///
/// 🔴 **Pedido después de arreglar la fecha:** «que se organicen por fechas,
/// que tengan una separación visual y que aparezca la fecha en la vista de
/// historial». La lista era una tira de filas con una marca de tiempo completa
/// cada una —`2026-09-09 11:05`— repetida veinte veces: la fecha estaba, pero
/// **no organizaba nada**, y con veinte conversaciones no se veía dónde acababa
/// un día y empezaba el otro.
///
/// Agrupar es lo que convierte esa tira en algo que se recorre: el día se dice
/// **una vez** en su cabecera y cada fila se queda con su hora, que es lo único
/// que la distingue de sus vecinas.
///
/// Se agrupa por [ConversationSummary.usadaEn] y no por cuándo empezó, por lo
/// mismo que se ordena así: una conversación que se retomó hoy pertenece a hoy.
abstract final class LosDiasDelHistorial {
  /// Los días, del más reciente al más viejo, y dentro de cada uno lo más
  /// reciente primero.
  ///
  /// **Se ordena aquí y no se confía en el orden de entrada**: por esta función
  /// pasan la lista del almacén y la mezcla con el vault, y una de las dos
  /// llega ordenada por otra cosa el día que alguien toque su proveedor.
  static List<UnDiaDelHistorial> agrupa(
    List<ConversationSummary> fichas, {
    DateTime? hoy,
  }) {
    final ahora = hoy ?? DateTime.now();
    final elDiaDeHoy = _elDia(ahora);
    final elDiaDeAyer = elDiaDeHoy.subtract(const Duration(days: 1));

    final porDia = <DateTime, List<ConversationSummary>>{};
    for (final ficha in fichas) {
      porDia.putIfAbsent(_elDia(ficha.usadaEn), () => []).add(ficha);
    }

    final dias = porDia.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final dia in dias)
        UnDiaDelHistorial(
          dia: dia,
          fichas: porDia[dia]!..sort((a, b) => b.usadaEn.compareTo(a.usadaEn)),
          cuando: dia == elDiaDeHoy
              ? CuandoFue.hoy
              : dia == elDiaDeAyer
              ? CuandoFue.ayer
              : CuandoFue.antes,
        ),
    ];
  }

  /// El día de una fecha, a las 00:00 **en la hora de aquí**.
  ///
  /// Sin `toUtc()` a propósito: los días de un historial son los del reloj de
  /// quien lo mira, y en UTC una conversación de las once de la noche aparecería
  /// al día siguiente.
  static DateTime _elDia(DateTime cuando) =>
      DateTime(cuando.year, cuando.month, cuando.day);
}
