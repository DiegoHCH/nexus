import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/accent_preference.dart';
import 'package:nexus/core/design_system/nexus_colors.dart';

// El acento se elige, y ninguna elección puede quedar ilegible.
//
// Esto es lo que hace que la paleta pueda existir sin miedo: el acento se pinta
// sobre tres fondos en cada tema, y una rueda de color libre dejaría la mitad de
// las elecciones sin contraste en uno de los dos. Con opciones calibradas a mano,
// lo único que hace falta es **comprobar la calibración**.
//
// Y al escribir esto salió un defecto que ya estaba publicado: el acento del tema
// claro era `#0C7C88` con un comentario que decía «por contraste AA», y medía
// **4,23** contra el fondo `void` claro — por debajo del 4,5 que pide AA. Contra
// el blanco de `deep` sí pasaba (4,94), que debió de ser lo que se midió. Ahora
// está en `#0B7480`, que da 4,71 contra el peor de los tres.
void main() {
  /// Luminancia relativa de WCAG 2.1.
  double luminancia(Color c) {
    double canal(double v) =>
        v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * canal(c.r) + 0.7152 * canal(c.g) + 0.0722 * canal(c.b);
  }

  double contraste(Color a, Color b) {
    final la = luminancia(a);
    final lb = luminancia(b);
    final alto = math.max(la, lb);
    final bajo = math.min(la, lb);
    return (alto + 0.05) / (bajo + 0.05);
  }

  /// Los tres fondos sobre los que aparece el acento en cada tema.
  ({String nombre, List<Color> fondos}) fondosDe(NexusColors c, String nombre) =>
      (nombre: nombre, fondos: [c.void_, c.deep, c.rise]);

  test('la medida de contraste es la de WCAG, comprobada con los extremos', () {
    // Sin esto, un error en la fórmula haría que las pruebas de abajo pasaran
    // midiendo cualquier cosa. Blanco sobre negro es 21:1 por definición.
    expect(
      contraste(const Color(0xFFFFFFFF), const Color(0xFF000000)),
      closeTo(21, 0.01),
    );
    expect(
      contraste(const Color(0xFF808080), const Color(0xFF808080)),
      closeTo(1, 0.01),
    );
  });

  for (final opcion in AccentChoice.values) {
    test('el acento ${opcion.name} se lee en los dos temas', () {
      for (final tema in [
        fondosDe(NexusColors.dark, 'oscuro'),
        fondosDe(NexusColors.light, 'claro'),
      ]) {
        final color = opcion.forBrightness(
          tema.nombre == 'oscuro' ? Brightness.dark : Brightness.light,
        );
        for (final fondo in tema.fondos) {
          final medida = contraste(color, fondo);
          expect(
            medida,
            greaterThanOrEqualTo(4.5),
            reason:
                'el acento ${opcion.name} da ${medida.toStringAsFixed(2)}:1 sobre '
                'un fondo del tema ${tema.nombre}, y AA pide 4,5. Un acento que no '
                'se lee no es una opción, es una trampa.',
          );
        }
      }
    });
  }

  test('el acento por defecto de la paleta es el cian de la lista', () {
    // Son dos sitios con el mismo valor —la paleta y la opción— y podrían
    // separarse sin que nada fallara: el tema sin acento explícito usaría uno y
    // la paleta enseñaría otro, así que el círculo marcado no coincidiría con lo
    // que se ve pintado.
    expect(NexusColors.dark.accent, AccentChoice.cyan.dark);
    expect(NexusColors.light.accent, AccentChoice.cyan.light);
  });

  test('lo guardado sobrevive a un nombre que ya no existe', () {
    expect(AccentChoice.fromStored('violet'), AccentChoice.violet);
    // Si algún día se retira un color, quien lo tuviera elegido no debe quedarse
    // sin app: cae al de siempre.
    expect(AccentChoice.fromStored('turquesa-de-2019'), AccentChoice.cyan);
    expect(AccentChoice.fromStored(null), AccentChoice.cyan);
  });
}
