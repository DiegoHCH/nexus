import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/history/domain/entities/conversation_summary.dart';
import 'package:nexus/features/history/domain/usecases/el_parte_de_ayer.dart';

/// El parte del día anterior, para el daily.
///
/// Lo redacta Claude; aquí se decide **qué día se cuenta y qué se le pone
/// delante**, que es donde está todo el criterio: un parte se estropea contando
/// el día equivocado, o dejando que quien lo escribe rellene los huecos.

void main() {
  ConversationSummary charla(
    DateTime cuando, {
    String carpeta = '/repos/app',
    String titulo = 'algo',
    int turnos = 3,
  }) => ConversationSummary(
    id: '$cuando$titulo',
    folderPath: carpeta,
    startedAt: cuando,
    title: titulo,
    turns: turnos,
  );

  group('qué día se cuenta', () {
    // El caso que decide el diseño: el lunes, «ayer» es domingo. Contar ayer a
    // secas dejaría el parte vacío justo el día que más se usa.
    test('el lunes se cuenta el viernes, no el domingo', () {
      final lunes = DateTime(2026, 8, 31, 9);
      final viernes = DateTime(2026, 8, 28, 17);

      expect(
        ElParteDeAyer.elDia([charla(viernes)], hoy: lunes),
        DateTime(2026, 8, 28),
      );
    });

    test('el último con actividad, aunque sea de hace una semana', () {
      final hoy = DateTime(2026, 8, 31, 9);
      expect(
        ElParteDeAyer.elDia([
          charla(DateTime(2026, 8, 20, 10)),
          charla(DateTime(2026, 8, 24, 16)),
        ], hoy: hoy),
        DateTime(2026, 8, 24),
      );
    });

    // Lo de esta mañana todavía se está haciendo: el parte es de lo cerrado.
    test('hoy no cuenta, aunque haya trabajo', () {
      final hoy = DateTime(2026, 8, 31, 15);
      expect(ElParteDeAyer.elDia([charla(hoy)], hoy: hoy), isNull);
    });

    test('sin historial no hay día', () {
      expect(ElParteDeAyer.elDia(const [], hoy: DateTime(2026, 8, 31)), isNull);
    });
  });

  group('lo que se le pone delante a Claude', () {
    final hoy = DateTime(2026, 8, 31, 9);
    final ayer = DateTime(2026, 8, 30, 10);

    test('el material va agrupado por proyecto, con hora y turnos', () {
      final instruccion = ElParteDeAyer.instruccion([
        charla(ayer, carpeta: '/repos/app', titulo: 'el visor de cambios'),
        charla(
          ayer.add(const Duration(hours: 4)),
          carpeta: '/repos/api',
          titulo: 'el endpoint de pagos',
          turnos: 1,
        ),
      ], hoy: hoy)!;

      expect(instruccion, contains('app (/repos/app)'));
      expect(instruccion, contains('api (/repos/api)'));
      expect(instruccion, contains('«el visor de cambios»'));
      expect(instruccion, contains('10:00'));
      expect(instruccion, contains('1 turno'), reason: 'uno, no «1 turnos»');
      expect(instruccion, contains('3 turnos'));
    });

    test('solo entra lo de ese día', () {
      final instruccion = ElParteDeAyer.instruccion([
        charla(ayer, titulo: 'lo de ayer'),
        charla(DateTime(2026, 8, 25), titulo: 'lo de la semana pasada'),
      ], hoy: hoy)!;

      expect(instruccion, contains('lo de ayer'));
      expect(instruccion, isNot(contains('lo de la semana pasada')));
    });

    // Lo más importante del texto, y por lo que existe este caso de uso: un
    // parte que rellena huecos es peor que no tener parte, porque se lee en voz
    // alta delante del equipo.
    test('se le prohíbe rellenar, dos veces y sin rodeos', () {
      final instruccion = ElParteDeAyer.instruccion([charla(ayer)], hoy: hoy)!;

      expect(instruccion, contains('no te inventes'));
      expect(instruccion, contains('No añadas nada que no puedas sostener'));
    });

    test('pide el formato del daily, y que salga listo para Slack', () {
      final instruccion = ElParteDeAyer.instruccion([charla(ayer)], hoy: hoy)!;

      expect(instruccion, contains('Qué hice'));
      expect(instruccion, contains('Qué sigue'));
      expect(instruccion, contains('Bloqueos'));
      expect(instruccion, contains('sin preámbulo'));
    });

    // Sin nada que contar no se le pregunta: pedirle el parte de un día vacío
    // es pedirle que se lo invente.
    test('un día sin nada no produce instrucción', () {
      expect(ElParteDeAyer.instruccion(const [], hoy: hoy), isNull);
      expect(
        ElParteDeAyer.instruccion([charla(hoy)], hoy: hoy),
        isNull,
        reason: 'lo de hoy no cuenta, así que no queda material',
      );
    });
  });
}
