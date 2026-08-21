import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/nexus_theme.dart';
import 'package:nexus/features/remote/data/channel_link.dart';
import 'package:nexus/features/remote/domain/channel_token.dart';
import 'package:nexus/features/remote/domain/pairing.dart';
import 'package:nexus/features/remote/presentation/pages/pairing_page.dart';
import 'package:nexus/features/remote/presentation/providers/pairing_providers.dart';
import 'package:nexus/features/remote/presentation/widgets/link_badge.dart';

// Emparejar a mano, que es la primera forma y no un apaño mientras llega el QR: el
// QR transporta estos mismos dos valores y solo ahorra teclearlos.

/// Un token con la pinta de uno de verdad: 43 caracteres.
const tokenBueno = 'MDEyMzQ1Njc4OWFiY2RlZmdoaWprbG1ub3BxcnN0dXZ3';

class _Memoria implements PairingStore {
  Pairing? guardado;
  var escrituras = 0;
  var borrados = 0;

  @override
  Future<Pairing?> read() async => guardado;
  @override
  Future<void> write(Pairing pairing) async {
    guardado = pairing;
    escrituras++;
  }

  @override
  Future<void> clear() async {
    guardado = null;
    borrados++;
  }
}

class _SocketQueNoAbre implements ChannelSocket {
  @override
  Stream<String> get entrantes => const Stream.empty();
  @override
  void enviar(String texto) {}
  @override
  Future<void> close() async {}
}

void main() {
  group('leer lo que se pegó', () {
    test('una dirección y un token buenos quedan emparejados', () {
      final leido = leerEmparejamiento(
        url: 'ws://100.101.102.103:7845',
        token: tokenBueno,
      );

      expect(leido.problema, isNull);
      expect(leido.emparejamiento!.comoSeVe, '100.101.102.103:7845');
    });

    test('los espacios de copiar y pegar no cuentan', () {
      // Copiar de una pantalla arrastra espacios y saltos de línea casi siempre, y
      // fallar por eso sería fallar por algo que no hizo nadie.
      final leido = leerEmparejamiento(
        url: '  ws://100.64.0.1:7845\n',
        token: ' $tokenBueno ',
      );
      expect(leido.problema, isNull);
    });

    test('la dirección a secas vale: se le pone el ws://', () {
      // Lo que se copia del Mac lleva el esquema, pero lo que se teclea de memoria es
      // la dirección y el puerto. Exigir el `ws://` era una regla mía, no del canal.
      final leido = leerEmparejamiento(
        url: '100.73.35.55:7845',
        token: tokenBueno,
      );

      expect(leido.problema, isNull);
      expect(leido.emparejamiento!.comoSeVe, '100.73.35.55:7845');
      expect(leido.emparejamiento!.url.scheme, 'ws');
    });

    test('y sigue avisando si esa dirección no es de Tailscale', () {
      // El aviso tiene que sobrevivir a completar el esquema: si al añadir `ws://` se
      // perdiera la comprobación, se habría cambiado un mensaje útil por otro.
      final leido = leerEmparejamiento(
        url: '192.168.1.40:7845',
        token: tokenBueno,
      );
      expect(leido.problema, isNull);
      expect(fueraDeTailscale(leido.emparejamiento!.url), isTrue);
    });

    test('pegar la del navegador se dice como lo que es', () {
      final leido = leerEmparejamiento(
        url: 'http://100.64.0.1:7845',
        token: tokenBueno,
      );
      expect(leido.problema, PairingProblem.esquemaEquivocado);
    });

    test('sin puerto es su propio error', () {
      // Aparte y no «ilegible»: una URL sin puerto se conectaría al 80, que no es
      // donde está el canal, y el mensaje tiene que poder decir el número.
      final leido = leerEmparejamiento(
        url: 'ws://100.64.0.1',
        token: tokenBueno,
      );
      expect(leido.problema, PairingProblem.faltaElPuerto);
    });

    test('un token a medias se atrapa antes de intentar conectar', () {
      final leido = leerEmparejamiento(
        url: 'ws://100.64.0.1:7845',
        token: 'MDEyMzQ1',
      );
      expect(leido.problema, PairingProblem.tokenCorto);
    });

    test('lo ilegible es ilegible', () {
      final leido = leerEmparejamiento(
        url: 'esto no es una url',
        token: tokenBueno,
      );
      expect(leido.problema, PairingProblem.urlIlegible);
    });
  });

  group('el aviso de Tailscale avisa y no bloquea', () {
    test('una del rango de Tailscale no avisa', () {
      expect(fueraDeTailscale(Uri.parse('ws://100.64.0.1:7845')), isFalse);
      expect(fueraDeTailscale(Uri.parse('ws://100.127.255.255:7845')), isFalse);
    });

    test('una del wifi de casa sí avisa', () {
      expect(fueraDeTailscale(Uri.parse('ws://192.168.1.40:7845')), isTrue);
    });

    test('100.0.x y 100.128.x avisan: son direcciones públicas', () {
      // El rango es /10 y no /8. Confundirlos es exactamente cómo se acaba
      // aceptando como «privada» una dirección de internet.
      expect(fueraDeTailscale(Uri.parse('ws://100.0.0.1:7845')), isTrue);
      expect(fueraDeTailscale(Uri.parse('ws://100.128.0.1:7845')), isTrue);
    });

    test('de un nombre de máquina no se opina', () {
      // Clasificarlo exigiría resolverlo, y resolver para poder avisar sería hacer
      // red antes de conectar.
      expect(fueraDeTailscale(Uri.parse('ws://mi-mac.ts.net:7845')), isFalse);
    });

    test('y una dirección de fuera SÍ se puede guardar', () async {
      // Avisar ayuda; bloquear adivina. La política de «solo Tailscale» la impone el
      // Mac, que es quien decide dónde escucha: repetirla aquí serían dos copias de
      // la misma regla, y el día que el Mac cambie de criterio este teléfono se
      // quedaría negándose sin motivo.
      final store = _Memoria();
      final c = ProviderContainer(
        overrides: [pairingStoreProvider.overrideWithValue(store)],
      );
      addTearDown(c.dispose);
      await c.read(pairingControllerProvider.future);

      final problema = await c
          .read(pairingControllerProvider.notifier)
          .emparejar(url: 'ws://192.168.1.40:7845', token: tokenBueno);

      expect(problema, isNull);
      expect(store.guardado, isNotNull);
    });
  });

  group('guardar y olvidar', () {
    ProviderContainer montar(_Memoria store) {
      final c = ProviderContainer(
        overrides: [
          pairingStoreProvider.overrideWithValue(store),
          socketOpenerProvider.overrideWithValue(
            (_) async => _SocketQueNoAbre(),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('nace sin emparejar', () async {
      final c = montar(_Memoria());
      expect(await c.read(pairingControllerProvider.future), isNull);
    });

    test('lo guardado se recuerda al arrancar', () async {
      final store = _Memoria()
        ..guardado = Pairing(
          url: Uri.parse('ws://100.64.0.1:7845'),
          token: const ChannelToken(tokenBueno),
        );
      final c = montar(store);

      final pareja = await c.read(pairingControllerProvider.future);
      expect(pareja!.comoSeVe, '100.64.0.1:7845');
    });

    test('un problema no escribe nada', () async {
      final store = _Memoria();
      final c = montar(store);
      await c.read(pairingControllerProvider.future);

      await c
          .read(pairingControllerProvider.notifier)
          .emparejar(url: 'no-va', token: tokenBueno);

      // Guardar algo que no sirve deja al teléfono creyéndose emparejado con nada, y
      // eso se ve como «no responde» en vez de como «lo pegaste mal».
      expect(store.escrituras, 0);
    });

    test('olvidar borra el secreto', () async {
      final store = _Memoria()
        ..guardado = Pairing(
          url: Uri.parse('ws://100.64.0.1:7845'),
          token: const ChannelToken(tokenBueno),
        );
      final c = montar(store);
      await c.read(pairingControllerProvider.future);

      await c.read(pairingControllerProvider.notifier).olvidar();

      expect(store.borrados, 1);
      expect(c.read(pairingControllerProvider).value, isNull);
    });
  });

  group('el token no se enseña entero', () {
    test('ni en la huella ni en el toString', () {
      final pareja = Pairing(
        url: Uri.parse('ws://100.64.0.1:7845'),
        token: const ChannelToken(tokenBueno),
      );

      // El mismo criterio que en el Mac: se enseña la huella. Aquí importa igual,
      // porque un `toString` acaba en un registro sin que nadie lo decida.
      expect(pareja.toString(), isNot(contains(tokenBueno)));
      expect(pareja.token.fingerprint.length, lessThan(10));
    });
  });

  group('la pantalla', () {
    Widget app(ProviderContainer c) => UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: NexusTheme.dark(), home: const PairingPage()),
    );

    ProviderContainer montar(_Memoria store) {
      final c = ProviderContainer(
        overrides: [pairingStoreProvider.overrideWithValue(store)],
      );
      addTearDown(c.dispose);
      return c;
    }

    testWidgets('un error se dice en pantalla y no se guarda', (tester) async {
      final store = _Memoria();
      final c = montar(store);
      await tester.pumpWidget(app(c));

      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('campo-url')),
          matching: find.byType(TextField),
        ),
        'http://100.64.0.1:7845',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('campo-token')),
          matching: find.byType(TextField),
        ),
        tokenBueno,
      );
      await tester.tap(find.byKey(const ValueKey('emparejar')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('problema')), findsOneWidget);
      expect(store.escrituras, 0);
    });

    testWidgets('el aviso de Tailscale sale mientras se escribe', (
      tester,
    ) async {
      final c = montar(_Memoria());
      await tester.pumpWidget(app(c));

      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('campo-url')),
          matching: find.byType(TextField),
        ),
        'ws://192.168.1.40:7845',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('campo-token')),
          matching: find.byType(TextField),
        ),
        tokenBueno,
      );
      await tester.pump();

      // Antes de pulsar nada: llegar a «no conecta» y enterarse entonces es el
      // camino largo.
      expect(find.byKey(const ValueKey('aviso-tailscale')), findsOneWidget);
    });

    testWidgets('lo bueno se guarda', (tester) async {
      final store = _Memoria();
      final c = montar(store);
      await tester.pumpWidget(app(c));

      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('campo-url')),
          matching: find.byType(TextField),
        ),
        'ws://100.64.0.1:7845',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('campo-token')),
          matching: find.byType(TextField),
        ),
        tokenBueno,
      );
      await tester.tap(find.byKey(const ValueKey('emparejar')));
      await tester.pumpAndSettle();

      expect(store.escrituras, 1);
      expect(find.byKey(const ValueKey('problema')), findsNothing);
    });
  });

  group('el estado de la conexión se dice', () {
    testWidgets('cada estado tiene su propio texto', (tester) async {
      // «Reconectando» y «sin conexión» significan las dos que ahora no hay Mac,
      // pero una es «el teléfono está en ello» y la otra «mira si está encendido».
      // Un solo mensaje para las dos manda a comprobar cosas mientras se arreglaba
      // solo.
      final dichos = <String>{};
      for (final estado in LinkState.values) {
        final c = ProviderContainer(
          overrides: [
            linkStateProvider.overrideWith((ref) => Stream.value(estado)),
          ],
        );
        addTearDown(c.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: c,
            child: MaterialApp(
              theme: NexusTheme.dark(),
              home: const Scaffold(body: LinkBadge()),
            ),
          ),
        );
        await tester.pump();
        final texto = tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const ValueKey('estado-del-enlace')),
                matching: find.byType(Text),
              ),
            )
            .data!;
        dichos.add(texto);
      }

      expect(
        dichos.length,
        LinkState.values.length,
        reason: 'ningún par de estados comparte mensaje',
      );
    });
  });
}
