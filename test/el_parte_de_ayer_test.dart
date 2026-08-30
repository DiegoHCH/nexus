import 'dart:io';

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

  group('de qué proyecto se cuenta', () {
    final hoy = DateTime(2026, 8, 31, 9);
    final ayer = DateTime(2026, 8, 30, 10);

    // El fallo que esto evita no se ve hasta que ya pasó: el parte va al Slack
    // de un equipo, y sin filtro lo que hiciste en tus proyectos personales
    // acabaría contado en ese daily.
    test('lo de otros proyectos no entra', () {
      final instruccion = ElParteDeAyer.instruccion(
        [
          charla(
            ayer,
            carpeta: '/w/front_mobile_b2c',
            titulo: 'lo del trabajo',
          ),
          charla(ayer, carpeta: '/personal/mio', titulo: 'lo mío'),
        ],
        hoy: hoy,
        soloDelProyecto: '/w/front_mobile_b2c',
      )!;

      expect(instruccion, contains('lo del trabajo'));
      expect(instruccion, isNot(contains('lo mío')));
    });

    // Y tampoco cuenta el día: si el único trabajo de ayer fue personal, el
    // parte del proyecto no es «vacío», es que no hay parte.
    test('el día se elige mirando solo ese proyecto', () {
      final soloPersonal = [
        charla(ayer, carpeta: '/personal/mio'),
        charla(DateTime(2026, 8, 25), carpeta: '/w/front_mobile_b2c'),
      ];

      expect(
        ElParteDeAyer.elDia(
          soloPersonal,
          hoy: hoy,
          soloDelProyecto: '/w/front_mobile_b2c',
        ),
        DateTime(2026, 8, 25),
        reason: 'el último día de ESE proyecto, no el último de la máquina',
      );
    });

    test(
      'sin proyecto elegido entra todo, que es el comportamiento de antes',
      () {
        final instruccion = ElParteDeAyer.instruccion([
          charla(ayer, carpeta: '/w/uno', titulo: 'de uno'),
          charla(ayer, carpeta: '/personal/dos', titulo: 'de dos'),
        ], hoy: hoy)!;

        expect(instruccion, contains('de uno'));
        expect(instruccion, contains('de dos'));
      },
    );
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

  // El fallo que costó tres intentos encontrar, y que ninguna prueba veía: el
  // mensaje se marcaba bien, el botón existía, y la fila de botones **no se
  // dibujaba** porque su condición se escribió cuando solo había cambios y
  // documento. Un parte no toca archivos —se pide sin escritura— así que caía
  // siempre en el lado de «este turno no dejó nada».
  test('la fila de botones cuenta el parte como algo que el turno dejó', () {
    final fuente = File(
      'lib/features/assistant/presentation/widgets/chat_panel.dart',
    ).readAsStringSync();

    final condicion = fuente.substring(
      fuente.indexOf('if (message.cambios != null'),
      fuente.indexOf('_LoQueDejo(message: message)'),
    );
    expect(
      condicion,
      contains('message.esElParte'),
      reason:
          'sin esto el botón de mandar a Slack existe y no se dibuja nunca, '
          'porque un parte no deja cambios ni documentos',
    );
  });

  group('pedirlo por escrito', () {
    test('las formas de pedirlo se reconocen, escritas con prisa', () {
      for (final frase in [
        'dame el daily',
        'Dame el daily',
        '  DAME EL DAILY  ',
        'el daily',
        'daily',
        'dame el parte',
        'el parte del día',
        'standup',
        '¿Qué hice ayer?',
        'que hice ayer',
        'Cuéntame lo de ayer.',
      ]) {
        expect(
          ElParteDeAyer.loEstanPidiendo(frase),
          isTrue,
          reason: '«$frase»',
        );
      }
    });

    // La mitad que importa. Reconocer de menos cuesta escribir la frase buena;
    // reconocer de más secuestra un encargo de verdad y lo convierte en un
    // resumen de ayer, que además tarda un minuto en salir.
    test('un encargo que solo menciona el daily sigue siendo un encargo', () {
      for (final frase in [
        'mira por qué falla el job del daily',
        'arregla el parte que sale mal en producción',
        'dame el daily y luego borra la rama',
        'qué hice ayer en el repo de la empresa, con detalle',
        'genera un standup automático cada mañana',
        'escribe un test para el parte',
      ]) {
        expect(
          ElParteDeAyer.loEstanPidiendo(frase),
          isFalse,
          reason: '«$frase»',
        );
      }
    });
  });
}
