import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// El acento de la app, elegible.
///
/// Hasta ahora era uno y estaba clavado: el cian del orbe. Y no hay motivo para
/// que lo esté — es lo único de la paleta que es **identidad y no información**.
/// Los colores de estado (`ok`/`warn`/`err`) no entran aquí y no se eligen nunca:
/// un «correcto» morado no querría decir nada.
///
/// **Cada opción trae dos colores, y ese es el punto que no es obvio.** El tema
/// claro no usa el mismo acento que el oscuro: sobre fondo claro un tono que
/// brilla deja de leerse, así que cada color baja. Un solo valor por opción, o
/// derivado con una fórmula, dejaría la mitad de las elecciones ilegibles en uno
/// de los dos temas.
///
/// Van calibrados a mano y **comprobados por una prueba** que mide el contraste de
/// los dos valores contra los tres fondos de su tema. Esa prueba encontró de paso
/// que el acento claro que ya estaba publicado —`#0C7C88`, con un comentario que
/// decía «por contraste AA»— medía **4,23** contra el `void` claro y no llegaba al
/// 4,5. Ahora es `#0B7480`.
enum AccentChoice {
  /// El de siempre, y el del icono de la app.
  cyan(Color(0xFF56E1EA), Color(0xFF0B7480)),

  violet(Color(0xFFB79BFF), Color(0xFF5B21B6)),

  amber(Color(0xFFF5C451), Color(0xFF8A5A06)),

  rose(Color(0xFFFF8FB8), Color(0xFFA81E5C)),

  /// Verde de verdad, para quien ya veía verde el cian.
  green(Color(0xFF6EE7A0), Color(0xFF14663C)),

  blue(Color(0xFF7FB2FF), Color(0xFF1D4ED8));

  const AccentChoice(this.dark, this.light);

  /// Sobre el vacío casi negro.
  final Color dark;

  /// Sobre el fondo claro, más oscuro para que siga leyéndose.
  final Color light;

  Color forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  static AccentChoice fromStored(String? value) => AccentChoice.values
      .firstWhere((c) => c.name == value, orElse: () => AccentChoice.cyan);

  String get stored => name;
}

/// El acento elegido, recordado entre arranques.
///
/// Arranca en el cian mientras se lee la preferencia, por lo mismo que el tema:
/// son unos milisegundos, y es mejor pintar el de siempre y corregir que
/// parpadear desde un color que nadie eligió.
class AccentController extends Notifier<AccentChoice> {
  static const _key = 'accent';

  @override
  AccentChoice build() {
    unawaited(cargar());
    return AccentChoice.cyan;
  }

  Future<void> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    final guardado = AccentChoice.fromStored(prefs.getString(_key));
    if (guardado != state) state = guardado;
  }

  Future<void> select(AccentChoice choice) async {
    state = choice;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, choice.stored);
  }
}

final accentControllerProvider =
    NotifierProvider<AccentController, AccentChoice>(AccentController.new);
