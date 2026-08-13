import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/stats/domain/entities/transcript_turn.dart';
import 'package:nexus/features/stats/domain/entities/usage_stats.dart';
import 'package:nexus/features/stats/domain/usecases/compute_stats.dart';

TranscriptTurn _turn(
  String day, {
  String session = 's1',
  String? model,
  int input = 0,
  int output = 0,
  int cached = 0,
  int hour = 12,
}) => TranscriptTurn(
  at: DateTime.parse('$day ${hour.toString().padLeft(2, '0')}:00:00'),
  sessionId: session,
  fromAssistant: model != null,
  model: model,
  input: input,
  output: output,
  cached: cached,
);

void main() {
  final hoy = DateTime.parse('2026-08-13 09:00:00');

  test('sin nada, no se inventan ceros con forma de estadística', () {
    expect(
      ComputeStats.from(const [], StatsRange.all, now: hoy).isEmpty,
      isTrue,
    );
  });

  test('las sesiones se cuentan por identificador, no por mensaje', () {
    final stats = ComputeStats.from(
      [
        _turn('2026-08-13', session: 'a'),
        _turn('2026-08-13', session: 'a'),
        _turn('2026-08-13', session: 'b'),
      ],
      StatsRange.all,
      now: hoy,
    );

    expect(stats.sessions, 2);
    expect(stats.messages, 3);
  });

  // La caché es real y es enorme: en la cuenta de trabajo son 4 967 M frente a
  // 15 M de salida. Sumarla al total dejaría cualquier gráfico en una barra.
  test('la caché se cuenta aparte y no entra en el total', () {
    final stats = ComputeStats.from(
      [
        _turn(
          '2026-08-13',
          model: 'claude-opus-5',
          input: 10,
          output: 90,
          cached: 50000,
        ),
      ],
      StatsRange.all,
      now: hoy,
    );

    expect(stats.tokens, 100);
    expect(stats.cached, 50000);
  });

  group('el tramo', () {
    final turnos = [
      _turn('2026-06-01', output: 1),
      _turn('2026-08-01', output: 1),
      _turn('2026-08-12', output: 1),
      _turn('2026-08-13', output: 1),
    ];

    test('«todo» no corta nada', () {
      expect(ComputeStats.from(turnos, StatsRange.all, now: hoy).messages, 4);
    });

    // Siete días **incluyendo hoy**, no ocho: un «7d» que se lleva ocho
    // jornadas es de esos fallos que nadie mira y todos arrastran.
    test('«7d» se queda con hoy y los seis anteriores', () {
      expect(ComputeStats.from(turnos, StatsRange.days7, now: hoy).messages, 2);
    });

    test('«30d» alcanza a agosto pero no a junio', () {
      expect(
        ComputeStats.from(turnos, StatsRange.days30, now: hoy).messages,
        3,
      );
    });
  });

  group('las rachas', () {
    test('los días seguidos hasta hoy', () {
      final stats = ComputeStats.from(
        [_turn('2026-08-11'), _turn('2026-08-12'), _turn('2026-08-13')],
        StatsRange.all,
        now: hoy,
      );

      expect(stats.currentStreak, 3);
      expect(stats.longestStreak, 3);
    });

    // A las nueve de la mañana, una racha de doce días no se ha roto: es que
    // aún no has empezado. Cortarla ahí sería contar el día antes de que pase.
    test('si hoy todavía no hay nada, la racha sigue viva desde ayer', () {
      final stats = ComputeStats.from(
        [_turn('2026-08-11'), _turn('2026-08-12')],
        StatsRange.all,
        now: hoy,
      );

      expect(stats.currentStreak, 2);
    });

    test('un hueco la rompe, y la más larga se recuerda', () {
      final stats = ComputeStats.from(
        [
          _turn('2026-08-01'),
          _turn('2026-08-02'),
          _turn('2026-08-03'),
          _turn('2026-08-13'),
        ],
        StatsRange.all,
        now: hoy,
      );

      expect(stats.currentStreak, 1);
      expect(stats.longestStreak, 3);
    });
  });

  test('la hora punta es la de más movimiento, en local', () {
    final stats = ComputeStats.from(
      [
        _turn('2026-08-13', hour: 9),
        _turn('2026-08-13', hour: 16),
        _turn('2026-08-13', hour: 16),
      ],
      StatsRange.all,
      now: hoy,
    );

    expect(stats.peakHour, 16);
  });

  group('los modelos', () {
    test('se ordenan por lo gastado y reparten el 100%', () {
      final stats = ComputeStats.from(
        [
          _turn('2026-08-13', model: 'claude-sonnet-5', output: 250),
          _turn('2026-08-13', model: 'claude-opus-5', output: 750),
        ],
        StatsRange.all,
        now: hoy,
      );

      expect(stats.models.map((m) => m.model), [
        'claude-opus-5',
        'claude-sonnet-5',
      ]);
      expect(stats.models.first.share, 0.75);
      expect(stats.favoriteModel, 'claude-opus-5');
    });

    // El favorito es el de más tokens, no el de más mensajes: la pregunta que
    // contesta la ficha es en cuál se te va el trabajo.
    test('el favorito lo decide el gasto, no el número de turnos', () {
      final stats = ComputeStats.from(
        [
          for (var i = 0; i < 20; i++)
            _turn('2026-08-13', model: 'claude-haiku-4-5', output: 10),
          _turn('2026-08-13', model: 'claude-opus-5', output: 5000),
        ],
        StatsRange.all,
        now: hoy,
      );

      expect(stats.favoriteModel, 'claude-opus-5');
    });

    // Los turnos del usuario no eligen modelo, y los del CLI llegan marcados
    // como `<synthetic>`: ninguno puede aparecer en la lista.
    test('un turno sin modelo no crea una entrada vacía', () {
      final stats = ComputeStats.from(
        [
          _turn('2026-08-13', output: 100),
          _turn('2026-08-13', model: 'claude-opus-5', output: 100),
        ],
        StatsRange.all,
        now: hoy,
      );

      expect(stats.models.length, 1);
    });
  });
}
