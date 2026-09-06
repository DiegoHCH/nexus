import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/platform/lo_que_pide_la_pagina.dart';
import 'package:nexus/features/emulators/domain/entities/emulador.dart';
import 'package:nexus/features/run/domain/entities/corrida.dart';
import 'package:nexus/features/run/presentation/providers/corridas_providers.dart';
import 'package:nexus/features/run/presentation/providers/la_ventana_del_registro.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// El registro de la corrida, en su ventana.
///
/// 🔴 **Cuando una compilación falla, el motivo está aquí y en ningún otro
/// sitio**: los errores de Gradle, los del compilador de Dart y los del NDK
/// salen por aquí, y el panel solo sabe decir que algo va mal. Lo que se prueba
/// es que se pinte cuando toca y —sobre todo— que **deje de pintarse** cuando
/// ya no hay nadie mirando: era un interruptor de widget y ahora es un oyente
/// que nadie cancela si no lo hacemos nosotros.
const _deviceId = 'emulator-5554';

const _corrida = Corrida(
  deviceId: _deviceId,
  dispositivo: 'Medium Phone API 36.1',
  proyecto: '/casa/tienda',
  configuracion: 'Tienda (dev)',
  plataforma: PlataformaEmulador.android,
  estado: EstadoDeCorrida.corriendo,
  appId: 'abc',
);

class _Corridas extends CorridasController {
  @override
  Map<String, Corrida> build() => const {_deviceId: _corrida};

  void seAcabo() => state = const {};
}

class _Pintor {
  final paginas = <({String nombre, String html, bool primeraVez})>[];

  Future<void> pinta(
    String nombre,
    String html, {
    required bool primeraVez,
  }) async => paginas.add((nombre: nombre, html: html, primeraVez: primeraVez));

  String get ultima => paginas.last.html;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Pintor pintor;
  late ProviderContainer contenedor;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    pintor = _Pintor();
    contenedor = ProviderContainer(
      overrides: [
        elPintorDeVentanasProvider.overrideWithValue(pintor.pinta),
        corridasProvider.overrideWith(_Corridas.new),
      ],
    );
    addTearDown(contenedor.dispose);
    addTearDown(LoQuePideLaPagina.olvidarTodo);
  });

  LasVentanasDelRegistro ventanas() =>
      contenedor.read(lasVentanasDelRegistroProvider.notifier);

  void anota(String linea) =>
      contenedor.read(registrosProvider.notifier).anota(_deviceId, linea);

  /// Lo que llega no se pinta al momento: se junta lo de este rato y se escribe
  /// una vez. Ver [LasVentanasDelRegistro.ritmo].
  Future<void> alRitmo() =>
      Future<void>.delayed(LasVentanasDelRegistro.ritmo * 2);

  test('abrirlo escribe su página, con el dispositivo dentro', () async {
    await ventanas().abre(_corrida, sistema: false);

    expect(pintor.paginas.single.nombre, 'registro-emulator-5554');
    expect(pintor.paginas.single.primeraVez, isTrue);
    expect(pintor.ultima, contains('Medium Phone API 36.1'));
    expect(pintor.ultima, contains('Tienda (dev)'));
    expect(contenedor.read(lasVentanasDelRegistroProvider), {
      'registro-emulator-5554',
    });
  });

  test('lo que imprime la corrida llega a la página', () async {
    await ventanas().abre(_corrida, sistema: false);
    anota("lib/main.dart:12:3: Error: Expected ';'");
    await alRitmo();

    expect(pintor.ultima, contains("Expected ';'"));
    expect(
      pintor.paginas.last.primeraVez,
      isFalse,
      reason: 'ya estaba abierta',
    );
  });

  // 🔴 **Gradle escupe a ráfagas**, y escribir el archivo por cada línea es
  // machacar el disco y pedirle al visor una recarga por línea.
  test('una ráfaga se escribe una sola vez', () async {
    await ventanas().abre(_corrida, sistema: false);
    final antes = pintor.paginas.length;

    for (var i = 0; i < 50; i++) {
      anota('linea $i');
    }
    await alRitmo();

    expect(pintor.paginas.length - antes, 1);
    expect(pintor.ultima, contains('linea 49'));
  });

  test('las líneas de otra corrida no repintan esta', () async {
    await ventanas().abre(_corrida, sistema: false);
    final antes = pintor.paginas.length;

    contenedor.read(registrosProvider.notifier).anota('otro-1234', 'lo suyo');
    await alRitmo();

    expect(pintor.paginas.length, antes);
  });

  // Sin proceso no van a llegar más líneas, y dejar el oyente vivo sería uno
  // por cada app que se corrió en la sesión.
  test('al pararse la corrida se pinta una última vez y se suelta', () async {
    await ventanas().abre(_corrida, sistema: false);
    (contenedor.read(corridasProvider.notifier) as _Corridas).seAcabo();
    await alRitmo();

    expect(
      pintor.ultima,
      isNot(contains('class="gira"')),
      reason: 'el indicador de que algo pasa se apaga con la corrida',
    );
    expect(contenedor.read(lasVentanasDelRegistroProvider), isEmpty);

    final antes = pintor.paginas.length;
    anota('esto ya no lo lee nadie');
    await alRitmo();
    expect(pintor.paginas.length, antes);
  });

  // «Dejar de seguirla» y no «cerrarla»: la ventana es del sistema y no se
  // puede cerrar desde aquí. Lo que se apaga es el repintado, que es lo que
  // cuesta — y el botón del panel, que si no seguiría marcado.
  test('el mismo botón la suelta, y volver a pulsarlo la reabre', () async {
    await ventanas().abre(_corrida, sistema: false);

    ventanas().alterna(_corrida, sistema: false);
    expect(contenedor.read(lasVentanasDelRegistroProvider), isEmpty);

    final antes = pintor.paginas.length;
    anota('mientras nadie mira');
    await alRitmo();
    expect(pintor.paginas.length, antes);

    ventanas().alterna(_corrida, sistema: false);
    await alRitmo();
    expect(contenedor.read(lasVentanasDelRegistroProvider), isNotEmpty);
    expect(pintor.ultima, contains('mientras nadie mira'));
    expect(
      pintor.paginas.last.primeraVez,
      isTrue,
      reason: 'hay que volver a pedirle al visor que la ponga delante',
    );
  });
}
