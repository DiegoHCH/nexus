import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/theme_preference.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('lo guardado se recupera, y lo raro cae en el del sistema', () {
    expect(ThemeChoice.fromStored('light'), ThemeChoice.light);
    expect(ThemeChoice.fromStored('dark'), ThemeChoice.dark);
    expect(ThemeChoice.fromStored('system'), ThemeChoice.system);
    // Una preferencia escrita por otra versión —o tocada a mano— no puede
    // tumbar el arranque: cae en la del sistema, que es lo que había antes de
    // que se pudiera elegir.
    expect(ThemeChoice.fromStored('sepia'), ThemeChoice.system);
    expect(ThemeChoice.fromStored(null), ThemeChoice.system);
  });

  test('elegir a mano gana al sistema, y con «el del sistema» manda él', () {
    // `isDark` existe aparte de `mode` porque el marco de la ventana no es
    // Flutter: a AppKit hay que decírselo en un booleano ya resuelto.
    expect(ThemeChoice.light.isDark(Brightness.dark), isFalse);
    expect(ThemeChoice.dark.isDark(Brightness.light), isTrue);
    expect(ThemeChoice.system.isDark(Brightness.dark), isTrue);
    expect(ThemeChoice.system.isDark(Brightness.light), isFalse);
  });

  test('la elección sobrevive al reinicio', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(themeControllerProvider.notifier).select(
      ThemeChoice.light,
    );
    expect(container.read(themeControllerProvider), ThemeChoice.light);

    // Otro arranque: se lee lo guardado en vez de volver al del sistema.
    final otro = ProviderContainer();
    addTearDown(otro.dispose);
    otro.read(themeControllerProvider);
    await otro.read(themeControllerProvider.notifier).unawaitedLoad();

    expect(otro.read(themeControllerProvider), ThemeChoice.light);
  });

  test('cada elección lleva su ThemeMode', () {
    expect(ThemeChoice.system.mode, ThemeMode.system);
    expect(ThemeChoice.light.mode, ThemeMode.light);
    expect(ThemeChoice.dark.mode, ThemeMode.dark);
  });
}
