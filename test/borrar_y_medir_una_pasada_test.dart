import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/e2e/data/datasources/e2e_data_source.dart';

/// Borrar y medir una pasada, que no siempre es una carpeta.
///
/// **Estas dos existen por un fallo que no daba ningún error.** Las pasadas que
/// lanza Nexus son un registro `.json` suelto, y las dos funciones trataban
/// cualquier ruta como una carpeta. `Directory(archivo).existsSync()` da `false`,
/// así que borrar salía por «no hay nada que borrar» devolviendo `null` —éxito— y
/// medir devolvía `0`. Nada se quejaba en ningún sitio: el borrado no hacía nada y
/// la fila volvía al refrescar.
void main() {
  const ds = E2eDataSource();

  late Directory casa;
  setUp(() => casa = Directory.systemTemp.createTempSync('pasadas'));
  tearDown(() => casa.deleteSync(recursive: true));

  test('borra el registro de una pasada nuestra, que es un archivo', () async {
    final registro = File('${casa.path}/login 2026-08-26 09h3507.json')
      ..writeAsStringSync('{"flow":"login"}');

    expect(await ds.borrar(registro.path), isNull);
    expect(registro.existsSync(), isFalse, reason: 'no se borró el registro');
  });

  test('se lleva también la página que se le escribió', () async {
    // La página es derivada del registro: sin él no lleva a ninguna parte, así
    // que quedaría ocupando sitio sin que nada la enseñe.
    final registro = File('${casa.path}/login 2026-08-26 09h3507.json')
      ..writeAsStringSync('{"flow":"login"}');
    final pagina = File(E2eDataSource.paginaDe(registro.path))
      ..writeAsStringSync('<html></html>');

    await ds.borrar(registro.path);

    expect(pagina.existsSync(), isFalse);
  });

  test('la página vive al lado del registro y con su nombre', () {
    // El nombre del archivo es el título de la ventana. Antes se recomponía
    // buscando un `T09-35` del formato anterior de sello de tiempo, y al cambiar
    // los nombres el patrón dejó de casar: la página salía con el flow repetido.
    expect(
      E2eDataSource.paginaDe('/t/login 2026-08-26 09h3507.json'),
      '/t/login 2026-08-26 09h3507.html',
    );
  });

  test('borra la carpeta de una pasada de Maestro, con lo que tenga dentro', () async {
    final carpeta = Directory('${casa.path}/login')..createSync();
    File('${carpeta.path}/commands.json').writeAsStringSync('[]');
    Directory('${carpeta.path}/takeScreenshot').createSync();

    expect(await ds.borrar(carpeta.path), isNull);
    expect(carpeta.existsSync(), isFalse);
  });

  test('lo que no está no da error: ya no está, que es lo que se pedía', () async {
    expect(await ds.borrar('${casa.path}/no_existe.json'), isNull);
  });

  test('mide un registro y su página, no cero', () async {
    final registro = File('${casa.path}/login 2026-08-26 09h3507.json')
      ..writeAsStringSync('12345');
    File(E2eDataSource.paginaDe(registro.path)).writeAsStringSync('123');

    expect(await ds.bytesDe(registro.path), 8);
  });

  test('mide una carpeta entera, bajando por dentro', () async {
    final carpeta = Directory('${casa.path}/login')..createSync();
    File('${carpeta.path}/commands.json').writeAsStringSync('1234');
    Directory('${carpeta.path}/takeScreenshot').createSync();
    File('${carpeta.path}/takeScreenshot/uno.png').writeAsStringSync('123456');

    expect(await ds.bytesDe(carpeta.path), 10);
  });

  test('lo que no existe mide cero', () async {
    expect(await ds.bytesDe('${casa.path}/no_existe'), 0);
  });
}
