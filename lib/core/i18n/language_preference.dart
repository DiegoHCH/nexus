import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Qué idioma usa la app: el del sistema, o uno elegido a mano.
enum LanguageChoice {
  system,
  spanish,
  english;

  static LanguageChoice fromStored(String? value) => switch (value) {
    'es' => LanguageChoice.spanish,
    'en' => LanguageChoice.english,
    _ => LanguageChoice.system,
  };

  String get stored => switch (this) {
    LanguageChoice.system => 'system',
    LanguageChoice.spanish => 'es',
    LanguageChoice.english => 'en',
  };

  /// El idioma efectivo. Con «el del sistema» se mira lo que dice la
  /// plataforma, y **cualquier cosa que no sea inglés cae en español**: es el
  /// idioma por defecto del producto, no un fallback neutro.
  Locale resolve(Locale system) => switch (this) {
    LanguageChoice.spanish => const Locale('es'),
    LanguageChoice.english => const Locale('en'),
    LanguageChoice.system =>
      system.languageCode == 'en' ? const Locale('en') : const Locale('es'),
  };
}

/// El idioma elegido, recordado entre arranques.
///
/// Arranca en `system` mientras se lee la preferencia: son unos milisegundos,
/// y es mejor enseñar el idioma del sistema y corregir que parpadear al revés.
class LanguageController extends Notifier<LanguageChoice> {
  static const _key = 'language';

  @override
  LanguageChoice build() {
    unawaitedLoad();
    return LanguageChoice.system;
  }

  Future<void> unawaitedLoad() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = LanguageChoice.fromStored(prefs.getString(_key));
    // 🔴 Se sale con `unawaited` desde `build`, así que esto aterriza **después
    // de un `await`** y el proveedor puede haberse desmontado ya. Sin la
    // comprobación, `state =` lanza — y como nadie espera este futuro, el error
    // sale por la puerta de atrás y tumba lo que estuviera corriendo.
    if (!ref.mounted) return;
    if (stored != state) state = stored;
  }

  Future<void> select(LanguageChoice choice) async {
    state = choice;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, choice.stored);
  }
}

final languageControllerProvider =
    NotifierProvider<LanguageController, LanguageChoice>(
      LanguageController.new,
    );

/// El idioma que toca ahora mismo, ya resuelto contra el del sistema.
final localeProvider = Provider<Locale>((ref) {
  final choice = ref.watch(languageControllerProvider);
  final system = PlatformDispatcher.instance.locale;
  return choice.resolve(system);
});

/// Los textos, para quien pueda leer providers. Las pantallas que no son
/// `Consumer` los reciben por el árbol, vía `context.strings`.
final stringsProvider = Provider<NexusStrings>(
  (ref) => NexusStrings.of(ref.watch(localeProvider)),
);
