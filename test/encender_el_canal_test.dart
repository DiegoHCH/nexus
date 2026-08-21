import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/remote/domain/channel_token.dart';
import 'package:nexus/features/remote/domain/write_phrase.dart';
import 'package:nexus/features/remote/presentation/providers/write_phrase_providers.dart';
import 'package:nexus/features/remote/presentation/providers/channel_providers.dart';
import 'package:nexus/features/remote/presentation/providers/channel_token_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Encender el canal, con Tailscale y sin él.
//
// Sin él es el caso normal de la primera vez, y **es el que no se puede probar a
// mano en esta máquina** — aquí no hay Tailscale corriendo. De ahí que buscar la
// dirección sea inyectable: la política de «solo por Tailscale» solo se puede
// comprobar si se puede fingir que no está.
class _Memoria implements ChannelTokenStore {
  ChannelToken? _guardado;
  int escrituras = 0;

  @override
  Future<ChannelToken?> read() async => _guardado;
  @override
  Future<void> write(ChannelToken token) async {
    _guardado = token;
    escrituras++;
  }

  @override
  Future<void> clear() async => _guardado = null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Memoria tokens;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tokens = _Memoria();
  });

  ProviderContainer montar({InternetAddress? tailscale, WriteUnlock? permiso}) {
    final c = ProviderContainer(
      overrides: [
        channelTokenStoreProvider.overrideWithValue(tokens),
        tailscaleAddressProvider.overrideWithValue(() async => tailscale),
        if (permiso != null) writeUnlockProvider.overrideWithValue(permiso),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('nace apagado', () async {
    final c = montar();
    expect(c.read(channelControllerProvider), isA<ChannelOff>());
  });

  test('sin Tailscale no escucha, y dice por qué', () async {
    // Lo importante es lo segundo: sin motivo, la pantalla solo podría decir «no
    // se pudo», que no es nada que nadie pueda arreglar.
    final c = montar();
    await c.read(channelControllerProvider.notifier).encender();

    final estado = c.read(channelControllerProvider);
    expect(estado, isA<ChannelUnavailable>());
    expect((estado as ChannelUnavailable).reason, ChannelProblem.noTailscale);
  });

  test('y no se recuerda una elección que no se pudo cumplir', () async {
    // Si se guardara, el siguiente arranque volvería a intentarlo y a fallar, y el
    // estado inicial diría «apagado» en una pantalla que enseña un error.
    final c = montar();
    await c.read(channelControllerProvider.notifier).encender();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('remote_channel_on'), isNull);
  });

  test('sin Tailscale tampoco se genera token', () async {
    // El token se asegura **después** de comprobar la dirección: al revés, un Mac
    // sin Tailscale acabaría con un secreto guardado que no abre nada.
    final c = montar();
    await c.read(channelControllerProvider.notifier).encender();
    expect(await tokens.read(), isNull);
    expect(tokens.escrituras, 0);
  });

  group('con Tailscale', () {
    // Se finge la dirección con la de bucle: lo que se prueba es la política de
    // encendido, no que `HttpServer` sepa escuchar.
    final falsa = InternetAddress.loopbackIPv4;

    test('escucha, y en el puerto acordado', () async {
      final c = montar(tailscale: falsa);
      await c.read(channelControllerProvider.notifier).encender();

      final estado = c.read(channelControllerProvider);
      expect(estado, isA<ChannelOn>());
      expect((estado as ChannelOn).port, canalPuerto);
      expect(estado.url, 'ws://127.0.0.1:$canalPuerto');
      await c.read(channelControllerProvider.notifier).apagar();
    });

    test(
      'asegura el token antes de escuchar, y no lo rota al reencender',
      () async {
        final c = montar(tailscale: falsa);
        final control = c.read(channelControllerProvider.notifier);

        await control.encender();
        final primero = await tokens.read();
        expect(primero, isNotNull);

        await control.apagar();
        await control.encender();

        expect(
          await tokens.read(),
          primero,
          reason: 'reencender no puede invalidar el teléfono ya emparejado',
        );
        expect(tokens.escrituras, 1);
        await control.apagar();
      },
    );

    test('recuerda que quedó encendido', () async {
      final c = montar(tailscale: falsa);
      await c.read(channelControllerProvider.notifier).encender();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('remote_channel_on'), isTrue);
      await c.read(channelControllerProvider.notifier).apagar();
      expect(prefs.getBool('remote_channel_on'), isFalse);
    });

    test('rotar el token cierra también la ventana de escritura', () async {
      // **El agujero que esto tapa**: rotar echaba a quien estuviera dentro pero
      // dejaba el permiso concedido. El `WriteUnlock` es uno para todo el canal y
      // sobrevive a apagar y encender, así que el siguiente teléfono que se
      // emparejara con el token nuevo heredaba permiso de escritura sin haber
      // teclado nunca la frase. Revocar a medias no es revocar.
      final permiso = WriteUnlock();
      final c = montar(tailscale: falsa, permiso: permiso);
      final control = c.read(channelControllerProvider.notifier);
      await control.encender();

      expect(
        permiso.intentar(
          guardada: const WritePhrase('ábreme-la-puerta'),
          recibida: 'ábreme-la-puerta',
        ),
        isNull,
        reason: 'la frase buena concede, que es el punto de partida',
      );
      expect(permiso.puedeEscribir, isTrue);

      await control.rotarToken();

      expect(permiso.puedeEscribir, isFalse);
      await control.apagar();
    });

    test('el puerto ocupado se distingue de los demás fallos', () async {
      // Tiene una causa concreta y adivinable —otra copia de Nexus abierta— y por
      // eso merece su propio mensaje en vez de un «no se pudo».
      final ocupado = await HttpServer.bind(falsa, canalPuerto);
      final c = montar(tailscale: falsa);
      await c.read(channelControllerProvider.notifier).encender();

      final estado = c.read(channelControllerProvider);
      expect(estado, isA<ChannelUnavailable>());
      expect((estado as ChannelUnavailable).reason, ChannelProblem.portBusy);
      await ocupado.close();
    });

    test('apagar cierra de verdad', () async {
      final c = montar(tailscale: falsa);
      final control = c.read(channelControllerProvider.notifier);
      await control.encender();
      await control.apagar();

      expect(c.read(channelControllerProvider), isA<ChannelOff>());
      // Si no cerrara, esto lanzaría.
      final otro = await HttpServer.bind(falsa, canalPuerto);
      await otro.close();
    });

    test('rotar el token echa a quien esté dentro', () async {
      // Y tiene que hacerlo: si las conexiones vivas sobrevivieran, rotar no
      // revocaría nada hasta la siguiente reconexión — y quien rota lo hace justo
      // porque quiere que alguien salga ya.
      final c = montar(tailscale: falsa);
      final control = c.read(channelControllerProvider.notifier);
      await control.encender();
      final antes = await tokens.read();

      await control.rotarToken();

      expect(await tokens.read(), isNot(antes));
      expect(
        c.read(channelControllerProvider),
        isA<ChannelOn>(),
        reason: 'y vuelve a escuchar, con el token nuevo',
      );
      await control.apagar();
    });
  });
}
