import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/run/data/datasources/el_canal_del_vm_service.dart';

import 'support/hasta_que.dart';

/// El cable al VM service de la corrida: **un socket de verdad**, con un
/// servidor de mentira al otro lado.
///
/// El idioma ya lo fija `el_error_que_pinta_la_app_test.dart` con eventos
/// capturados. Lo que se comprueba aquí es lo que solo se ve enchufando: que se
/// pide el canal al conectar —sin eso el VM service no manda nada— y que un
/// error llega a quien escucha.
void main() {
  late HttpServer servidor;
  late String url;
  final recibido = <String>[];
  WebSocket? cliente;

  setUp(() async {
    recibido.clear();
    servidor = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    url = 'ws://127.0.0.1:${servidor.port}/ws';
    unawaited(
      servidor.forEach((peticion) async {
        final ws = await WebSocketTransformer.upgrade(peticion);
        cliente = ws;
        ws.listen((mensaje) => recibido.add('$mensaje'));
      }),
    );
  });

  tearDown(() async {
    await cliente?.close();
    await servidor.close(force: true);
  });

  String elError(String texto) => jsonEncode({
    'jsonrpc': '2.0',
    'method': 'streamNotify',
    'params': {
      'streamId': 'Extension',
      'event': {
        'extensionKind': 'Flutter.Error',
        'extensionData': {'renderedErrorText': texto},
      },
    },
  });

  test('al conectar se apunta al canal, y lo que llega se cuenta', () async {
    final oidos = <String>[];
    final canal = await ElCanalDelVmService.abrir(url, alOirUnError: oidos.add);
    addTearDown(() async => canal?.cerrar());

    expect(canal, isNotNull);
    await hastaQue(
      () => recibido.isNotEmpty,
      esperando: 'que el canal se pida al conectar',
      loQueSeVe: () => 'no llegó nada al servidor',
    );
    expect(recibido.single, contains('streamListen'));

    cliente!.add(elError('Bad state: el fallo pintando la pantalla'));
    await hastaQue(
      () => oidos.isNotEmpty,
      esperando: 'que el error llegue a quien escucha',
      loQueSeVe: () => 'oídos=${oidos.length}, recibido=${recibido.length}',
    );
    expect(oidos.single, contains('el fallo pintando'));
  });

  // 🔴 **No poder oír no rompe la corrida.** La app sigue corriendo igual de
  // bien sin que nadie escuche sus errores, así que aquí no se lanza nada: se
  // anota y se sigue. Un puerto donde no hay nadie es el caso de todos los días
  // —la corrida se acaba de morir, o el aparato se fue—.
  test('si no hay nadie al otro lado, se dice que no y no revienta', () async {
    final canal = await ElCanalDelVmService.abrir(
      'ws://127.0.0.1:1/ws',
      alOirUnError: (_) => fail('no hay de dónde oír nada'),
    );

    expect(canal, isNull);
  });
}
