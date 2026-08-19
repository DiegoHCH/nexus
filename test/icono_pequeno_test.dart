import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

// Que el cian llegue **como cian** en los tamaños pequeños.
//
// El icono de 16 px se veía gris, y no era opacidad: el aro ya se dibujaba a
// opacidad total. Los grosores estaban calibrados «a 4096» mientras los tamaños
// pequeños se dibujan en un lienzo de 256, así que al reducir el aro acababa
// midiendo **0,14 píxeles finales** y se promediaba con la placa. Medido antes
// del arreglo: el píxel más brillante era (15, 37, 43).
//
// Esto lee los PNG que se compilan de verdad en la app, no la salida del
// generador: lo que importa es lo que acaba dentro del `.app`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const accent = (86, 225, 234); // #56E1EA, el acento de la paleta
  const carpeta = 'macos/Runner/Assets.xcassets/AppIcon.appiconset';

  Future<List<(int, int, int)>> pixeles(int lado) async {
    final bytes = File('$carpeta/app_icon_$lado.png').readAsBytesSync();
    final codec = await ui.instantiateImageCodec(bytes);
    final imagen = (await codec.getNextFrame()).image;
    final datos = await imagen.toByteData(format: ui.ImageByteFormat.rawRgba);

    return [
      for (var i = 0; i < datos!.lengthInBytes; i += 4)
        (datos.getUint8(i), datos.getUint8(i + 1), datos.getUint8(i + 2)),
    ];
  }

  double brillo((int, int, int) p) =>
      0.2126 * p.$1 + 0.7152 * p.$2 + 0.0722 * p.$3;

  for (final lado in [16, 32]) {
    test('a $lado px el cian llega como cian', () async {
      final px = await pixeles(lado);
      expect(px, isNotEmpty, reason: 'no se pudo leer el PNG del icono');

      final masBrillante = px.reduce((a, b) => brillo(a) > brillo(b) ? a : b);

      // Cerca del acento de verdad. Antes del arreglo esto era (15, 37, 43): un
      // gris azulado que en la lista del Finder no se distingue del fondo.
      expect(
        (masBrillante.$1 - accent.$1).abs() +
            (masBrillante.$2 - accent.$2).abs() +
            (masBrillante.$3 - accent.$3).abs(),
        lessThan(40),
        reason:
            'el píxel más brillante es $masBrillante y debería acercarse a '
            '$accent: el trazo se está perdiendo al reducir',
      );
    });

    test('y a $lado px sigue siendo un aro, no un disco', () async {
      // El otro lado del mismo mando: engordar el trazo hasta que el cian llegue
      // es fácil, y pasarse convierte la esfera en una mancha. Ya ocurrió con el
      // contraste del orbe, donde subir el halo mejoraba la medida y empeoraba
      // lo que se ve.
      final px = await pixeles(lado);
      final conCian = px
          .where((p) => p.$2 > p.$1 + 12 && p.$3 > p.$1 + 12)
          .length;

      expect(
        conCian / px.length,
        lessThan(0.45),
        reason:
            'el ${(100 * conCian / px.length).round()} % del icono es cian: '
            'a este tamaño eso ya no se lee como una esfera',
      );
      expect(
        conCian / px.length,
        greaterThan(0.05),
        reason: 'y algo tiene que verse',
      );
    });
  }
}
