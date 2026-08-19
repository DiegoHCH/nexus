import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'nexus_colors.dart';

/// El acento de la app: cualquiera, elegido en una rueda de color.
///
/// Empezó siendo seis colores fijos y era demasiado poco: el acento es lo único
/// de la paleta que es **identidad y no información** —los `ok`/`warn`/`err` son
/// señal y no se eligen nunca, un «correcto» morado no querría decir nada— así
/// que no hay motivo para ofrecer una lista cerrada.
///
/// El problema de la libertad total es real y estaba medido: el acento se pinta
/// sobre tres fondos en cada tema, y un tono elegido a gusto sobre el vacío puede
/// quedar **ilegible en el tema claro**, o al revés. La primera versión lo
/// resolvía limitando la elección a seis pares calibrados a mano.
///
/// Esto lo resuelve mejor, sin quitar nada: **se elige el color y la app le busca
/// el brillo**. Matiz y saturación son de quien elige y no se tocan —son lo que
/// hace que un color sea «ese color»—; la luminosidad se mueve lo justo para
/// cumplir contraste AA sobre los fondos del tema que toque. Así el violeta que
/// elijas sigue siendo tu violeta en oscuro y en claro, y en los dos se lee.
@immutable
class Accent {
  const Accent(this.chosen);

  /// Lo que se eligió en la rueda, tal cual. Es lo que se enseña marcado allí.
  final Color chosen;

  static const cyan = Accent(Color(0xFF56E1EA));

  /// El contraste mínimo que se exige: el de AA para texto normal.
  ///
  /// 4,5 y no 3 —el de «componente de interfaz»— porque el acento **también es
  /// texto**: el número de versión, los datos del cupo y los rótulos de los
  /// botones se pintan con él.
  static const minimoAA = 4.5;

  /// El tono con el que se pinta en un tema, ya ajustado para que se lea.
  Color forBrightness(Brightness brightness) {
    final paleta = brightness == Brightness.dark
        ? NexusColors.dark
        : NexusColors.light;
    return _legible(
      chosen,
      fondos: [paleta.void_, paleta.deep, paleta.rise],
      aclarar: brightness == Brightness.dark,
    );
  }

  /// Sube o baja la luminosidad hasta que el color se lea sobre **todos** los
  /// fondos, conservando matiz y saturación.
  ///
  /// Contra los tres y no contra uno: en el tema claro `deep` es blanco puro y
  /// `void` es azulado, y un tono puede pasar contra uno y fallar contra el otro
  /// — le pasaba al cian que ya estaba publicado, que cumplía contra el blanco y
  /// se quedaba en 4,23 contra el otro.
  ///
  /// En pasos pequeños y en una dirección, no por bisección: hay que quedarse en
  /// **el primero que cumple**, porque cada paso más aleja el color de lo que se
  /// eligió. Bisecar daría un tono válido pero innecesariamente lavado.
  static Color _legible(
    Color elegido, {
    required List<Color> fondos,
    required bool aclarar,
  }) {
    final hsl = HSLColor.fromColor(elegido);
    for (var i = 0; i <= 100; i++) {
      final l = (aclarar ? hsl.lightness + i / 100 : hsl.lightness - i / 100)
          .clamp(0.0, 1.0);
      final candidato = hsl.withLightness(l).toColor();
      if (fondos.every((f) => contrast(candidato, f) >= minimoAA)) {
        return candidato;
      }
      // Al llegar al extremo no queda nada que probar. No debería ocurrir —el
      // extremo opuesto al fondo siempre contrasta— pero un bucle que confía en
      // eso y se equivoca cuelga la app.
      if (l == 0.0 || l == 1.0) return candidato;
    }
    return elegido;
  }

  /// Luminancia relativa de WCAG 2.1.
  static double luminance(Color c) {
    double canal(double v) =>
        v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * canal(c.r) + 0.7152 * canal(c.g) + 0.0722 * canal(c.b);
  }

  /// La razón de contraste entre dos colores, de 1 a 21.
  static double contrast(Color a, Color b) {
    final la = luminance(a);
    final lb = luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  /// `#RRGGBB`, para enseñarlo y para mandarlo al lado nativo.
  String get hex =>
      '#${(chosen.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  /// Cómo se llama, más o menos.
  ///
  /// Aproximado a propósito, y por el matiz: nombrar un color con exactitud es
  /// imposible y no hace falta. Sirve para tener algo que decir en voz alta —«lo
  /// puse violeta»— y para que un lector de pantalla anuncie algo que no sea un
  /// número hexadecimal.
  ///
  /// Los grises se resuelven **antes** que el matiz: con la saturación a cero el
  /// ángulo existe pero no significa nada, y sin este atajo un gris se anunciaría
  /// como «rojo».
  AccentName get name {
    final hsl = HSLColor.fromColor(chosen);
    if (hsl.saturation < 0.12) return AccentName.grey;
    final h = hsl.hue % 360;
    return switch (h) {
      < 15 || >= 345 => AccentName.red,
      < 40 => AccentName.orange,
      < 65 => AccentName.amber,
      < 90 => AccentName.lime,
      < 150 => AccentName.green,
      < 175 => AccentName.emerald,
      < 195 => AccentName.cyan,
      < 225 => AccentName.blue,
      < 255 => AccentName.indigo,
      < 285 => AccentName.violet,
      < 315 => AccentName.magenta,
      _ => AccentName.rose,
    };
  }

  @override
  bool operator ==(Object other) => other is Accent && other.chosen == chosen;

  @override
  int get hashCode => chosen.hashCode;
}

/// Los nombres posibles. Los textos viven en el diccionario, como todo lo que se
/// lee: esto es solo la lista.
enum AccentName {
  red,
  orange,
  amber,
  lime,
  green,
  emerald,
  cyan,
  blue,
  indigo,
  violet,
  magenta,
  rose,
  grey,
}

/// El acento elegido, recordado entre arranques.
///
/// Arranca en el cian mientras se lee la preferencia, por lo mismo que el tema:
/// son unos milisegundos, y es mejor pintar el de siempre y corregir que
/// parpadear desde un color que nadie eligió.
class AccentController extends Notifier<Accent> {
  static const _key = 'accent';

  @override
  Accent build() {
    unawaited(cargar());
    return Accent.cyan;
  }

  Future<void> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    state = leer(prefs.getString(_key));
  }

  /// Lo guardado, o el cian.
  ///
  /// Acepta también los nombres de la primera versión —`violet`, `amber`…—
  /// porque esa versión ya se instaló en esta máquina y pudo guardar uno de
  /// esos: quien eligiera violeta no debería encontrarse cian sin explicación.
  static Accent leer(String? guardado) {
    if (guardado == null) return Accent.cyan;
    final entero = int.tryParse(guardado);
    if (entero != null) return Accent(Color(entero));
    return switch (guardado) {
      'violet' => const Accent(Color(0xFFB79BFF)),
      'amber' => const Accent(Color(0xFFF5C451)),
      'rose' => const Accent(Color(0xFFFF8FB8)),
      'green' => const Accent(Color(0xFF6EE7A0)),
      'blue' => const Accent(Color(0xFF7FB2FF)),
      _ => Accent.cyan,
    };
  }

  Future<void> select(Color color) async {
    state = Accent(color);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, color.toARGB32().toString());
  }
}

final accentControllerProvider = NotifierProvider<AccentController, Accent>(
  AccentController.new,
);
