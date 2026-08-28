import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/diagnostico/registro_de_la_app.dart';

/// ADD-01. La app se distribuye firmada, se actualiza sola y no tenía forma de
/// contar que se rompió: todo el diagnóstico era `debugPrint`, y en release eso
/// no llega a ninguna parte — medido en este mismo repo cuando nació el registro
/// del canal.

void main() {
  late Directory casa;

  setUp(() {
    casa = Directory.systemTemp.createTempSync('nexus_registro');
  });
  tearDown(() => casa.deleteSync(recursive: true));

  RegistroDeLaApp registro({int tope = 512 * 1024}) =>
      RegistroDeLaApp(carpeta: casa, tope: tope);

  File archivo() => File('${casa.path}/nexus.log');

  test('lo anotado queda escrito, con su hora delante', () async {
    await registro().anotar('claude · arranca el encargo');

    final texto = archivo().readAsStringSync();
    expect(texto, contains('claude · arranca el encargo'));
    // La hora es la mitad del valor: «falló» sin cuándo no se cruza con nada.
    expect(texto, matches(RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}')));
  });

  test('se añade, no se reescribe', () async {
    final r = registro();
    await r.anotar('la primera');
    await r.anotar('la segunda');

    final lineas = archivo().readAsLinesSync();
    expect(lineas, hasLength(2));
    expect(lineas.first, contains('la primera'));
    expect(lineas.last, contains('la segunda'));
  });

  // Recortar por dentro sería editarlo, y entonces deja de ser un registro. Es
  // la misma regla que el del canal.
  test('al pasarse rota renombrando, y lo anterior queda entero', () async {
    final r = registro(tope: 200);
    for (var i = 0; i < 12; i++) {
      await r.anotar('linea de relleno numero $i con su texto');
    }

    final anterior = File('${archivo().path}.anterior');
    expect(anterior.existsSync(), isTrue, reason: 'tiene que haber rotado');
    expect(anterior.readAsStringSync(), isNotEmpty);
    // Y lo nuevo sigue escribiéndose, que es lo que la rotación no puede romper.
    expect(archivo().readAsStringSync(), contains('numero 11'));

    // **Una sola generación anterior**, y por eso lo de `numero 0` ya no está:
    // con doce líneas y este tope rota dos veces, y la segunda se lleva por
    // delante lo que guardó la primera. Es lo que acota el disco — un registro
    // que guarda todas sus vidas crece igual que uno sin rotación.
    final generaciones = casa
        .listSync()
        .whereType<File>()
        .map((f) => f.path.split('/').last)
        .toList();
    expect(generaciones, unorderedEquals(['nexus.log', 'nexus.log.anterior']));
  });

  test('una carpeta imposible no rompe a quien anota', () async {
    final imposible = RegistroDeLaApp(
      carpeta: Directory('/dev/null/no-se-puede'),
    );

    // Sin excepción: un fallo al registrar no puede tumbar lo que registraba.
    await expectLater(imposible.anotar('da igual'), completes);
  });

  test('dice dónde vive, para poder abrirlo', () async {
    expect(await registro().ruta, '${casa.path}/nexus.log');
  });

  // Lo que hace que esto valga desde el primer día en vez de dentro de seis
  // meses: los 41 `debugPrint` que ya existen no se tocaron.
  group('el enganche de debugPrint', () {
    late DebugPrintCallback original;

    setUp(() => original = debugPrint);
    tearDown(() => debugPrint = original);

    test('lo que se imprime también se escribe', () async {
      final r = registro();
      var loQueSeVioEnConsola = '';
      debugPrint = (mensaje, {wrapWidth}) => loQueSeVioEnConsola = '$mensaje';

      // El mismo envoltorio que monta `main`, en pequeño.
      final antes = debugPrint;
      debugPrint = (mensaje, {wrapWidth}) {
        antes(mensaje, wrapWidth: wrapWidth);
        if (mensaje != null) r.anotar(mensaje);
      };

      debugPrint('nexus · algo que contar');
      await r.anotar('');

      // Sigue yendo a la consola: eso es para lo que sirve en `flutter run`, y
      // envolver no puede quitarlo.
      expect(loQueSeVioEnConsola, 'nexus · algo que contar');
      expect(archivo().readAsStringSync(), contains('nexus · algo que contar'));
    });
  });

  // El enganche vive en `main` y no en un provider, y tiene que ser lo primero:
  // engancharlo después de arrancar deja fuera los fallos del arranque, que son
  // los que menos se pueden reproducir luego.
  group('y está enganchado de verdad', () {
    final main = File('lib/main.dart').readAsStringSync();

    test('main lo engancha antes de nada', () {
      final engancha = main.indexOf('engancharElRegistro(registro)');
      final arranca = main.indexOf('runApp(');
      expect(engancha, isNot(-1));
      expect(engancha, lessThan(arranca));
    });

    test('y los errores del framework y los sueltos también caen ahí', () {
      expect(main, contains('FlutterError.onError'));
      expect(main, contains('PlatformDispatcher.instance.onError'));
    });

    test('Ajustes enseña el mismo que escribe, no otro', () {
      expect(
        main,
        contains('registroDeLaAppProvider.overrideWithValue(registro)'),
        reason:
            'sin el override, Ajustes construiria el suyo y ensenaria la ruta '
            'de un archivo en el que no escribe nadie',
      );
    });
  });
}
