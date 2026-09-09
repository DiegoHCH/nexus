import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/run/data/datasources/corrida_viva.dart';
import 'package:nexus/features/run/domain/entities/mensaje_del_daemon.dart';

import 'support/hasta_que.dart';

/// **`flutter run --machine` vivo, sin lanzar ningún `flutter run`.**
///
/// 🔴 Punto 3 del repaso: este archivo estaba al **0 % de cobertura** de 47
/// líneas, y no por descuido — llamaba a `Process.start` a pelo, así que
/// probarlo pedía un emulador encendido y tres minutos de compilación. Con el
/// lanzador como parámetro, lo que se puede comprobar es justo lo que se rompe:
/// **qué se le pide al proceso y qué se hace con lo que contesta**.
///
/// Y es donde vive el enganche del VM service, que es lo único del PR de los
/// errores del framework que se quedó sin prueba por este motivo.
class _ProcesoDeMentira implements Process {
  _ProcesoDeMentira();

  final _salida = StreamController<List<int>>();
  final _errores = StreamController<List<int>>();
  final _entrada = _EntradaQueApunta();
  final _fin = Completer<int>();

  /// Lo que el proceso «escribe» por su stdout, tal cual: se parte en trozos
  /// como los parte el sistema, que es lo que obliga a juntar líneas.
  void dice(String texto) => _salida.add(utf8.encode(texto));
  void seQueja(String texto) => _errores.add(utf8.encode(texto));
  void seMuere(int codigo) {
    _salida.close();
    _errores.close();
    if (!_fin.isCompleted) _fin.complete(codigo);
  }

  /// Lo que se le mandó por stdin: el canal por el que se piden las recargas.
  List<String> get loQueSeLePidio => _entrada.escrito;

  @override
  Stream<List<int>> get stdout => _salida.stream;
  @override
  Stream<List<int>> get stderr => _errores.stream;
  @override
  IOSink get stdin => _entrada;
  @override
  Future<int> get exitCode => _fin.future;
  @override
  int get pid => 4242;

  final matados = <ProcessSignal>[];

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    matados.add(signal);
    seMuere(-9);
    return true;
  }
}

class _EntradaQueApunta implements IOSink {
  final escrito = <String>[];

  @override
  void write(Object? objeto) => escrito.add('$objeto');

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late _ProcesoDeMentira proceso;
  late List<EventoDelDaemon> eventos;
  late List<String> registro;
  late List<String?> finales;

  /// Lo que se le pidió al lanzador: el ejecutable, sus argumentos y dónde.
  late ({String ejecutable, List<String> argumentos, String? donde}) pedido;

  setUp(() {
    proceso = _ProcesoDeMentira();
    eventos = [];
    registro = [];
    finales = [];
  });

  Future<CorridaViva?> arrancar({List<String> args = const []}) =>
      CorridaViva.arrancar(
        flutter: '/donde/sea/flutter',
        proyecto: '/casa/tienda',
        deviceId: 'emulator-5554',
        args: args,
        onEvento: eventos.add,
        onRegistro: registro.add,
        onFin: finales.add,
        lanzar:
            (
              ejecutable,
              argumentos, {
              workingDirectory,
              environment,
              includeParentEnvironment = true,
            }) async {
              pedido = (
                ejecutable: ejecutable,
                argumentos: argumentos,
                donde: workingDirectory,
              );
              return proceso;
            },
      );

  test(
    'se lanza en modo máquina, en el proyecto y con sus argumentos',
    () async {
      await arrancar(args: const ['--flavor', 'ci']);

      expect(pedido.ejecutable, '/donde/sea/flutter');
      expect(pedido.argumentos, [
        'run',
        '--machine',
        '-d',
        'emulator-5554',
        '--flavor',
        'ci',
      ]);
      expect(
        pedido.donde,
        '/casa/tienda',
        reason: 'un `flutter run` fuera del proyecto no compila nada',
      );
    },
  );

  test(
    'los eventos del daemon llegan enteros, aunque vengan partidos',
    () async {
      await arrancar();

      // 🔴 Un `Stream` de proceso **no viene en líneas**: llega en trozos del
      // tamaño que decida el sistema, así que un mensaje puede partirse por la
      // mitad. El evento que se perdería es `app.started`, que es justo el que
      // hace falta.
      proceso.dice('[{"event":"app.start","params":{"appId":"abc"');
      proceso.dice('}}]\n[{"event":"app.started","params":{}}]\n');
      await hastaQue(
        () => eventos.length >= 2,
        esperando: 'que lleguen los dos eventos',
        loQueSeVe: () => 'eventos=${eventos.map((e) => e.nombre)}',
      );

      expect(eventos.map((e) => e.nombre), ['app.start', 'app.started']);
      expect(eventos.first.params['appId'], 'abc');
    },
  );

  test(
    'y lo que no es JSON es registro, que ahí van los fallos de compilar',
    () async {
      await arrancar();

      proceso.dice('Launching lib/main.dart on macOS in debug mode...\n');
      proceso.seQueja('** BUILD FAILED **\n');
      await hastaQue(
        () => registro.length >= 2,
        esperando: 'que las dos líneas lleguen al registro',
        loQueSeVe: () => 'registro=$registro',
      );

      expect(registro.first, contains('Launching lib/main.dart'));
      expect(
        registro.last,
        contains('BUILD FAILED'),
        reason: 'stderr entero al registro: ahí sale lo de Gradle y CocoaPods',
      );
    },
  );

  test(
    'recargar se pide por el canal, con el appId que dio el daemon',
    () async {
      final viva = (await arrancar())!;
      proceso.dice('[{"event":"app.start","params":{"appId":"abc"}}]\n');
      await hastaQue(
        () => eventos.isNotEmpty,
        esperando: 'que llegue el appId',
        loQueSeVe: () => 'eventos=${eventos.length}',
      );

      unawaited(viva.recargar(completa: false));
      await hastaQue(
        () => proceso.loQueSeLePidio.isNotEmpty,
        esperando: 'que se le pida la recarga',
        loQueSeVe: () => 'pedido=${proceso.loQueSeLePidio}',
      );

      final pedido = proceso.loQueSeLePidio.single;
      expect(pedido, contains('app.restart'));
      expect(pedido, contains('"appId":"abc"'));
      expect(pedido, contains('"fullRestart":false'));
    },
  );

  // 🔴 **Sin `appId` no hay a quién pedírselo, y eso no es un fallo**: es que
  // sigue compilando. Se dice así, en vez de callarse.
  test('mientras compila, recargar dice que todavía no', () async {
    final viva = (await arrancar())!;

    final resultado = await viva.recargar(completa: false);

    expect(resultado.ok, isFalse);
    expect(resultado.error, 'Todavía está compilando');
    expect(proceso.loQueSeLePidio, isEmpty);
  });

  test('parar se pide por el daemon, no matando el proceso', () async {
    final viva = (await arrancar())!;
    proceso.dice('[{"event":"app.start","params":{"appId":"abc"}}]\n');
    await hastaQue(
      () => eventos.isNotEmpty,
      esperando: 'que llegue el appId',
      loQueSeVe: () => 'eventos=${eventos.length}',
    );

    unawaited(viva.parar());
    await hastaQue(
      () => proceso.loQueSeLePidio.isNotEmpty,
      esperando: 'que se le pida parar',
      loQueSeVe: () => 'pedido=${proceso.loQueSeLePidio}',
    );

    expect(proceso.loQueSeLePidio.single, contains('app.stop'));
    expect(
      proceso.matados,
      isEmpty,
      reason:
          'matarlo dejaría la app abierta en el dispositivo y sin quien lo '
          'cuente',
    );
  });

  // Y si no hay `appId` —murió antes de arrancar— entonces sí se mata: es lo
  // único que queda.
  test('sin appId, parar sí lo mata', () async {
    final viva = (await arrancar())!;

    await viva.parar();

    expect(proceso.matados, isNotEmpty);
  });

  test('un código distinto de cero se cuenta como fallo', () async {
    await arrancar();

    proceso.seMuere(1);
    await hastaQue(
      () => finales.isNotEmpty,
      esperando: 'que se cuente el final',
      loQueSeVe: () => 'finales=$finales',
    );

    expect(finales.single, contains('código 1'));
  });

  // 🔴 **Parar bien no es un fallo.** El proceso sale con código distinto de
  // cero al cerrarse la app, y sin esta distinción quien mira el código diría
  // que se cayó.
  test('pero no si lo paramos nosotros', () async {
    final viva = (await arrancar())!;

    await viva.parar();
    await hastaQue(
      () => finales.isNotEmpty,
      esperando: 'que se cuente el final',
      loQueSeVe: () => 'finales=$finales',
    );

    expect(finales.single, isNull);
  });

  test('y si el binario no está, no hay corrida y no revienta', () async {
    final viva = await CorridaViva.arrancar(
      flutter: '/no/existe/flutter',
      proyecto: '/casa/tienda',
      deviceId: 'emulator-5554',
      args: const [],
      onEvento: eventos.add,
      onRegistro: registro.add,
      onFin: finales.add,
      lanzar:
          (
            ejecutable,
            argumentos, {
            workingDirectory,
            environment,
            includeParentEnvironment = true,
          }) => throw ProcessException(ejecutable, argumentos),
    );

    expect(viva, isNull);
  });
}
