import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/emulators/domain/entities/emulador.dart';
import 'package:nexus/features/run/data/datasources/tunel_data_source.dart';
import 'package:nexus/features/run/domain/entities/corrida.dart';
import 'package:nexus/features/run/domain/usecases/la_consola_de_la_app.dart';
import 'package:nexus/features/run/presentation/providers/corridas_providers.dart';
import 'package:nexus/features/run/presentation/providers/la_consola_que_se_abre.dart';

/// La consola de depuración que la app se levanta a sí misma.
///
/// 🔴 **Nada de esto se inventa.** Si hay consola lo dice la configuración
/// elegida del `launch.json`; en qué puerto lo dice la app en su banner. El
/// `9777` es de *ese* repositorio: cablearlo sería acertar hoy y fallar el día
/// que alguien lo cambie, con un fallo que no diría por qué.
void main() {
  group('si la configuración la enciende', () {
    test('con el flag en true, sí', () {
      expect(
        LaConsolaDeLaApp.laEnciende([
          '--flavor',
          'ci',
          '--dart-define=ENABLE_DEBUG_SERVER=true',
        ]),
        isTrue,
      );
    });

    // Está en los `launch.json` de verdad: el entorno de producción lo apaga, y
    // tratarlo como encendido abriría un túnel a un puerto donde no hay nadie.
    test('con el flag en false, no', () {
      expect(
        LaConsolaDeLaApp.laEnciende([
          '--dart-define=ENABLE_DEBUG_SERVER=false',
        ]),
        isFalse,
      );
    });

    test('sin flag, no', () {
      expect(LaConsolaDeLaApp.laEnciende(['--flavor', 'ci']), isFalse);
      expect(LaConsolaDeLaApp.laEnciende(const []), isFalse);
    });
  });

  group('el puerto del banner', () {
    test('sale de lo que imprime la app', () {
      expect(
        LaConsolaDeLaApp.puertoEn(
          '🔧 Debug server listo. Abre: http://localhost:9777',
        ),
        9777,
      );
      expect(
        LaConsolaDeLaApp.puertoEn('escuchando en http://127.0.0.1:8080'),
        8080,
      );
    });

    // Una traza con `Perfil.kt:9777` no es un banner, y un `logcat` está lleno
    // de números detrás de dos puntos.
    test('y no de cualquier número detrás de dos puntos', () {
      expect(
        LaConsolaDeLaApp.puertoEn(
          '\tat com.ejemplo.Perfil.onCreate(Perfil.kt:9777)',
        ),
        isNull,
      );
      expect(LaConsolaDeLaApp.puertoEn('localhost:9777'), isNull);
    });

    test('un puerto imposible no es un puerto', () {
      expect(LaConsolaDeLaApp.puertoEn('http://localhost:0'), isNull);
      expect(LaConsolaDeLaApp.puertoEn('http://localhost:99999'), isNull);
    });

    test('y la URL de la ventana sale de él', () {
      expect(LaConsolaDeLaApp.urlDe(9777), 'http://localhost:9777');
    });
  });

  group('de una línea a una ventana abierta', () {
    const deviceId = 'emulator-5554';
    const conConsola = ['--dart-define=ENABLE_DEBUG_SERVER=true'];
    const elBanner = 'Debug server listo. Abre: http://localhost:9777';

    late _Tunel tunel;
    late List<String> abiertas;
    late ProviderContainer contenedor;

    setUp(() {
      tunel = _Tunel();
      abiertas = [];
      contenedor = ProviderContainer(
        overrides: [
          tunelDataSourceProvider.overrideWithValue(tunel),
          abreLaConsolaProvider.overrideWithValue(({
            required url,
            titulo,
          }) async {
            abiertas.add(url);
            return true;
          }),
          corridasProvider.overrideWith(_Corridas.new),
        ],
      );
      addTearDown(contenedor.dispose);
    });

    LaConsolaQueSeAbre laConsola() =>
        contenedor.read(laConsolaQueSeAbreProvider);

    test('con el flag y el banner: túnel, ventana y puerto apuntado', () async {
      laConsola().alArrancar(deviceId: deviceId, args: conConsola);
      await laConsola().alVerLaLinea(deviceId, elBanner);

      expect(tunel.abiertos, ['$deviceId:9777']);
      expect(abiertas, ['http://localhost:9777']);
      expect(contenedor.read(corridasProvider)[deviceId]?.consola, 9777);
      // Y queda escrito: la ventana se puede cerrar, y la dirección tiene que
      // seguir en algún sitio.
      expect(
        contenedor.read(registrosProvider)[deviceId]?.last,
        contains('http://localhost:9777'),
      );
    });

    test('sin el flag no se mira ni una línea', () async {
      laConsola().alArrancar(
        deviceId: deviceId,
        args: const ['--flavor', 'ci'],
      );
      await laConsola().alVerLaLinea(deviceId, elBanner);

      expect(tunel.abiertos, isEmpty);
      expect(abiertas, isEmpty);
    });

    test('y el banner solo cuenta una vez', () async {
      laConsola().alArrancar(deviceId: deviceId, args: conConsola);
      await laConsola().alVerLaLinea(deviceId, elBanner);
      await laConsola().alVerLaLinea(deviceId, elBanner);

      expect(abiertas, hasLength(1), reason: 'dos ventanas iguales no ayudan');
    });

    // 🔴 El fallo típico es el puerto ocupado por el `forward` huérfano de otra
    // sesión. Abrir la ventana igual sería enseñar un «no se puede conectar»
    // sin decir por qué.
    test('si el túnel no se puede abrir, no se abre la ventana', () async {
      contenedor.dispose();
      tunel = _Tunel(problema: 'error: cannot bind listener');
      contenedor = ProviderContainer(
        overrides: [
          tunelDataSourceProvider.overrideWithValue(tunel),
          abreLaConsolaProvider.overrideWithValue(({
            required url,
            titulo,
          }) async {
            abiertas.add(url);
            return true;
          }),
          corridasProvider.overrideWith(_Corridas.new),
        ],
      );

      laConsola().alArrancar(deviceId: deviceId, args: conConsola);
      await laConsola().alVerLaLinea(deviceId, elBanner);

      expect(abiertas, isEmpty);
      expect(
        contenedor.read(registrosProvider)[deviceId]?.last,
        contains('cannot bind listener'),
      );
    });

    test('al terminar la corrida, el túnel se cierra', () async {
      laConsola().alArrancar(deviceId: deviceId, args: conConsola);
      await laConsola().alVerLaLinea(deviceId, elBanner);
      await laConsola().alTerminar(deviceId);

      expect(tunel.cerrados, ['$deviceId:9777']);
    });

    test('y sin túnel abierto, terminar no hace nada', () async {
      await laConsola().alTerminar(deviceId);

      expect(tunel.cerrados, isEmpty);
    });
  });

  group('el túnel', () {
    test('enchufa el mismo puerto a los dos lados', () async {
      final pedidos = <List<String>>[];
      final tunel = TunelDataSource(
        donde: (_, {required candidatos}) async => '/usr/bin/adb',
        correr: (exe, args) async {
          pedidos.add([exe, ...args]);
          return ProcessResult(1, 0, '', '');
        },
      );

      expect(
        await tunel.abrir(deviceId: 'emulator-5554', puerto: 9777),
        isNull,
      );
      expect(pedidos.single, [
        '/usr/bin/adb',
        '-s',
        'emulator-5554',
        'forward',
        'tcp:9777',
        'tcp:9777',
      ]);
    });

    // Se llama al terminar la corrida: un `forward` huérfano se queda vivo en el
    // daemon de `adb` el resto de la sesión.
    test('y se quita por el mismo sitio', () async {
      final pedidos = <List<String>>[];
      final tunel = TunelDataSource(
        donde: (_, {required candidatos}) async => '/usr/bin/adb',
        correr: (exe, args) async {
          pedidos.add(args);
          return ProcessResult(1, 0, '', '');
        },
      );

      await tunel.cerrar(deviceId: 'emulator-5554', puerto: 9777);

      expect(pedidos.single, [
        '-s',
        'emulator-5554',
        'forward',
        '--remove',
        'tcp:9777',
      ]);
    });

    test('sin adb se dice, no se calla', () async {
      final tunel = TunelDataSource(
        donde: (_, {required candidatos}) async => null,
        correr: (_, _) async => throw StateError('no debería llamarse'),
      );

      expect(
        await tunel.abrir(deviceId: 'emulator-5554', puerto: 9777),
        contains('adb'),
      );
    });

    // El puerto ocupado es el fallo de verdad de esto, y `adb` lo cuenta por
    // stderr: sin recogerlo, la ventana se abriría contra nada.
    test('y lo que conteste adb al fallar se recoge', () async {
      final tunel = TunelDataSource(
        donde: (_, {required candidatos}) async => '/usr/bin/adb',
        correr: (_, _) async =>
            ProcessResult(1, 1, '', 'error: cannot bind listener'),
      );

      expect(
        await tunel.abrir(deviceId: 'emulator-5554', puerto: 9777),
        'error: cannot bind listener',
      );
    });
  });
}

/// Y el cableado: de una línea del registro a una ventana abierta.
///
/// Se prueba la clase que decide y no el controlador de corridas: aquél lleva un
/// `flutter run` de verdad, y lo que hay que comprobar aquí son los tres pasos
/// —¿hay consola?, ¿en qué puerto?, ¿hace falta túnel?— sin compilar nada.
class _Tunel extends TunelDataSource {
  _Tunel({this.problema});

  final String? problema;
  final abiertos = <String>[];
  final cerrados = <String>[];

  @override
  Future<String?> abrir({required String deviceId, required int puerto}) async {
    abiertos.add('$deviceId:$puerto');
    return problema;
  }

  @override
  Future<void> cerrar({required String deviceId, required int puerto}) async =>
      cerrados.add('$deviceId:$puerto');
}

class _Corridas extends CorridasController {
  @override
  Map<String, Corrida> build() => const {
    'emulator-5554': Corrida(
      deviceId: 'emulator-5554',
      dispositivo: 'Medium Phone API 36.1',
      proyecto: '/casa/tienda',
      configuracion: 'Tienda (dev)',
      plataforma: PlataformaEmulador.android,
      estado: EstadoDeCorrida.corriendo,
      appId: 'abc',
    ),
  };
}
