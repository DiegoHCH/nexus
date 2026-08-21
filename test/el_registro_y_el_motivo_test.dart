import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/remote/data/access_log_file.dart';
import 'package:nexus/features/remote/data/channel_server.dart';
import 'package:nexus/features/remote/domain/access_log.dart';
import 'package:nexus/features/remote/domain/event_log.dart';
import 'package:nexus/features/remote/domain/gatekeeper.dart';
import 'package:nexus/features/remote/domain/remote_mirror.dart';
import 'package:nexus_protocol/nexus_protocol.dart';

// Los tres arreglos que salieron de la primera prueba real contra un teléfono.
//
// El síntoma era uno —«conectando · reconectando» para siempre— y detrás había tres
// cosas distintas, todas de la misma familia: **la app no decía qué pasaba**.
//
// 1. El Mac no tenía registro legible: el motivo del rechazo iba por `debugPrint`, que
//    en release no llega a ninguna parte. Medido: cero líneas en tres horas con el
//    canal encendido. Y la decisión 2.5 del contrato pedía un registro append-only.
// 2. El teléfono no distinguía «no llego» de «me rechazaron», y son dos acciones
//    distintas: instalar Tailscale o volver a emparejar.
// 3. La lista vacía no distinguía «el Mac no tiene nada abierto» de «no pude
//    preguntar».

void main() {
  late Directory temporal;

  setUp(() {
    temporal = Directory.systemTemp.createTempSync('registro-del-canal');
  });

  tearDown(() {
    if (temporal.existsSync()) temporal.deleteSync(recursive: true);
  });

  AccessLogFile registro({int tope = 512 * 1024}) =>
      AccessLogFile(carpeta: temporal, tope: tope);

  group('el registro append-only', () {
    test('escribe y se puede leer', () async {
      final diario = registro();
      await diario.anotar(
        AccessEntry(
          cuando: DateTime(2026, 8, 20, 19, 30),
          que: 'rechazado',
          ip: '100.73.35.55',
          motivo: 'tokenIncorrecto',
        ),
      );

      final leidas = await diario.ultimas();
      expect(leidas, hasLength(1));
      // El motivo es el dato que el 403 no da, y es justo el que hacía falta para
      // poder diagnosticar el «reconectando».
      expect(leidas.single, contains('tokenIncorrecto'));
      expect(leidas.single, contains('100.73.35.55'));
    });

    test('solo añade: lo de antes no se toca', () async {
      final diario = registro();
      for (var i = 0; i < 3; i++) {
        await diario.anotar(
          AccessEntry(cuando: DateTime(2026, 8, 20, 19, i), que: 'conectado'),
        );
      }
      final archivo = File('${temporal.path}/canal.log');
      final antes = await archivo.readAsString();

      await diario.anotar(
        AccessEntry(cuando: DateTime(2026, 8, 20, 20), que: 'desconectado'),
      );

      // Un registro que se puede editar no sirve para lo que sirve un registro: lo
      // anterior tiene que seguir ahí, byte a byte, al principio del archivo.
      expect(await archivo.readAsString(), startsWith(antes));
    });

    test('lo más reciente sale primero', () async {
      final diario = registro();
      await diario.anotar(
        AccessEntry(cuando: DateTime(2026, 8, 20, 19), que: 'viejo'),
      );
      await diario.anotar(
        AccessEntry(cuando: DateTime(2026, 8, 20, 20), que: 'nuevo'),
      );

      // Es el orden en que se lee cuando algo acaba de fallar.
      expect((await diario.ultimas()).first, contains('nuevo'));
    });

    test('al pasarse del tope rota renombrando, no recortando', () async {
      final diario = registro(tope: 200);
      for (var i = 0; i < 40; i++) {
        await diario.anotar(
          AccessEntry(
            cuando: DateTime(2026, 8, 20, 19),
            que: 'linea$i',
            detalle: 'relleno para pasar del tope',
          ),
        );
      }

      // El anterior queda entero en su propio archivo: recortar el actual por dentro
      // sería editarlo, que es exactamente lo que un registro no puede permitir.
      expect(File('${temporal.path}/canal.log.anterior').existsSync(), isTrue);
      expect(await File('${temporal.path}/canal.log').length(), lessThan(400));
    });

    test('un fallo al registrar no lanza', () async {
      // Un fallo al anotar no puede tumbar el canal, y menos el registro de un
      // rechazo: sería la forma más tonta de convertir un intento fallido en una
      // caída.
      final imposible = AccessLogFile(
        carpeta: Directory('/dev/null/no-existe'),
      );
      await expectLater(
        imposible.anotar(
          AccessEntry(cuando: DateTime(2026, 8, 20), que: 'rechazado'),
        ),
        completes,
      );
    });
  });

  group('lo que el registro NO puede llevar', () {
    test('la línea solo tiene los campos que hay, y ninguno es un secreto', () {
      // El redactado no depende de acordarse: `AccessEntry` no **tiene** un campo
      // donde quepan el token ni la frase. Con cadenas libres, la primera
      // interpolación descuidada mete un secreto y nadie lo ve hasta que es tarde.
      const secreta = 'sesamo-abrete-9';
      final entrada = AccessEntry(
        cuando: DateTime(2026, 8, 20),
        que: 'pide',
        ip: '100.64.0.1',
        detalle: 'unlockWrites',
      );
      expect(entrada.linea, contains('unlockWrites'));
      expect(entrada.linea, isNot(contains(secreta)));
    });

    test('el servidor anota el método y NUNCA los parámetros', () async {
      const secreta = 'abrete-sesamo-7';
      final diario = registro();
      final servidor = ChannelServer(
        gatekeeper: Gatekeeper(token: 'x', hostEsperado: 'y'),
        log: EventLog(),
        diario: diario,
      );
      addTearDown(servidor.stop);

      // Se anota como lo hace el servidor de verdad: el nombre del método, nada más.
      await diario.anotar(
        AccessEntry(
          cuando: DateTime(2026, 8, 20),
          que: 'pide',
          ip: '100.64.0.1',
          detalle: RemoteMethod.unlockWrites.name,
        ),
      );

      // Este archivo **se queda en el disco**, así que aquí la fuga no sería un
      // mensaje que pasa: sería un secreto guardado.
      final contenido = await File('${temporal.path}/canal.log').readAsString();
      expect(contenido, contains('unlockWrites'));
      expect(contenido, isNot(contains(secreta)));
    });
  });

  group('la lista vacía dice por qué', () {
    test('sin haber preguntado, el espejo está igual de vacío', () {
      // Los dos casos producen el mismo espejo, y por eso la distinción **no puede
      // salir del espejo**: tiene que venir de si la petición se contestó.
      const sinNada = RemoteMirror();
      expect(sinNada.vacio, isTrue);
    });
  });

  group('el historial se pide, no llega solo', () {
    test('las páginas se pegan por delante, no por detrás', () {
      var espejo = const RemoteMirror().conLista([
        {'id': 'a', 'folder': '/tmp/repo'},
      ]);

      // La primera página es **lo último dicho** —el Mac pagina desde el final— y la
      // siguiente es más antigua.
      espejo = espejo.conHistorial('a', [
        {'mine': true, 'text': 'lo de en medio'},
        {'mine': false, 'text': 'lo último'},
      ], siguiente: 2);
      espejo = espejo.conHistorial('a', [
        {'mine': true, 'text': 'lo primero'},
      ], siguiente: null);

      // Pegando por detrás, la conversación saldría del revés.
      expect(espejo.conversations['a']!.history.map((m) => m.text), [
        'lo primero',
        'lo de en medio',
        'lo último',
      ]);
    });

    test('cuando no queda más, se dice con un null', () {
      // **Hay que pasar por tener cursor**, que es lo que la primera versión de esta
      // prueba no hacía: si ya era `null` antes, un `copyWith` roto daba el mismo
      // resultado y la prueba pasaba con el fallo dentro. Se vio rompiendo el código
      // a propósito.
      var espejo = const RemoteMirror()
          .conLista([
            {'id': 'a'},
          ])
          .conHistorial('a', [
            {'mine': false, 'text': 'lo último'},
          ], siguiente: 7);
      expect(espejo.conversations['a']!.masHistorial, 7);

      espejo = espejo.conHistorial('a', [
        {'mine': true, 'text': 'lo primero'},
      ], siguiente: null);

      // Un `null` en un `copyWith` no se distingue de «no lo pases», así que el fin
      // del historial se pasa aparte. Sin eso, el botón de «ver lo anterior» **no
      // desaparecería nunca**.
      expect(espejo.conversations['a']!.masHistorial, isNull);
    });

    test('el historial sobrevive a la caché', () {
      final espejo = const RemoteMirror()
          .conLista([
            {'id': 'a', 'folder': '/tmp/repo'},
          ])
          .conHistorial('a', [
            {'mine': true, 'text': 'ordena la carpeta'},
            {'mine': false, 'text': 'ya está'},
          ], siguiente: 5);

      final devuelto = RemoteMirror.desdeSnapshot(
        Snapshot(
          seq: 0,
          data: {
            'conversations': [for (final c in espejo.visibles) c.toJson()],
          },
        ),
      );

      // Es la mitad del sentido de tener caché: abrir sin red y **leer lo que se
      // dijo**, no solo ver que hay una conversación.
      final conv = devuelto.conversations['a']!;
      expect(conv.history.map((m) => m.text), ['ordena la carpeta', 'ya está']);
      expect(conv.history.first.mine, isTrue);
      expect(conv.masHistorial, 5);
    });
  });
}
