import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/remote/domain/channel_token.dart';
import 'package:nexus/features/remote/presentation/providers/channel_token_providers.dart';

// El token que abre el canal del teléfono.
//
// Va antes que el socket a propósito: un servidor sin token no debería existir ni
// un commit. Escuchar primero y autenticar después deja una ventana en la que
// cualquiera de la red de Tailscale entra, y esa ventana se olvida abierta.
//
// Lo que se vigila aquí son las tres cosas que fallan en silencio: un generador
// predecible que **parece** aleatorio, un token que se cuela en un registro, y un
// borrado que no borra.
class _Memoria implements ChannelTokenStore {
  ChannelToken? _guardado;
  int escrituras = 0;
  int borrados = 0;

  @override
  Future<ChannelToken?> read() async => _guardado;

  @override
  Future<void> write(ChannelToken token) async {
    _guardado = token;
    escrituras++;
  }

  @override
  Future<void> clear() async {
    _guardado = null;
    borrados++;
  }
}

void main() {
  group('cómo se genera', () {
    test('256 bits, en 43 caracteres seguros para URL', () {
      final t = ChannelToken.generar();
      // Sin relleno: 32 bytes en base64 son 43 caracteres y un `=`.
      expect(t.value.length, 43);
      expect(t.value, isNot(contains('=')));
      // El alfabeto seguro para URL: nada que haya que escapar en ninguna capa.
      expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(t.value), isTrue);
      // Y de verdad son 32 bytes al decodificarlo.
      expect(base64Url.decode('${t.value}=').length, ChannelToken.bytes);
    });

    test('dos tokens no se parecen', () {
      // No demuestra que sea seguro —eso lo da `Random.secure()`— pero sí caza el
      // error de generar una constante, o de sembrar el generador con algo fijo.
      final muchos = {
        for (var i = 0; i < 200; i++) ChannelToken.generar().value,
      };
      expect(muchos.length, 200, reason: 'hubo repetición en 200 intentos');
    });

    test('un generador sembrado da lo mismo, y por eso no se usa', () {
      // La prueba de que la elección importa: con `Random(1)` el token es
      // reproducible. Es exactamente el fallo que no se nota nunca, porque el
      // token *parece* aleatorio.
      final a = ChannelToken.generar(Random(1));
      final b = ChannelToken.generar(Random(1));
      expect(
        a,
        b,
        reason: 'sembrado es predecible: de ahí que se use Random.secure',
      );
      expect(ChannelToken.generar(), isNot(a));
    });
  });

  group('no se escribe en los registros', () {
    test('toString enseña la huella y no el secreto', () {
      // Esta app registra mucho, y la interpolación de Dart llama a `toString` sin
      // avisar. Un `String` desnudo se cuela el día que alguien escriba
      // `debugPrint('token: $token')` de buena fe — y ese registro se queda en el
      // disco.
      final t = ChannelToken.generar();
      final impreso = '$t';
      expect(
        impreso.contains(t.value),
        isFalse,
        reason:
            'el valor entero apareció en toString: eso acaba en un registro',
      );
      expect(impreso, contains(t.fingerprint));
      expect(impreso, startsWith('ChannelToken('));
    });

    test('la huella no acerca a adivinarlo', () {
      final t = ChannelToken.generar();
      expect(t.fingerprint.length, 7, reason: 'seis caracteres y el puntito');
      expect(t.value, startsWith(t.fingerprint.substring(0, 6)));
    });

    test('y con un token corto tampoco lo suelta', () {
      // El borde: un token de tres caracteres no puede acabar impreso entero por
      // culpa de un `substring`.
      const t = ChannelToken('abc');
      expect('$t'.contains('abc'), isFalse);
    });
  });

  group('guardar, leer y rotar', () {
    test('lo que se guarda se lee', () async {
      final store = _Memoria();
      final t = ChannelToken.generar();
      await store.write(t);
      expect(await store.read(), t);
    });

    test('sin token, null — y eso no es un error', () async {
      // Es el estado del primer arranque, y lo que la comprobación tiene que
      // convertir en «genera uno», no en un fallo.
      expect(await _Memoria().read(), isNull);
    });

    test('rotar reemplaza, y el viejo deja de valer', () async {
      final store = _Memoria();
      final viejo = ChannelToken.generar();
      await store.write(viejo);
      final nuevo = ChannelToken.generar();
      await store.write(nuevo);

      expect(await store.read(), nuevo);
      expect(
        await store.read(),
        isNot(viejo),
        reason:
            'rotar invalida todos los teléfonos de golpe, que es lo decidido',
      );
    });

    test('borrar deja el canal sin token, y eso es lo correcto', () async {
      // Mejor un canal que no acepta a nadie que uno que acepta con un token que
      // se quiso revocar.
      final store = _Memoria();
      await store.write(ChannelToken.generar());
      await store.clear();
      expect(await store.read(), isNull);
      expect(store.borrados, 1);
    });
  });

  group('el controlador', () {
    ProviderContainer montar(_Memoria store) {
      final c = ProviderContainer(
        overrides: [channelTokenStoreProvider.overrideWithValue(store)],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('asegurar genera uno si no hay', () async {
      final store = _Memoria();
      final c = montar(store);
      final t = await c
          .read(channelTokenControllerProvider.notifier)
          .asegurar();
      expect(t.value.length, 43);
      expect(await store.read(), t);
    });

    test('y NO lo rota si ya existe', () async {
      // El fallo que esto evita: llamar a `asegurar()` al arrancar el servidor
      // —que es cuando se llamará— no puede invalidar el teléfono que ya estaba
      // emparejado. Sería un canal que se rompe solo en cada reinicio.
      final store = _Memoria();
      final viejo = ChannelToken.generar();
      await store.write(viejo);
      final c = montar(store);

      expect(
        await c.read(channelTokenControllerProvider.notifier).asegurar(),
        viejo,
      );
      expect(store.escrituras, 1, reason: 'no debería haber escrito otra vez');
    });

    test('rotar sí lo cambia', () async {
      final store = _Memoria();
      final viejo = ChannelToken.generar();
      await store.write(viejo);
      final c = montar(store);

      final nuevo = await c
          .read(channelTokenControllerProvider.notifier)
          .rotar();
      expect(nuevo, isNot(viejo));
      expect(await store.read(), nuevo);
    });

    test('revocar deja el canal cerrado', () async {
      final store = _Memoria();
      await store.write(ChannelToken.generar());
      final c = montar(store);
      await c.read(channelTokenControllerProvider.notifier).revocar();
      expect(await store.read(), isNull);
    });
  });
}
