import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/updates/domain/entities/release_check.dart';
import 'package:nexus/features/updates/domain/repositories/release_feed.dart';
import 'package:nexus/features/updates/presentation/providers/updates_providers.dart';

// El aviso de versión nueva: **solo avisa**.
//
// No descarga ni instala, y menos aún reinicia — reiniciarse por su cuenta sería
// matar un `claude -p` a media escritura, que es lo que la ficha `le9` viene a
// impedir.
//
// Lo que se prueba aquí es lo que puede salir mal: comparar versiones como texto,
// confundir «no se pudo preguntar» con «estás al día», y preguntar a GitHub cada
// vez que vuelves a la ventana.
class _Feed implements ReleaseFeed {
  _Feed(this._tag);

  final String? _tag;
  var veces = 0;

  @override
  Future<({String tag, String url})?> latest() async {
    veces++;
    final tag = _tag;
    return tag == null
        ? null
        : (tag: tag, url: 'https://github.com/DiegoHCH/nexus/releases/tag/$tag');
  }
}

void main() {
  group('comparar versiones', () {
    test('la publicada más alta se anuncia', () {
      const c = ReleaseCheck(current: '0.0.1', latest: 'v0.0.2');
      expect(c.isNewer, isTrue);
    });

    test('la misma no', () {
      expect(
        const ReleaseCheck(current: '0.0.1', latest: 'v0.0.1').isNewer,
        isFalse,
      );
    });

    test('y una más vieja tampoco', () {
      expect(
        const ReleaseCheck(current: '0.1.0', latest: 'v0.0.9').isNewer,
        isFalse,
      );
    });

    test('la décima versión no se cuenta como menor que la novena', () {
      // Como texto, «0.0.10» < «0.0.9» porque el 1 va antes del 9: el aviso
      // habría desaparecido justo al llegar a la décima. Es el fallo clásico de
      // comparar versiones con `compareTo`.
      expect(ReleaseCheck.compare('0.0.10', '0.0.9'), greaterThan(0));
      expect(
        const ReleaseCheck(current: '0.0.9', latest: 'v0.0.10').isNewer,
        isTrue,
      );
    });

    test('una etiqueta rara no revienta, solo no destaca', () {
      expect(
        const ReleaseCheck(current: '0.0.1', latest: 'v0.0.2-beta.1').isNewer,
        isTrue,
      );
      expect(
        const ReleaseCheck(current: '0.0.1', latest: 'nightly').isNewer,
        isFalse,
      );
    });

    test('no saber no es estar al día', () {
      // `null` en `latest` es «no se pudo preguntar»: sin red, o sin ninguna
      // release publicada todavía. Decir que estás al día sería afirmar algo que
      // nadie ha comprobado.
      const c = ReleaseCheck(current: '0.0.1');
      expect(c.isNewer, isFalse);
      expect(c.latest, isNull);
    });
  });

  group('cada cuánto se pregunta', () {
    ({ProviderContainer container, _Feed feed}) montar({
      required DateTime Function() reloj,
      String? publicada = 'v0.0.2',
    }) {
      final feed = _Feed(publicada);
      final container = ProviderContainer(
        overrides: [
          releaseFeedProvider.overrideWithValue(feed),
          relojProvider.overrideWithValue(reloj),
          currentVersionProvider.overrideWith((ref) async => '0.0.1'),
        ],
      );
      addTearDown(container.dispose);
      return (container: container, feed: feed);
    }

    test('al arrancar se pregunta una vez', () async {
      var ahora = DateTime(2026, 8, 19, 10);
      final m = montar(reloj: () => ahora);
      m.container.listen(updatesControllerProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);

      expect(m.feed.veces, 1);
      expect(m.container.read(updatesControllerProvider)?.isNewer, isTrue);
    });

    test('volver a la ventana antes de 15 min no vuelve a preguntar', () async {
      // Sin el tope, cambiar de app y volver diez veces son diez peticiones.
      var ahora = DateTime(2026, 8, 19, 10);
      final m = montar(reloj: () => ahora);
      m.container.listen(updatesControllerProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);

      ahora = ahora.add(const Duration(minutes: 14));
      await m.container.read(updatesControllerProvider.notifier).alRegresar();

      expect(m.feed.veces, 1, reason: 'aún no toca');
    });

    test('y pasados los 15, sí', () async {
      var ahora = DateTime(2026, 8, 19, 10);
      final m = montar(reloj: () => ahora);
      m.container.listen(updatesControllerProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);

      ahora = ahora.add(const Duration(minutes: 16));
      await m.container.read(updatesControllerProvider.notifier).alRegresar();

      expect(m.feed.veces, 2);
    });

    test('sin releases publicadas no se anuncia nada', () async {
      // Es el estado del primer día: el endpoint contesta 404 —comprobado— y eso
      // no puede leerse como un fallo ni como una novedad.
      var ahora = DateTime(2026, 8, 19, 10);
      final m = montar(reloj: () => ahora, publicada: null);
      m.container.listen(updatesControllerProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);

      final aviso = m.container.read(updatesControllerProvider);
      expect(aviso?.isNewer, isFalse);
      expect(aviso?.current, '0.0.1');
    });
  });
}
