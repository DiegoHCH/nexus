import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/agenda/domain/entities/reunion.dart';
import 'package:nexus/features/agenda/domain/usecases/la_lectura_que_toca.dart';
import 'package:nexus/features/agenda/domain/usecases/lo_que_se_contesta_de_la_agenda.dart';
import 'package:nexus/features/agenda/domain/usecases/lo_que_toca_avisar.dart';

/// Lo que decide la agenda, ahora que decide en `domain`.
///
/// Vivía dentro de `ElVigilanteDeLaAgenda` —527 líneas al 9,3 %— y de ahí no lo
/// miraba nada: el suelo de cobertura del CI mira `**/domain/**`, así que estas
/// reglas se libraban **por dónde estaba el archivo y no por lo que hacen**.
///
/// Y su error no se ve: una lectura de más gasta cupo de la suscripción, una de
/// menos deja la mañana sin avisos, y un aviso que no suena no deja rastro.
void main() {
  Reunion reunion(String id, int hora, {int minuto = 0, int invitados = 2}) =>
      Reunion(
        id: id,
        titulo: id,
        comienza: DateTime(2026, 9, 3, hora, minuto),
        invitados: invitados,
      );

  // Jueves 3 de septiembre de 2026.
  DateTime alas(int hora, [int minuto = 0]) =>
      DateTime(2026, 9, 3, hora, minuto);

  group('qué se contesta a «¿qué tengo hoy?»', () {
    String contestar(List<Reunion> agenda, DateTime cuando) =>
        LoQueSeContestaDeLaAgenda.respuesta(
          agenda,
          cuando: cuando,
          fueraDeJornada: 'la jornada ya acabó',
          vacia: 'hoy no tienes reuniones',
          cabecera: (n) => 'hoy tienes $n',
        );

    test('las lista en orden de reloj, con la hora delante', () {
      final dicho = contestar([
        reunion('la tarde', 16, minuto: 30),
        reunion('la mañana', 9, minuto: 5),
      ], alas(8));

      expect(dicho, 'hoy tienes 2\n- 09:05 · la mañana\n- 16:30 · la tarde');
    });

    test('la hora lleva el cero delante', () {
      expect(LoQueSeContestaDeLaAgenda.laHora(alas(9, 5)), '09:05');
      expect(LoQueSeContestaDeLaAgenda.laHora(alas(14, 0)), '14:00');
    });

    // Un calendario lleva «comer», «foco» y cumpleaños. Contarlos como agenda es
    // el mismo ruido que ya se decidió no avisar.
    test('los bloques sin invitados no son agenda', () {
      final dicho = contestar([
        reunion('comer', 13, invitados: 0),
        reunion('foco', 15, invitados: 0),
      ], alas(9));

      expect(dicho, 'hoy no tienes reuniones');
    });

    // 🔴 La distinción que importa: fuera de jornada la agenda está **borrada**,
    // así que decir «no tienes reuniones» sería mentir sobre un día que sí las
    // tuvo. Las dos salidas se ven iguales desde fuera y no lo son.
    test('fuera de jornada no dice que no hay: dice que ya no la sabe', () {
      expect(contestar(const [], alas(19)), 'la jornada ya acabó');
      expect(contestar([reunion('una', 10)], alas(19)), 'la jornada ya acabó');
    });

    test('el sábado tampoco es jornada, aunque sean las diez', () {
      // Sábado 5 de septiembre de 2026.
      final sabado = DateTime(2026, 9, 5, 10);

      expect(contestar(const [], sabado), 'la jornada ya acabó');
    });

    test('dentro de jornada y sin nada, sí se puede decir que no hay', () {
      expect(contestar(const [], alas(9)), 'hoy no tienes reuniones');
    });
  });

  group('cuándo se sale a leer el calendario', () {
    ({QueHacerConLaAgenda que, DateTime? ancla}) toca({
      required DateTime ahora,
      DateTime? leidoDesde,
      String? carpeta = '/Users/alguien/repo',
      bool emparejada = true,
    }) => LaLecturaQueToca.para(
      ahora: ahora,
      leidoDesde: leidoDesde,
      carpeta: carpeta,
      carpetaEmparejada: emparejada,
    );

    test('al arrancar temprano se lee, y el ancla es el principio del día', () {
      final r = toca(ahora: alas(7, 30));

      expect(r.que, QueHacerConLaAgenda.leerla);
      expect(r.ancla, DateTime(2026, 9, 3));
    });

    test('pasadas las ocho el ancla es otra, así que se relee una vez', () {
      final r = toca(ahora: alas(8, 1), leidoDesde: DateTime(2026, 9, 3));

      expect(
        r.que,
        QueHacerConLaAgenda.leerla,
        reason: 'leer solo al arrancar deja fuera lo que se programó anoche',
      );
      expect(r.ancla, DateTime(2026, 9, 3, 8));
    });

    test('con el ancla ya leída no se vuelve a consultar', () {
      final r = toca(ahora: alas(11), leidoDesde: DateTime(2026, 9, 3, 8));

      expect(r.que, QueHacerConLaAgenda.dejarlaComoEsta);
    });

    test('fuera de jornada se olvida, no se conserva', () {
      expect(toca(ahora: alas(18, 1)).que, QueHacerConLaAgenda.olvidarla);
      expect(
        toca(ahora: DateTime(2026, 9, 6, 10)).que,
        QueHacerConLaAgenda.olvidarla,
        reason: 'domingo',
      );
    });

    test('sin carpeta configurada no se consulta ni se toca lo que hay', () {
      expect(
        toca(ahora: alas(9), carpeta: null).que,
        QueHacerConLaAgenda.dejarlaComoEsta,
      );
      expect(
        toca(ahora: alas(9), carpeta: '').que,
        QueHacerConLaAgenda.dejarlaComoEsta,
      );
    });

    // 🔴 Esta es la que no se puede confundir con `dejarlaComoEsta`: el
    // vigilante le gana la carrera al workspace al arrancar, y leer ahí sacaría
    // la agenda de la cuenta por defecto en vez de la de la carpeta. Espera al
    // siguiente tic **sin marcar el ancla**, así que treinta segundos después
    // sí lee.
    test('con la carpeta elegida pero aún sin cargar, se espera', () {
      final r = toca(ahora: alas(9), emparejada: false);

      expect(r.que, QueHacerConLaAgenda.esperarALaCarpeta);
      expect(
        toca(ahora: alas(9, 0), emparejada: true).que,
        QueHacerConLaAgenda.leerla,
        reason: 'y en cuanto el workspace la trae, se lee',
      );
    });
  });

  group('lo que se recuerda haber avisado', () {
    test('lo de una agenda que ya no existe se suelta', () {
      final vivos = LoQueTocaAvisar.loQueSigueVivo(
        {'a', 'b', 'c'},
        [reunion('b', 10)],
      );

      expect(vivos, {'b'});
    });

    test('sin agenda no queda nada', () {
      expect(LoQueTocaAvisar.loQueSigueVivo({'a'}, const []), isEmpty);
    });

    test('no inventa: solo quita', () {
      final vivos = LoQueTocaAvisar.loQueSigueVivo(
        {'a'},
        [reunion('a', 10), reunion('b', 11)],
      );

      expect(vivos, {
        'a',
      }, reason: 'una reunión no avisada no puede acabar marcada como avisada');
    });
  });
}
