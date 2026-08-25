import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/emulators/domain/entities/emulador.dart';
import 'package:nexus/features/emulators/domain/usecases/comando_de_emuladores.dart';

/// Los emuladores de la máquina: leerlos, arrancarlos y saber si están arriba.
///
/// Las entradas de estas pruebas son **salidas reales**, copiadas de esta máquina
/// el 25 ago 2026, no inventadas. Es la diferencia entre probar el parser y
/// probar una idea del parser: la tabla trae un recuento arriba, una cabecera, y
/// dos consejos al final que también llevan comillas y guiones.
void main() {
  // `flutter emulators` tal cual, con todo el ruido alrededor.
  const tablaReal = '''
3 available emulators:

Id                    • Name                  • Manufacturer • Platform

apple_ios_simulator   • iOS Simulator         • Apple        • ios
Medium_Phone_API_36.1 • Medium Phone API 36.1 • Generic      • android
Small_Phone           • Small Phone           • Generic      • android

To run an emulator, run 'flutter emulators --launch <emulator id>'.
To create a new emulator, run 'flutter emulators --create [--name xyz]'.
''';

  group('leer la tabla', () {
    test('salen los tres, y ni la cabecera ni los consejos', () {
      final leidos = ComandoDeEmuladores.leerTabla(tablaReal);

      expect(leidos.length, 3);
      expect(leidos.map((e) => e.id), [
        'apple_ios_simulator',
        'Medium_Phone_API_36.1',
        'Small_Phone',
      ]);
      // La cabecera trae cuatro columnas igual que una fila buena: si se
      // descartara por el número de celdas, entraría como un emulador llamado
      // «Id».
      expect(leidos.map((e) => e.id), isNot(contains('Id')));
    });

    test('el nombre legible se distingue del id', () {
      final medium = ComandoDeEmuladores.leerTabla(
        tablaReal,
      ).firstWhere((e) => e.id == 'Medium_Phone_API_36.1');

      // Los dos hacen falta: el id es lo que entiende `--launch` y el nombre es
      // lo que puede contestar `adb emu avd name`.
      expect(medium.nombre, 'Medium Phone API 36.1');
      expect(medium.plataforma, PlataformaEmulador.android);
    });

    test('una plataforma desconocida se descarta, no se asume Android', () {
      // Ofrecer un botón que no sabemos cerrar es peor que no ofrecerlo.
      final leidos = ComandoDeEmuladores.leerTabla(
        'raro_1 • Raro • Nadie • fuchsia',
      );
      expect(leidos, isEmpty);
    });

    test('una tabla vacía no revienta', () {
      expect(ComandoDeEmuladores.leerTabla('No emulators available.'), isEmpty);
      expect(ComandoDeEmuladores.leerTabla(''), isEmpty);
    });
  });

  group('la orden de lanzar', () {
    final android = ComandoDeEmuladores.leerTabla(
      tablaReal,
    ).firstWhere((e) => e.plataforma == PlataformaEmulador.android);
    final ios = ComandoDeEmuladores.leerTabla(
      tablaReal,
    ).firstWhere((e) => e.plataforma == PlataformaEmulador.ios);

    test('lo normal', () {
      expect(ComandoDeEmuladores.argumentosDeLanzar(android), [
        'emulators',
        '--launch',
        'Medium_Phone_API_36.1',
      ]);
    });

    test('el arranque en frío solo va en Android', () {
      // `--cold` no existe para un simulador de iOS: pasárselo es un argumento
      // que no entiende.
      expect(
        ComandoDeEmuladores.argumentosDeLanzar(android, frio: true),
        contains('--cold'),
      );
      expect(
        ComandoDeEmuladores.argumentosDeLanzar(ios, frio: true),
        isNot(contains('--cold')),
      );
    });
  });

  group('el veredicto del lanzamiento', () {
    test('un id que no existe es un fallo, aunque el proceso salga con 0', () {
      // **La trampa entera de esta feature.** `flutter emulators --launch` sale
      // con código 0 imprimiendo esto, así que quien mire el exit code dirá que
      // lanzó algo que nunca arrancó.
      final r = ComandoDeEmuladores.resultadoDeLanzar(
        'No emulator found that matches "no_existe".',
      );

      expect(r.ok, isFalse);
      expect(r.error, isNotNull);
    });

    test('el camino bueno no imprime nada', () {
      expect(ComandoDeEmuladores.resultadoDeLanzar('').ok, isTrue);
      expect(ComandoDeEmuladores.resultadoDeLanzar('   \n  ').ok, isTrue);
    });

    test('cualquier línea de error cuenta, y se devuelve tal cual', () {
      final r = ComandoDeEmuladores.resultadoDeLanzar(
        'Unable to locate Android SDK.',
      );

      expect(r.ok, isFalse);
      // Literal, como los errores del CLI que la app ya muestra sin traducir:
      // esconderlo tras un «no se pudo» obliga a abrir la terminal.
      expect(r.error, 'Unable to locate Android SDK.');
    });
  });

  group('quién está arriba', () {
    test('adb: los emuladores sí, el móvil enchufado no', () {
      // Salida real con el Redmi conectado y el emulador arriba.
      const salida = '''
List of devices attached
36c56d94	device
emulator-5554	device
''';
      // `36c56d94` es un teléfono de verdad: está en la misma lista y no es un
      // emulador.
      expect(ComandoDeEmuladores.idsDeEmuladorEnAdb(salida), ['emulator-5554']);
    });

    test('un emulador arrancando todavía no cuenta', () {
      // Medido: durante ~20 s del arranque, adb lo lista como `offline`. Darlo
      // por arriba pondría el botón en «cerrar» sobre algo que no se puede usar.
      const salida = '''
List of devices attached
emulator-5554	offline
''';
      expect(ComandoDeEmuladores.idsDeEmuladorEnAdb(salida), isEmpty);
    });

    test('simctl: se mira el estado, no que exista', () {
      const conUnoArriba = '''
{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-1":[
  {"udid":"A","state":"Shutdown","name":"iPhone 17"},
  {"udid":"B","state":"Booted","name":"iPhone Air"}]}}''';
      expect(ComandoDeEmuladores.hayIosArriba(conUnoArriba), isTrue);

      const todosApagados = '''
{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-1":[
  {"udid":"A","state":"Shutdown","name":"iPhone 17"}]}}''';
      expect(ComandoDeEmuladores.hayIosArriba(todosApagados), isFalse);
    });

    test('sin Xcode, simctl no da JSON y eso no puede tirar la lista', () {
      expect(ComandoDeEmuladores.hayIosArriba('xcrun: error: …'), isFalse);
      expect(ComandoDeEmuladores.hayIosArriba(''), isFalse);
    });
  });

  group('el cruce de catálogo y estado', () {
    final catalogo = ComandoDeEmuladores.leerTabla(tablaReal);

    test('el de Android arriba trae con qué cerrarlo', () {
      final conEstado = ComandoDeEmuladores.conEstado(
        catalogo,
        avdsArriba: {'Medium_Phone_API_36.1': 'emulator-5554'},
        iosArriba: false,
      );

      final medium = conEstado.firstWhere(
        (e) => e.id == 'Medium_Phone_API_36.1',
      );
      expect(medium.corriendo, isTrue);
      // Sin esto no se puede matar: no hay id común entre el emulador y el
      // dispositivo que resulta de arrancarlo.
      expect(medium.deviceId, 'emulator-5554');

      expect(conEstado.firstWhere((e) => e.id == 'Small_Phone').corriendo, isFalse);
    });

    test('empareja también por el nombre legible', () {
      // `adb emu avd name` puede contestar el id o el nombre según cómo se
      // creara el AVD.
      final conEstado = ComandoDeEmuladores.conEstado(
        catalogo,
        avdsArriba: {'Small Phone': 'emulator-5556'},
        iosArriba: false,
      );

      expect(conEstado.firstWhere((e) => e.id == 'Small_Phone').corriendo, isTrue);
    });

    test('iOS no lleva dispositivo, porque se apagan todos juntos', () {
      final conEstado = ComandoDeEmuladores.conEstado(
        catalogo,
        avdsArriba: const {},
        iosArriba: true,
      );

      final ios = conEstado.firstWhere((e) => e.id == 'apple_ios_simulator');
      expect(ios.corriendo, isTrue);
      expect(ios.deviceId, isNull);
    });
  });
}
