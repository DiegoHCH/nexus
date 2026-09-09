import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/run/data/datasources/el_canal_del_vm_service.dart';
import 'package:nexus/features/run/domain/usecases/el_freno_de_la_app.dart';

import 'support/hasta_que.dart';

/// **El cable al VM service, sin VM service.**
///
/// 🔴 Punto 7 del repaso. Este archivo llamaba a `WebSocket.connect` a pelo, así
/// que probarlo pedía una app compilada y corriendo — y ahora hace algo que
/// antes no hacía: **esperar respuestas**. Ahí lo que se rompe no falla: una
/// respuesta leída como evento deja a quien preguntó esperando para siempre, y
/// el freno no se llega a poner sin que nada lo diga.
class _SocketDeMentira implements WebSocket {
  final _entrada = StreamController<dynamic>();

  /// Lo que se le mandó, en orden.
  final mandado = <String>[];

  void dice(String mensaje) => _entrada.add(mensaje);
  Future<void> seCae() => _entrada.close();

  /// La respuesta a la petición número [cual], con lo que sea.
  void contestaA(int cual, Map<String, Object?> resultado) =>
      dice(jsonEncode({'jsonrpc': '2.0', 'id': cual, 'result': resultado}));

  @override
  StreamSubscription<dynamic> listen(
    void Function(dynamic)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _entrada.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  void add(dynamic data) => mandado.add('$data');

  @override
  Future<void> close([int? code, String? reason]) => _entrada.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

String _evento(Map<String, Object?> evento) => jsonEncode({
  'jsonrpc': '2.0',
  'method': 'streamNotify',
  'params': {'streamId': 'Debug', 'event': evento},
});

void main() {
  late _SocketDeMentira socket;
  late List<String> errores;
  late List<LaParadaDeLaApp> paradas;
  late List<String> siguieron;

  setUp(() {
    socket = _SocketDeMentira();
    errores = [];
    paradas = [];
    siguieron = [];
  });

  Future<ElCanalDelVmService?> abrir({bool conFreno = true}) =>
      ElCanalDelVmService.abrir(
        'ws://127.0.0.1:1234/ws',
        alOirUnError: errores.add,
        alPararse: conFreno ? paradas.add : null,
        alSeguir: siguieron.add,
        conectar: (_) async => socket,
      );

  /// Qué método se pidió en la petición número [cual].
  String metodo(int cual) =>
      '${(jsonDecode(socket.mandado[cual - 1]) as Map)['method']}';

  test('al abrir se apunta a los dos canales', () async {
    await abrir();
    await hastaQue(
      () => socket.mandado.length >= 2,
      esperando: 'que se pidan las dos escuchas',
      loQueSeVe: () => 'mandado=${socket.mandado}',
    );

    expect(metodo(1), 'streamListen');
    expect(metodo(2), 'streamListen');
    expect(socket.mandado.first, contains('Extension'));
    expect(socket.mandado.last, contains('Debug'));
  });

  // Apuntarse a un canal que nadie escucha es tráfico por nada.
  test('y sin quien oiga las paradas, solo al de los errores', () async {
    await abrir(conFreno: false);
    await hastaQue(
      () => socket.mandado.isNotEmpty,
      esperando: 'que se pida la escucha de errores',
      loQueSeVe: () => 'mandado=${socket.mandado}',
    );

    expect(socket.mandado.single, contains('Extension'));
  });

  test('si no se puede conectar, no hay canal y no revienta', () async {
    final canal = await ElCanalDelVmService.abrir(
      'ws://no/existe',
      alOirUnError: errores.add,
      conectar: (_) => throw const SocketException('rechazado'),
    );

    expect(canal, isNull);
  });

  group('preguntar y esperar', () {
    test(
      'cada petición lleva su id, y la respuesta vuelve a quien preguntó',
      () async {
        final canal = (await abrir())!;

        // Dos a la vez, y la segunda se contesta primero: si el emparejamiento
        // fuera por orden de llegada, cada una recibiría la de la otra.
        final primera = canal.pedir(ElFrenoDeLaApp.pedirLosIsolates);
        final segunda = canal.pedir(ElFrenoDeLaApp.pedirLosIsolates);
        await hastaQue(
          () => socket.mandado.length >= 4,
          esperando: 'que salgan las dos peticiones',
          loQueSeVe: () => 'mandado=${socket.mandado.length}',
        );

        socket.contestaA(4, {'quien': 'la segunda'});
        socket.contestaA(3, {'quien': 'la primera'});

        expect(await primera, contains('la primera'));
        expect(await segunda, contains('la segunda'));
      },
    );

    test('y los isolates salen de esa respuesta', () async {
      final canal = (await abrir())!;
      final pregunta = canal.pedir(ElFrenoDeLaApp.pedirLosIsolates);
      await hastaQue(
        () => socket.mandado.length >= 3,
        esperando: 'que salga el getVM',
        loQueSeVe: () => 'mandado=${socket.mandado.length}',
      );

      socket.contestaA(3, {
        'isolates': [
          {'id': 'isolates/1234'},
        ],
      });

      expect(ElFrenoDeLaApp.losIsolates(await pregunta), ['isolates/1234']);
    });

    // 🔴 **Una respuesta no es un evento**, y leerla como tal es lo que dejaría
    // a quien preguntó esperando para siempre.
    test('una respuesta no baja a los lectores', () async {
      final canal = (await abrir())!;
      final pregunta = canal.pedir(ElFrenoDeLaApp.pedirLosIsolates);
      await hastaQue(
        () => socket.mandado.length >= 3,
        esperando: 'que salga la petición',
        loQueSeVe: () => 'mandado=${socket.mandado.length}',
      );

      socket.contestaA(3, {'type': 'VM'});
      await pregunta;

      expect(paradas, isEmpty);
      expect(errores, isEmpty);
      expect(siguieron, isEmpty);
    });

    // Todo esto pasa dentro de un botón: sin plazo, una app a medias deja el
    // botón girando hasta que alguien cierre la ventana.
    test('si no contesta, se deja de esperar y se dice que no hubo', () async {
      final canal = (await abrir())!;

      expect(
        await canal.pedir(
          ElFrenoDeLaApp.pedirLosIsolates,
          tope: const Duration(milliseconds: 20),
        ),
        isNull,
      );
    });

    // 🔴 **Un socket muerto no va a contestar.** Sin esto, quien esperaba se
    // quedaría su plazo entero colgado por una app que ya se cerró.
    test('y si el socket se cae, se suelta a quien esperaba', () async {
      final canal = (await abrir())!;
      final pregunta = canal.pedir(ElFrenoDeLaApp.pedirLosIsolates);
      await hastaQue(
        () => socket.mandado.length >= 3,
        esperando: 'que salga la petición',
        loQueSeVe: () => 'mandado=${socket.mandado.length}',
      );

      await socket.seCae();

      expect(await pregunta, isNull);
    });

    test('cerrar el canal también los suelta', () async {
      final canal = (await abrir())!;
      final pregunta = canal.pedir(ElFrenoDeLaApp.pedirLosIsolates);

      await canal.cerrar();

      expect(await pregunta, isNull);
    });
  });

  group('lo que llega solo', () {
    test('una parada llega leída, con su isolate', () async {
      await abrir();

      socket.dice(
        _evento({
          'kind': 'PauseException',
          'isolate': {'id': 'isolates/1234'},
          'topFrame': {
            'function': {'name': 'Algo.build'},
            'location': {
              'script': {'id': 's1', 'uri': 'package:app/algo.dart'},
              'tokenPos': 10,
            },
          },
          'exception': {'valueAsString': 'Bad state: algo'},
        }),
      );
      await hastaQue(
        () => paradas.isNotEmpty,
        esperando: 'que llegue la parada',
        loQueSeVe: () => 'paradas=${paradas.length}',
      );

      expect(paradas.single.isolate, 'isolates/1234');
      expect(paradas.single.excepcion, 'Bad state: algo');
      expect(paradas.single.funcion, 'Algo.build');
    });

    test('y cuando sigue, se dice cuál siguió', () async {
      await abrir();

      socket.dice(
        _evento({
          'kind': 'Resume',
          'isolate': {'id': 'isolates/1234'},
        }),
      );
      await hastaQue(
        () => siguieron.isNotEmpty,
        esperando: 'que se cuente la reanudación',
        loQueSeVe: () => 'siguieron=$siguieron',
      );

      expect(siguieron.single, 'isolates/1234');
      expect(paradas, isEmpty);
    });

    test('los errores del framework siguen llegando por aquí', () async {
      await abrir();

      socket.dice(
        jsonEncode({
          'jsonrpc': '2.0',
          'method': 'streamNotify',
          'params': {
            'streamId': 'Extension',
            'event': {
              'extensionKind': 'Flutter.Error',
              'extensionData': {
                'renderedErrorText': '══╡ EXCEPTION CAUGHT BY WIDGETS LIBRARY',
              },
            },
          },
        }),
      );
      await hastaQue(
        () => errores.isNotEmpty,
        esperando: 'que llegue el error',
        loQueSeVe: () => 'errores=${errores.length}',
      );

      expect(errores.single, contains('EXCEPTION CAUGHT BY'));
      expect(paradas, isEmpty, reason: 'un error no es una parada');
    });

    test('lo que no es nada de eso no llama a nadie', () async {
      await abrir();

      socket.dice('Connecting to VM Service at ws://…');
      socket.dice(_evento({'kind': 'PauseStart'}));
      await hastaQue(
        () => socket.mandado.length >= 2,
        esperando: 'que el canal esté en marcha',
        loQueSeVe: () => 'mandado=${socket.mandado.length}',
      );

      expect(errores, isEmpty);
      expect(paradas, isEmpty);
      expect(siguieron, isEmpty);
    });
  });
}
