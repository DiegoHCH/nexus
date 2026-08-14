import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Qué apariencia usa la app: la del sistema, o una elegida a mano.
///
/// Con «la del sistema» no basta, y por eso existe esto: esta app se mira de
/// noche y a oscuras tanto como de día, y quien la usa no cambia el tema del
/// Mac entero para eso. El tema claro ya estaba construido —paleta propia, con
/// el cian bajado a `#0C7C88` por contraste AA— pero no había dónde pedirlo.
enum ThemeChoice {
  system,
  light,
  dark;

  static ThemeChoice fromStored(String? value) => switch (value) {
    'light' => ThemeChoice.light,
    'dark' => ThemeChoice.dark,
    _ => ThemeChoice.system,
  };

  String get stored => switch (this) {
    ThemeChoice.system => 'system',
    ThemeChoice.light => 'light',
    ThemeChoice.dark => 'dark',
  };

  ThemeMode get mode => switch (this) {
    ThemeChoice.system => ThemeMode.system,
    ThemeChoice.light => ThemeMode.light,
    ThemeChoice.dark => ThemeMode.dark,
  };

  /// Si lo que toca pintar es oscuro, ya resuelto contra el sistema.
  ///
  /// Hace falta aparte de [mode] porque **el marco de la ventana no es
  /// Flutter**: es AppKit, y hay que decírselo en un booleano. Sin esto, elegir
  /// claro dejaba el contenido claro dentro de una barra de título negra.
  bool isDark(Brightness system) => switch (this) {
    ThemeChoice.light => false,
    ThemeChoice.dark => true,
    ThemeChoice.system => system == Brightness.dark,
  };
}

/// La apariencia elegida, recordada entre arranques.
///
/// Arranca en `system` mientras se lee la preferencia: son unos milisegundos, y
/// es mejor enseñar lo que el sistema pide y corregir que parpadear al revés.
class ThemeController extends Notifier<ThemeChoice> {
  static const _key = 'theme';

  @override
  ThemeChoice build() {
    unawaitedLoad();
    return ThemeChoice.system;
  }

  Future<void> unawaitedLoad() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = ThemeChoice.fromStored(prefs.getString(_key));
    if (stored != state) state = stored;
  }

  Future<void> select(ThemeChoice choice) async {
    state = choice;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, choice.stored);
  }
}

final themeControllerProvider = NotifierProvider<ThemeController, ThemeChoice>(
  ThemeController.new,
);

/// Si ahora mismo toca oscuro, ya resuelto. Lo miran la app y el marco nativo.
final isDarkProvider = Provider<bool>((ref) {
  final choice = ref.watch(themeControllerProvider);
  return choice.isDark(PlatformDispatcher.instance.platformBrightness);
});
