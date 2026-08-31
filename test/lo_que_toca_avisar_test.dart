import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/agenda/domain/entities/reunion.dart';
import 'package:nexus/features/agenda/domain/usecases/lo_que_toca_avisar.dart';
import 'package:nexus/features/agenda/domain/usecases/la_jornada.dart';

/// Las reglas del aviso, que son lo que se rompe en silencio: un aviso que no
/// suena no deja rastro, y uno que suena de más enseña a ignorarlo.
void main() {
  final ahora = DateTime(2026, 8, 31, 9, 55);

  Reunion r(
    String id,
    int minutosDesdeAhora, {
    int invitados = 2,
    String? titulo,
  }) => Reunion(
    id: id,
    titulo: titulo ?? 'Refinamiento $id',
    comienza: ahora.add(Duration(minutes: minutosDesdeAhora)),
    invitados: invitados,
  );

  List<Reunion> tocan(
    List<Reunion> agenda, {
    Set<String> yaAvisadas = const {},
    Duration antes = const Duration(minutes: 5),
  }) => LoQueTocaAvisar.ahora(
    agenda,
    cuando: ahora,
    antes: antes,
    yaAvisadas: yaAvisadas,
  );

  group('qué entra en la ventana', () {
    test('lo que empieza dentro de los cinco minutos', () {
      expect(tocan([r('a', 5)]).map((x) => x.id), ['a']);
      expect(tocan([r('a', 3)]).map((x) => x.id), ['a']);
    });

    test('lo que está más lejos, todavía no', () {
      expect(tocan([r('a', 6)]), isEmpty);
    });

    // 🔴 La ventana se cierra al empezar. Si no, abrir la app a las seis de la
    // tarde soltaría de golpe los seis avisos que se perdió por estar cerrada.
    test('lo que ya empezó no se avisa', () {
      expect(tocan([r('a', -1)]), isEmpty);
      expect(tocan([r('a', -120)]), isEmpty);
    });
  });

  group('qué cuenta como reunión', () {
    // Un calendario lleva «comer», «foco» y cumpleaños. Avisar de eso es ruido,
    // y el ruido enseña a ignorar el aviso — que es peor que no tenerlo.
    test('sin invitados no suena', () {
      expect(tocan([r('comer', 3, invitados: 0, titulo: 'Comer')]), isEmpty);
    });

    test('con al menos uno, sí', () {
      expect(tocan([r('a', 3, invitados: 1)]).map((x) => x.id), ['a']);
    });
  });

  test('no se avisa dos veces de lo mismo', () {
    expect(tocan([r('a', 3)], yaAvisadas: {'a'}), isEmpty);
  });

  test('si coinciden dos, primero la que empieza antes', () {
    expect(tocan([r('tarde', 5), r('pronto', 2)]).map((x) => x.id), [
      'pronto',
      'tarde',
    ]);
  });

  group('cómo se dice', () {
    String decir(Reunion reunion) => LoQueTocaAvisar.comoSeDice(
      reunion,
      cuando: ahora,
      plantilla: (titulo, minutos) => '$titulo, en $minutos minutos.',
      ahoraMismo: (titulo) => '$titulo, ahora.',
    );

    test('el título y cuánto falta', () {
      expect(
        decir(r('a', 5, titulo: 'Refinamiento SU-601')),
        'Refinamiento SU-601, en 5 minutos.',
      );
    });

    // 🔴 Hacia arriba. A falta de cuatro minutos y medio, «en cinco» es verdad
    // y «en cuatro» te haría salir tarde.
    test('los minutos se redondean hacia arriba', () {
      final casi = Reunion(
        id: 'a',
        titulo: 'Daily',
        comienza: ahora.add(const Duration(minutes: 4, seconds: 30)),
        invitados: 2,
      );

      expect(decir(casi), 'Daily, en 5 minutos.');
    });

    test('y si ya es la hora, se dice así', () {
      final justo = Reunion(
        id: 'a',
        titulo: 'Daily',
        comienza: ahora,
        invitados: 2,
      );

      expect(decir(justo), 'Daily, ahora.');
    });
  });

  // Las reglas de jornada: cuántas veces se le pregunta a la cuenta, y hasta
  // cuándo se guarda lo que contestó. Una regla mal puesta aquí no se ve — se
  // traduce en consultas que nadie pidió, o en avisos que no llegan.
  group('la jornada', () {
    // 2026-08-31 es lunes; el 5 de septiembre, sábado.
    final lunes = DateTime(2026, 8, 31, 9);
    final sabado = DateTime(2026, 9, 5, 9);
    final domingo = DateTime(2026, 9, 6, 9);

    test('de lunes a viernes se lee; el fin de semana no', () {
      expect(LaJornada.anclaPara(lunes), isNotNull);
      expect(LaJornada.anclaPara(DateTime(2026, 9, 4, 9)), isNotNull);
      expect(LaJornada.anclaPara(sabado), isNull);
      expect(LaJornada.anclaPara(domingo), isNull);
    });

    test('antes de las ocho, el ancla es el arranque del día', () {
      expect(
        LaJornada.anclaPara(DateTime(2026, 8, 31, 7, 30)),
        DateTime(2026, 8, 31),
      );
    });

    test('a partir de las ocho, el ancla son las ocho', () {
      expect(
        LaJornada.anclaPara(DateTime(2026, 8, 31, 8)),
        DateTime(2026, 8, 31, 8),
      );
      expect(
        LaJornada.anclaPara(DateTime(2026, 8, 31, 17, 45)),
        DateTime(2026, 8, 31, 8),
      );
    });

    // Que sea el mismo valor toda la tarde es lo que evita releer.
    test('toda la tarde comparte ancla, así que no se relee', () {
      expect(
        LaJornada.anclaPara(DateTime(2026, 8, 31, 9)),
        LaJornada.anclaPara(DateTime(2026, 8, 31, 17)),
      );
    });

    // 🔴 A las seis se acaba. Lo que quedara en memoria sería la lista de un
    // día que terminó: sirve para contestar «hoy no tienes reuniones» cuando
    // sí las tuviste, y para nada más.
    test('a las seis se cierra, y ya no se lee', () {
      expect(LaJornada.dentro(DateTime(2026, 8, 31, 17, 59)), isTrue);
      expect(LaJornada.dentro(DateTime(2026, 8, 31, 18)), isFalse);
      expect(LaJornada.anclaPara(DateTime(2026, 8, 31, 18, 30)), isNull);
    });

    test('y un sábado está fuera a cualquier hora', () {
      expect(LaJornada.dentro(DateTime(2026, 9, 5, 10)), isFalse);
    });
  });

  group('lo que llega del calendario', () {
    test('una reunión bien formada se lee', () {
      final leida = Reunion.deJson({
        'id': 'evt_1',
        'titulo': '  Refinamiento SU-601  ',
        'comienza': '2026-08-31T10:00:00Z',
        'invitados': 3,
      });

      expect(leida!.titulo, 'Refinamiento SU-601');
      expect(leida.invitados, 3);
    });

    // Lo que venga a medias se salta: una entrada ilegible no puede tumbar la
    // lista entera y dejarte sin ningún aviso del día.
    test('lo que viene a medias se descarta, no revienta', () {
      expect(Reunion.deJson({'titulo': 'sin id ni hora'}), isNull);
      expect(
        Reunion.deJson({'id': 'x', 'titulo': 'y', 'comienza': 'ayer'}),
        isNull,
      );
      expect(Reunion.deJson('esto no es un evento'), isNull);
    });
  });
}
