import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/emulators/data/datasources/emuladores_data_source.dart';
import 'package:nexus/features/emulators/domain/entities/emulador.dart';
import 'package:nexus/features/emulators/domain/usecases/el_espejo_del_iphone.dart';

/// **Los emuladores de la máquina, sin encender ninguno.**
///
/// 🔴 Punto 3 del repaso: este archivo estaba al **5,7 % de cobertura** de 106
/// líneas, y no por descuido — todo pasaba por un `Process.run` a pelo y una
/// búsqueda en el PATH de verdad, así que probarlo pedía un Mac con Android
/// Studio, un AVD creado y un iPhone enchufado. El parseo sí estaba probado
/// —`los_emuladores_de_la_maquina_test.dart`, con salidas reales— y lo que no
/// había forma de tocar era **lo de en medio**: qué comandos se lanzan, en qué
/// orden y qué se cruza con qué.
///
/// Y eso es justo donde vive lo que se ha pagado: el `flutter devices` de 7
/// segundos que no debe colarse en la lista de emuladores, el `stderr` que no
/// puede pegarse al JSON, y el puente `emulator-5554` ⇄ nombre del AVD, que es
/// lo único que permite cerrar uno.

/// La máquina de mentira: qué binarios hay y qué contesta cada comando.
class _Maquina {
  _Maquina({
    this.binarios = const {
      'flutter': '/sdk/flutter/bin/flutter',
      'adb': '/sdk/platform-tools/adb',
      'scrcpy': '/opt/homebrew/bin/scrcpy',
    },
    this.respuestas = const {},
  });

  /// Dónde está cada binario, o `null` si no está instalado.
  final Map<String, String?> binarios;

  /// De un trozo de la línea de comandos a lo que contesta. Lo que no encaje
  /// contesta vacío y con éxito: aquí se mide cómo se lee lo que llega.
  ///
  /// Gana el trozo **más largo** que encaje, y esto ya se pagó escribiéndolo:
  /// con el orden de inserción, `xcrun simctl list devices booted` respondía lo
  /// de `adb devices` porque contiene «devices», y el simulador de iOS salía
  /// apagado sin que nada lo dijera.
  final Map<String, ProcessResult Function(List<String> argumentos)> respuestas;

  /// Lo que se pidió, en orden, como `binario arg arg`.
  final pedidos = <String>[];

  Future<String?> buscar(String nombre, List<String> candidatos) async =>
      binarios[nombre];

  Future<ProcessResult> correr(
    String ejecutable,
    List<String> argumentos, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
  }) async {
    final linea = '${ejecutable.split('/').last} ${argumentos.join(' ')}';
    pedidos.add(linea);
    final claves = respuestas.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final clave in claves) {
      if (linea.contains(clave)) return respuestas[clave]!(argumentos);
    }
    return ProcessResult(0, 0, '', '');
  }

  bool sePidio(String trozo) => pedidos.any((p) => p.contains(trozo));
}

ProcessResult Function(List<String>) _dice(
  String salida, {
  String error = '',
  int codigo = 0,
}) =>
    (_) => ProcessResult(0, codigo, salida, error);

void main() {
  // `flutter emulators`, con su cabecera y sus consejos.
  const laTabla = '''
2 available emulators:

Id                  • Name                • Manufacturer • Platform

Medium_Phone_API_36 • Medium Phone API 36 • Generic       • android
apple_ios_simulator • iOS Simulator       • Apple         • ios

To run an emulator, run 'flutter emulators --launch <emulator id>'.
''';

  // `adb devices` con un emulador arriba y un móvil enchufado.
  const adbDevices = '''
List of devices attached
emulator-5554	device
36c56d94	device
''';

  const iosArriba =
      '{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":'
      '[{"udid":"A1","name":"iPhone 16","state":"Booted"}]}}';

  EmuladoresDataSource conLa(_Maquina maquina, {AbrirSuelto? abre}) =>
      EmuladoresDataSource(
        correr: maquina.correr,
        buscar: maquina.buscar,
        abrirSuelto: abre ?? _noAbreNada,
      );

  group('el catálogo con su estado', () {
    test('cruza la tabla con adb y con simctl', () async {
      final maquina = _Maquina(
        respuestas: {
          'emulators': _dice(laTabla),
          'adb devices': _dice(adbDevices),
          // Contesta el nombre y luego un `OK`: solo vale la primera línea.
          'emu avd name': _dice('Medium_Phone_API_36\nOK\n'),
          'simctl list devices booted': _dice(iosArriba),
        },
      );

      final resultado = await conLa(maquina).listar();

      expect(resultado.error, isNull);
      final android = resultado.emuladores.first;
      expect(android.nombre, 'Medium Phone API 36');
      expect(android.corriendo, isTrue);
      expect(
        android.deviceId,
        'emulator-5554',
        reason: 'sin el dispositivo no hay con qué cerrarlo',
      );
      expect(resultado.emuladores.last.corriendo, isTrue, reason: 'el de iOS');
    });

    // 🔴 **Los 7 segundos no entran aquí.** `flutter devices --machine` tarda
    // 7 s midiendo aparatos de verdad y esta lista se separó justo por eso: si
    // alguien lo mete en este camino, la pantalla vuelve a tardar 8 s y la
    // medición del comentario deja de ser verdad sin que nada falle.
    test('y no pregunta por los teléfonos, que cuestan 7 segundos', () async {
      final maquina = _Maquina(respuestas: {'emulators': _dice(laTabla)});

      await conLa(maquina).listar();

      expect(maquina.sePidio('devices --machine'), isFalse);
      expect(maquina.sePidio('flutter emulators'), isTrue);
    });

    test('sin Flutter no se corre nada y se dice dónde se buscó', () async {
      final maquina = _Maquina(binarios: const {'flutter': null});

      final resultado = await conLa(maquina).listar();

      expect(resultado.emuladores, isEmpty);
      expect(resultado.error, contains('No se encontró Flutter'));
      expect(maquina.pedidos, isEmpty);
    });

    // 🔴 **Un comando que no contesta no es una lista vacía**: es que no se pudo
    // preguntar, y decirlo es la diferencia entre «no tienes emuladores» y «algo
    // va mal aquí».
    test('si Flutter no contesta, se dice en vez de enseñar cero', () async {
      final resultado = await EmuladoresDataSource(
        buscar: _Maquina().buscar,
        correr:
            (
              ejecutable,
              argumentos, {
              workingDirectory,
              environment,
              includeParentEnvironment = true,
            }) => throw const ProcessException('flutter', ['emulators']),
        abrirSuelto: _noAbreNada,
      ).listar();

      expect(resultado.emuladores, isEmpty);
      expect(resultado.error, contains('no contestó'));
    });

    test('sin adb, los de Android salen pero sin estado', () async {
      final maquina = _Maquina(
        binarios: const {'flutter': '/sdk/flutter', 'adb': null},
        respuestas: {'emulators': _dice(laTabla)},
      );

      final resultado = await conLa(maquina).listar();

      expect(resultado.emuladores.first.corriendo, isFalse);
      expect(resultado.emuladores.first.deviceId, isNull);
      expect(resultado.error, isNull, reason: 'la lista sirve igual');
    });
  });

  group('los teléfonos de verdad', () {
    const elJson = '''
[
  {"name":"24069PC21G","id":"36c56d94","emulator":false,
   "targetPlatform":"android-arm64"},
  {"name":"iPhone","id":"00008030-000C390C1AC0C02E","emulator":false,
   "targetPlatform":"ios"},
  {"name":"macOS","id":"macos","emulator":false,"targetPlatform":"darwin"}
]
''';

    /// `devicectl` **no imprime el JSON**: lo escribe en el archivo que se le
    /// pasa por `--json-output`, así que la máquina de mentira tiene que
    /// escribirlo igual o no se prueba nada de este camino.
    ProcessResult escribeElJsonDeIos(List<String> argumentos) {
      final destino = argumentos[argumentos.indexOf('--json-output') + 1];
      File(destino).writeAsStringSync(
        '{"result":{"devices":[{"hardwareProperties":'
        '{"udid":"00008030-000C390C1AC0C02E","marketingName":"iPhone 11"}}]}}',
      );
      return ProcessResult(0, 0, '', '');
    }

    test('salen del JSON de stdout y con nombres de persona', () async {
      final maquina = _Maquina(
        respuestas: {
          'devices --machine': _dice(
            elJson,
            // 🔴 Esto es lo que rompía el parseo cuando las dos salidas se
            // pegaban: con esta línea delante no hay JSON que leer.
            error:
                'Waiting for another flutter command to release the '
                'startup lock...',
          ),
          'getprop ro.product.marketname': _dice('POCO F6\n'),
          'devicectl list devices': escribeElJsonDeIos,
        },
      );

      final dispositivos = await conLa(maquina).listarDispositivos();

      // El `macos` de Flutter no es un teléfono y no sale.
      expect(dispositivos, hasLength(2));
      expect(
        dispositivos.first.nombre,
        'POCO F6',
        reason: 'Flutter lo llama «24069PC21G», que no dice cuál de los dos es',
      );
      expect(
        dispositivos.last.nombre,
        'iPhone 11',
        reason: 'Flutter llama «iPhone» a todos los iPhone',
      );
    });

    // Un nombre pobre es mejor que ninguno: si la plataforma no contesta se
    // queda el que reportó Flutter.
    test('si nadie da el nombre bueno, se queda el de Flutter', () async {
      final maquina = _Maquina(
        respuestas: {'devices --machine': _dice(elJson)},
      );

      final dispositivos = await conLa(maquina).listarDispositivos();

      expect(dispositivos.first.nombre, '24069PC21G');
      expect(dispositivos.last.nombre, 'iPhone');
    });

    test('el temporal de devicectl se borra al acabar', () async {
      String? destino;
      final maquina = _Maquina(
        respuestas: {
          'devices --machine': _dice(elJson),
          'devicectl list devices': (argumentos) {
            destino = argumentos[argumentos.indexOf('--json-output') + 1];
            return escribeElJsonDeIos(argumentos);
          },
        },
      );

      await conLa(maquina).listarDispositivos();

      expect(destino, isNotNull);
      expect(File(destino!).existsSync(), isFalse);
    });

    test('sin Flutter, ninguno', () async {
      final maquina = _Maquina(binarios: const {'flutter': null});

      expect(await conLa(maquina).listarDispositivos(), isEmpty);
      expect(maquina.pedidos, isEmpty);
    });

    test('sin teléfonos no se pregunta ningún nombre', () async {
      final maquina = _Maquina(respuestas: {'devices --machine': _dice('[]')});

      expect(await conLa(maquina).listarDispositivos(), isEmpty);
      expect(maquina.sePidio('getprop'), isFalse);
      expect(maquina.sePidio('devicectl'), isFalse);
    });
  });

  group('lanzar uno', () {
    const android = Emulador(
      id: 'Medium_Phone_API_36',
      nombre: 'Medium Phone API 36',
      fabricante: 'Generic',
      plataforma: PlataformaEmulador.android,
    );

    test('se pide por su id y se espera a que aparezca arriba', () async {
      final maquina = _Maquina(
        respuestas: {
          'adb devices': _dice(adbDevices),
          'emu avd name': _dice('Medium_Phone_API_36\nOK\n'),
        },
      );

      final error = await conLa(maquina).lanzar(android, cada: Duration.zero);

      expect(error, isNull);
      expect(maquina.sePidio('emulators --launch Medium_Phone_API_36'), isTrue);
    });

    // 🔴 **`--launch` sale con 0 aunque falle**, así que el veredicto se lee de
    // la salida. Mirando el código, la app diría que lanzó algo que no arrancó.
    test(
      'un id que no existe es un fallo aunque el proceso salga bien',
      () async {
        final maquina = _Maquina(
          respuestas: {
            'emulators --launch': _dice(
              'No emulator found that matches Medium_Phone_API_36',
            ),
          },
        );

        expect(
          await conLa(maquina).lanzar(android, cada: Duration.zero),
          'No se encontró ese emulador',
        );
      },
    );

    // Se lanzó bien pero no aparece: no es lo mismo que «no se pudo», porque
    // puede seguir arrancando. Un emulador tarda ~20 s en existir.
    test('lanzado y todavía sin aparecer, se dice así', () async {
      final maquina = _Maquina();

      final error = await conLa(
        maquina,
      ).lanzar(android, cada: Duration.zero, intentos: 2);

      expect(error, 'Se lanzó, pero todavía no aparece arrancado');
    });

    test('sin Flutter no se intenta', () async {
      final maquina = _Maquina(binarios: const {'flutter': null});

      expect(
        await conLa(maquina).lanzar(android, cada: Duration.zero),
        'No se encontró Flutter',
      );
    });

    test('el arranque en frío solo se le pasa a Android', () async {
      final maquina = _Maquina(
        respuestas: {
          'adb devices': _dice(adbDevices),
          'emu avd name': _dice('Medium_Phone_API_36\nOK\n'),
          'simctl list devices booted': _dice(iosArriba),
        },
      );
      final fuente = conLa(maquina);

      await fuente.lanzar(android, frio: true, cada: Duration.zero);
      expect(maquina.sePidio('--cold'), isTrue);

      maquina.pedidos.clear();
      await fuente.lanzar(
        const Emulador(
          id: 'apple_ios_simulator',
          nombre: 'iOS Simulator',
          fabricante: 'Apple',
          plataforma: PlataformaEmulador.ios,
        ),
        frio: true,
        cada: Duration.zero,
      );
      expect(maquina.sePidio('--cold'), isFalse);
    });
  });

  group('cerrar uno', () {
    test('el de Android, por su dispositivo', () async {
      final maquina = _Maquina();

      final error = await conLa(maquina).cerrar(
        const Emulador(
          id: 'Medium_Phone_API_36',
          nombre: 'Medium Phone API 36',
          fabricante: 'Generic',
          plataforma: PlataformaEmulador.android,
          corriendo: true,
          deviceId: 'emulator-5554',
        ),
      );

      expect(error, isNull);
      expect(maquina.sePidio('adb -s emulator-5554 emu kill'), isTrue);
    });

    test('y sin dispositivo se dice, en vez de matar otro', () async {
      final maquina = _Maquina();

      expect(
        await conLa(maquina).cerrar(
          const Emulador(
            id: 'Medium_Phone_API_36',
            nombre: 'Medium Phone API 36',
            fabricante: 'Generic',
            plataforma: PlataformaEmulador.android,
            corriendo: true,
          ),
        ),
        'No se supo qué emulador cerrar',
      );
      expect(maquina.pedidos, isEmpty);
    });

    // 🔴 **En iOS son dos pasos.** Sin cerrar la app queda la ventana abierta en
    // negro, que se lee como que sigue arrancado.
    test('el de iOS se apaga y además se cierra la ventana', () async {
      final maquina = _Maquina();

      final error = await conLa(maquina).cerrar(
        const Emulador(
          id: 'apple_ios_simulator',
          nombre: 'iOS Simulator',
          fabricante: 'Apple',
          plataforma: PlataformaEmulador.ios,
          corriendo: true,
        ),
      );

      expect(error, isNull);
      expect(maquina.sePidio('simctl shutdown all'), isTrue);
      expect(maquina.sePidio('quit app "Simulator"'), isTrue);
    });
  });

  group('el espejo del móvil', () {
    test('se abre suelto, con el título y sin control', () async {
      final aperturas = <({List<String> argumentos, ProcessStartMode modo})>[];
      final maquina = _Maquina();

      final error =
          await conLa(
            maquina,
            abre: (ejecutable, argumentos, {required modo, entorno}) async {
              aperturas.add((argumentos: argumentos, modo: modo));
            },
          ).verLaPantalla(
            deviceId: '36c56d94',
            titulo: 'POCO F6',
            conControl: false,
          );

      expect(error, isNull);
      expect(
        aperturas.single.argumentos,
        containsAll(['--serial', '36c56d94']),
      );
      expect(aperturas.single.argumentos, contains('--no-control'));
      // 🔴 **`detached`, y por eso hay costura.** Con el modo por defecto Dart
      // abre las tres tuberías y nadie las lee: scrcpy vive horas espejando y se
      // queda bloqueado al llenarse el búfer — un espejo congelado sin nada que
      // lo explique.
      expect(aperturas.single.modo, ProcessStartMode.detached);
    });

    test('sin scrcpy instalado, se dice y no se abre nada', () async {
      final maquina = _Maquina(
        binarios: const {'flutter': '/sdk/flutter', 'scrcpy': null},
      );

      expect(
        await conLa(maquina).verLaPantalla(
          deviceId: '36c56d94',
          titulo: 'POCO F6',
          conControl: true,
        ),
        'No se encontró scrcpy',
      );
    });

    test('si el sistema no lo deja abrir, se devuelve el motivo', () async {
      final error =
          await EmuladoresDataSource(
            buscar: _Maquina().buscar,
            correr: _Maquina().correr,
            abrirSuelto: (ejecutable, argumentos, {required modo, entorno}) =>
                throw const ProcessException('scrcpy', [], 'Permission denied'),
          ).verLaPantalla(
            deviceId: '36c56d94',
            titulo: 'POCO F6',
            conControl: true,
          );

      expect(error, 'Permission denied');
    });

    test('el del iPhone abre la app de macOS que se elija', () async {
      final aperturas = <List<String>>[];

      final error = await EmuladoresDataSource(
        buscar: _Maquina().buscar,
        correr: _Maquina().correr,
        abrirSuelto: (ejecutable, argumentos, {required modo, entorno}) async {
          aperturas.add([ejecutable, ...argumentos]);
        },
      ).verElIphone(ComoVerElIphone.duplicado);

      expect(error, isNull);
      expect(aperturas.single, ['open', '-a', 'iPhone Mirroring']);
    });
  });
}

Future<void> _noAbreNada(
  String ejecutable,
  List<String> argumentos, {
  required ProcessStartMode modo,
  Map<String, String>? entorno,
}) async {}
