import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/emulators/domain/usecases/el_espejo_del_iphone.dart';

/// Ver un iPhone físico con lo que trae macOS.
///
/// **No hay scrcpy para iOS y no puede haberlo**: el sistema no deja inyectar
/// eventos desde fuera ni exponer la pantalla a un cliente cualquiera. Así que aquí
/// no se elige entre construir y lanzar — solo se puede lanzar.
void main() {
  test('cada forma se abre por el nombre de su app', () {
    expect(ElEspejoDelIphone.argumentos(ComoVerElIphone.duplicado), [
      '-a',
      'iPhone Mirroring',
    ]);
    expect(ElEspejoDelIphone.argumentos(ComoVerElIphone.quickTime), [
      '-a',
      'QuickTime Player',
    ]);
  });

  group('qué se puede ofrecer', () {
    test('con las dos apps, las dos', () {
      expect(
        ElEspejoDelIphone.lasQueHay(existe: (_) => true),
        ComoVerElIphone.values,
      );
    });

    test('sin Duplicado, solo QuickTime', () {
      // Duplicado de iPhone llegó en macOS 15. En una anterior ese botón solo
      // podría fallar, así que no se pinta.
      final hay = ElEspejoDelIphone.lasQueHay(
        existe: (ruta) => !ruta.contains('iPhone Mirroring'),
      );

      expect(hay, [ComoVerElIphone.quickTime]);
    });

    test('sin ninguna de las dos, ninguna', () {
      expect(ElEspejoDelIphone.lasQueHay(existe: (_) => false), isEmpty);
    });
  });

  test('las rutas son las de las apps del sistema', () {
    // Si alguien cambia el mapa, esto lo dice: es lo único que puede romperse al
    // editar aquí, porque `Directory` no se está probando.
    expect(
      ElEspejoDelIphone.donde[ComoVerElIphone.duplicado],
      '/System/Applications/iPhone Mirroring.app',
    );
    expect(
      ElEspejoDelIphone.donde[ComoVerElIphone.quickTime],
      '/System/Applications/QuickTime Player.app',
    );
  });
}
