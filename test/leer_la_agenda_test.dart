import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/agenda/data/datasources/agenda_data_source.dart';

/// Lo que contesta Claude cuando se le pide el calendario.
///
/// Se le pide JSON pelado y **a veces no llega así**: dentro de un bloque de
/// código, con una frase delante. Negarse por el envoltorio dejaría sin avisos
/// un día entero por una coletilla, así que aquí se prueba la tolerancia.
void main() {
  const json =
      '[{"id":"e1","titulo":"Daily","comienza":"2026-08-31T10:00:00Z",'
      '"invitados":3}]';

  test('el JSON pelado, que es lo que se pide', () {
    final leidas = AgendaDataSource.leer(json);

    expect(leidas.single.titulo, 'Daily');
    expect(leidas.single.invitados, 3);
  });

  test('dentro de un bloque de código también', () {
    expect(AgendaDataSource.leer('```json\n$json\n```').single.titulo, 'Daily');
  });

  test('y con una frase delante', () {
    expect(
      AgendaDataSource.leer('Claro, aquí tienes tus eventos:\n$json').single.id,
      'e1',
    );
  });

  test('un día sin nada no es un fallo', () {
    expect(AgendaDataSource.leer('[]'), isEmpty);
    expect(AgendaDataSource.leer('No tienes eventos hoy.'), isEmpty);
  });

  // Un evento a medias se salta y los demás siguen: una entrada rara no puede
  // dejarte sin los avisos del resto del día.
  test('lo ilegible se salta, el resto se queda', () {
    final leidas = AgendaDataSource.leer(
      '[{"titulo":"sin id"},'
      '{"id":"e2","titulo":"Refinamiento","comienza":"2026-08-31T11:00:00Z","invitados":2}]',
    );

    expect(leidas.map((r) => r.id), ['e2']);
  });

  // 🔴 **La forma que devuelve el conector de verdad**, medida contra un
  // `claude -p` real el 31-08-2026. Los datos son inventados —el calendario del
  // que salió es de trabajo y este repo es público— pero la forma es la que
  // llegó, y es la que el resto del archivo no probaba: los ids del calendario
  // son compuestos (`<id>_<fechaZ>`), la hora viene con desplazamiento y no en
  // `Z`, y los invitados pueden ser tres cifras. Si el conector cambia de forma,
  // es aquí donde tiene que romperse.
  test('la forma real del conector, con ids compuestos y hora con huso', () {
    final leidas = AgendaDataSource.leer(
      '[{"id": "5f3a91c2d4e6b8a0f1c3d5e7b9a1c3d5_20260831T140000Z", '
      '"titulo": "Daily", '
      '"comienza": "2026-08-31T09:00:00-05:00", "invitados": 9}, '
      '{"id": "a1b2c3d4e5f60718293a4b5c6d7e8f90", '
      '"titulo": "Todos a una", '
      '"comienza": "2026-08-31T15:00:00-05:00", "invitados": 113}]',
    );

    expect(leidas.length, 2);
    expect(leidas.map((r) => r.titulo), ['Daily', 'Todos a una']);
    // Las dos son reuniones de verdad, no bloques propios.
    expect(leidas.every((r) => r.esUnaReunion), isTrue);
    // El id compuesto se conserva entero: es lo que separa dos apariciones de la
    // misma reunión repetida, y recortarlo haría que la de mañana llegue ya
    // avisada.
    expect(leidas.first.id, endsWith('_20260831T140000Z'));
    // La hora se guarda en local, que es contra lo que compara el reloj del
    // vigilante: comparar un instante con desplazamiento contra `DateTime.now()`
    // es justo el error que adelantaría o atrasaría el aviso cinco horas.
    expect(leidas.first.comienza.isUtc, isFalse);
    expect(
      leidas.first.comienza,
      DateTime.parse('2026-08-31T09:00:00-05:00').toLocal(),
    );
  });

  // 🔴 No se pide la descripción, y eso es a propósito: lo que no se pide no
  // puede acabar sonando por el altavoz con alguien delante.
  test('la instrucción no pide la descripción del evento', () {
    final instruccion = AgendaDataSource.instruccionPara(DateTime(2026, 8, 31));

    expect(instruccion, contains('2026-08-31'));
    expect(instruccion, contains('invitados'));
    expect(instruccion.toLowerCase(), isNot(contains('descripci')));
  });
}
