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

  // 🔴 No se pide la descripción, y eso es a propósito: lo que no se pide no
  // puede acabar sonando por el altavoz con alguien delante.
  test('la instrucción no pide la descripción del evento', () {
    final instruccion = AgendaDataSource.instruccionPara(DateTime(2026, 8, 31));

    expect(instruccion, contains('2026-08-31'));
    expect(instruccion, contains('invitados'));
    expect(instruccion.toLowerCase(), isNot(contains('descripci')));
  });
}
