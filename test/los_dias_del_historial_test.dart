import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/features/history/domain/entities/conversation_summary.dart';
import 'package:nexus/features/history/domain/usecases/los_dias_del_historial.dart';

/// **El historial por días.**
///
/// 🔴 Pedido justo después de arreglar la fecha: «que se organicen por fechas,
/// que tengan una separación visual y que aparezca la fecha en la vista de
/// historial». La lista era una tira de filas con la marca de tiempo completa
/// repetida en cada una —`2026-09-09 11:05`—: la fecha estaba y **no
/// organizaba nada**, y con veinte conversaciones no se veía dónde acababa un
/// día y empezaba el otro.
ConversationSummary _ficha(String id, DateTime usadaEn, {DateTime? empezo}) =>
    ConversationSummary(
      id: id,
      folderPath: '/Users/alguien/Workspace/front-mobile-b2c',
      startedAt: empezo ?? usadaEn,
      usadaEn: usadaEn,
      title: id,
      turns: 4,
    );

void main() {
  final hoy = DateTime(2026, 9, 9, 15, 30);

  group('los días', () {
    test('lo del mismo día va junto, del más reciente al más viejo', () {
      final dias = LosDiasDelHistorial.agrupa([
        _ficha('mañana', DateTime(2026, 9, 9, 9)),
        _ficha('mediodía', DateTime(2026, 9, 9, 13)),
        _ficha('anoche', DateTime(2026, 9, 8, 22)),
      ], hoy: hoy);

      expect(dias, hasLength(2));
      expect(dias.first.fichas.map((f) => f.id), ['mediodía', 'mañana']);
      expect(dias.last.fichas.map((f) => f.id), ['anoche']);
    });

    test('y los días, el más reciente arriba', () {
      final dias = LosDiasDelHistorial.agrupa([
        _ficha('vieja', DateTime(2026, 9, 1, 10)),
        _ficha('de hoy', DateTime(2026, 9, 9, 10)),
        _ficha('de ayer', DateTime(2026, 9, 8, 10)),
      ], hoy: hoy);

      expect(dias.map((d) => d.dia), [
        DateTime(2026, 9, 9),
        DateTime(2026, 9, 8),
        DateTime(2026, 9, 1),
      ]);
    });

    test('hoy y ayer tienen nombre; lo de antes, su fecha', () {
      final dias = LosDiasDelHistorial.agrupa([
        _ficha('a', DateTime(2026, 9, 9, 10)),
        _ficha('b', DateTime(2026, 9, 8, 10)),
        _ficha('c', DateTime(2026, 9, 7, 10)),
      ], hoy: hoy);

      expect(dias.map((d) => d.cuando), [
        CuandoFue.hoy,
        CuandoFue.ayer,
        CuandoFue.antes,
      ]);
    });

    // 🔴 **Se agrupa por cuándo se usó, no por cuándo empezó**, que es lo mismo
    // que se arregló al ordenar: una conversación de anteayer que se retomó hoy
    // pertenece a hoy. Si se agrupara por el comienzo, el trabajo de hoy
    // seguiría escondido bajo la cabecera de anteayer.
    test('la retomada hoy va en hoy, aunque empezara hace tres días', () {
      final dias = LosDiasDelHistorial.agrupa([
        _ficha(
          'la larga',
          DateTime(2026, 9, 9, 11),
          empezo: DateTime(2026, 9, 6, 22),
        ),
      ], hoy: hoy);

      expect(dias.single.cuando, CuandoFue.hoy);
      expect(dias.single.dia, DateTime(2026, 9, 9));
    });

    // El día es el del reloj de quien mira: en UTC, una conversación de las
    // once de la noche se iría al día siguiente.
    test('una de las once de la noche es de ese día, no del siguiente', () {
      final dias = LosDiasDelHistorial.agrupa([
        _ficha('tarde', DateTime(2026, 9, 8, 23, 50)),
      ], hoy: hoy);

      expect(dias.single.dia, DateTime(2026, 9, 8));
      expect(dias.single.cuando, CuandoFue.ayer);
    });

    test('sin nada, ningún día', () {
      expect(LosDiasDelHistorial.agrupa(const [], hoy: hoy), isEmpty);
    });

    // Por aquí pasan la lista del almacén y la mezcla con el vault: una de las
    // dos llegará desordenada el día que alguien toque su proveedor.
    test('no se confía en el orden de entrada', () {
      final dias = LosDiasDelHistorial.agrupa([
        _ficha('vieja', DateTime(2026, 9, 1)),
        _ficha('nueva', DateTime(2026, 9, 9, 8)),
        _ficha('la de en medio', DateTime(2026, 9, 9, 12)),
      ], hoy: hoy);

      expect(dias.first.fichas.map((f) => f.id), ['la de en medio', 'nueva']);
    });
  });

  group('cómo se titula un día', () {
    test('en español, con el año solo cuando no es este', () {
      const textos = NexusStringsEs();

      expect(textos.historialHoy, 'Hoy');
      expect(textos.historialAyer, 'Ayer');
      expect(
        textos.historialDia(DateTime(2026, 9, 8), conElAno: false),
        '8 de septiembre',
      );
      expect(
        textos.historialDia(DateTime(2025, 12, 31), conElAno: true),
        '31 de diciembre de 2025',
      );
    });

    test('y en inglés', () {
      const textos = NexusStringsEn();

      expect(textos.historialHoy, 'Today');
      expect(
        textos.historialDia(DateTime(2026, 9, 8), conElAno: false),
        'September 8',
      );
      expect(
        textos.historialDia(DateTime(2025, 1, 3), conElAno: true),
        'January 3, 2025',
      );
    });

    // Los doce, porque un mes mal puesto en la tabla no se ve mirando el código
    // y sí en la pantalla de quien busca algo de marzo.
    test('los doce meses, en los dos idiomas', () {
      for (final textos in [const NexusStringsEs(), const NexusStringsEn()]) {
        final dichos = {
          for (var mes = 1; mes <= 12; mes++)
            textos.historialDia(DateTime(2026, mes, 1), conElAno: false),
        };
        expect(dichos, hasLength(12), reason: 'hay un mes repetido');
      }
    });
  });
}
