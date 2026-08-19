import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/accent_preference.dart';
import 'package:nexus/core/design_system/nexus_colors.dart';

// El acento se elige en una rueda, y nada de lo que se pueda elegir puede quedar
// ilegible.
//
// La primera versión ofrecía seis colores fijos y bastaba comprobar seis pares. Al
// abrir la rueda entera esa prueba dejó de servir, y lo que hay que comprobar es
// **más fuerte**: que la regla que ajusta el brillo cumpla para toda la rueda —
// incluidos los sitios donde es difícil, que son un amarillo purísimo sobre fondo
// claro y un azul oscuro sobre el vacío.
//
// Se barre en malla y no con casos elegidos a mano: elegir los casos yo mismo es
// elegir los que sé que pasan.
void main() {
  const fondosOscuros = [
    NexusColors.dark,
  ];

  test('la medida de contraste es la de WCAG, comprobada con los extremos', () {
    // Sin esto, un error en la fórmula haría que todo lo de abajo pasara midiendo
    // cualquier cosa. Blanco sobre negro es 21:1 por definición.
    expect(
      Accent.contrast(const Color(0xFFFFFFFF), const Color(0xFF000000)),
      closeTo(21, 0.01),
    );
    expect(
      Accent.contrast(const Color(0xFF808080), const Color(0xFF808080)),
      closeTo(1, 0.01),
    );
  });

  group('toda la rueda se lee, en los dos temas', () {
    /// Los tres fondos de cada tema. Se comprueban los tres y no uno: en claro
    /// `deep` es blanco puro y `void` es azulado, y un tono puede pasar contra uno
    /// y fallar contra el otro — le pasaba al cian que ya estaba publicado.
    List<Color> fondos(Brightness b) {
      final p = b == Brightness.dark ? NexusColors.dark : NexusColors.light;
      return [p.void_, p.deep, p.rise];
    }

    for (final brillo in [Brightness.dark, Brightness.light]) {
      test('en ${brillo.name}, barriendo matiz, saturación y brillo', () {
        final fallos = <String>[];
        var probados = 0;

        for (var h = 0; h < 360; h += 15) {
          for (final s in [0.15, 0.45, 0.75, 1.0]) {
            for (final v in [0.25, 0.55, 0.85, 1.0]) {
              final elegido = HSVColor.fromAHSV(1, h.toDouble(), s, v).toColor();
              final pintado = Accent(elegido).forBrightness(brillo);
              probados++;

              for (final fondo in fondos(brillo)) {
                final medida = Accent.contrast(pintado, fondo);
                if (medida < Accent.minimoAA) {
                  fallos.add(
                    'h$h s$s v$v → ${medida.toStringAsFixed(2)}:1',
                  );
                }
              }
            }
          }
        }

        expect(probados, 384, reason: 'la malla dejó de barrer lo que decía');
        expect(
          fallos,
          isEmpty,
          reason:
              '${fallos.length} de $probados colores quedan por debajo de '
              '${Accent.minimoAA}:1 en tema ${brillo.name}. Una rueda que deja '
              'elegir algo ilegible no es libertad, es una trampa. '
              'Primeros: ${fallos.take(5).join(' · ')}',
        );
      });
    }

    test('el matiz elegido no se toca, solo el brillo', () {
      // Es la promesa que hace la pantalla: «se ajusta el brillo, no el color».
      // Si el ajuste moviera el matiz, el violeta elegido saldría azul y la
      // explicación de Ajustes sería mentira.
      for (var h = 0; h < 360; h += 15) {
        final elegido = HSVColor.fromAHSV(1, h.toDouble(), 0.8, 0.6).toColor();
        for (final brillo in [Brightness.dark, Brightness.light]) {
          final pintado = Accent(elegido).forBrightness(brillo);
          final antes = HSLColor.fromColor(elegido);
          final despues = HSLColor.fromColor(pintado);
          // Un grado de margen por el redondeo a enteros de 8 bits al convertir.
          expect(
            (despues.hue - antes.hue).abs(),
            lessThan(1.5),
            reason: 'el matiz $h se movió a ${despues.hue} en ${brillo.name}',
          );
        }
      }
    });

    test('un color que ya se lee se deja como está', () {
      // El ajuste avanza en pasos y se queda en el primero que cumple, así que un
      // color que ya cumple no debería moverse ni un paso: cada paso lo aleja de
      // lo que se eligió.
      const cian = Accent(Color(0xFF56E1EA));
      expect(cian.forBrightness(Brightness.dark), cian.chosen);
    });
  });

  group('lo que se guarda y lo que se enseña', () {
    test('el color vuelve tal como se guardó', () {
      const elegido = Color(0xFFB79BFF);
      expect(
        AccentController.leer(elegido.toARGB32().toString()).chosen,
        elegido,
      );
    });

    test('los nombres de la primera versión siguen valiendo', () {
      // Hubo una versión con seis colores por nombre, y está instalada en esta
      // máquina: quien eligiera violeta no debe encontrarse cian sin explicación.
      expect(AccentController.leer('violet').chosen, const Color(0xFFB79BFF));
      expect(AccentController.leer('amber').chosen, const Color(0xFFF5C451));
    });

    test('lo que no se entiende cae al cian', () {
      expect(AccentController.leer(null), Accent.cyan);
      expect(AccentController.leer('turquesa-de-2019'), Accent.cyan);
    });

    test('el nombre sale del matiz, y un gris no se llama rojo', () {
      // Con la saturación a cero el ángulo del matiz existe pero no significa
      // nada: sin el atajo del gris, un gris se anunciaría como «rojo» porque su
      // matiz calculado es 0.
      expect(const Accent(Color(0xFF808080)).name, AccentName.grey);
      expect(const Accent(Color(0xFFB79BFF)).name, AccentName.violet);
      expect(const Accent(Color(0xFF56E1EA)).name, AccentName.cyan);
      expect(const Accent(Color(0xFFE53935)).name, AccentName.red);
    });

    test('el hexadecimal se enseña como se escribe', () {
      expect(const Accent(Color(0xFF56E1EA)).hex, '#56E1EA');
      // Con ceros por delante, que es donde se pierde un dígito si se olvida
      // rellenar.
      expect(const Accent(Color(0xFF0B7480)).hex, '#0B7480');
    });
  });

  test('el acento por defecto de la paleta es el de la clase', () {
    // Dos sitios con el mismo valor que podrían separarse sin que nada fallara: el
    // tema sin acento explícito usaría uno y la rueda arrancaría en otro.
    expect(NexusColors.dark.accent, Accent.cyan.chosen);
    expect(fondosOscuros.first.accent, Accent.cyan.chosen);
  });
}
