import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/i18n/language_preference.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';

void main() {
  group('qué idioma toca', () {
    test('elegido a mano, manda lo elegido', () {
      expect(
        LanguageChoice.english.resolve(const Locale('es')),
        const Locale('en'),
      );
      expect(
        LanguageChoice.spanish.resolve(const Locale('en')),
        const Locale('es'),
      );
    });

    test('siguiendo al sistema, se sigue al sistema', () {
      expect(
        LanguageChoice.system.resolve(const Locale('en')),
        const Locale('en'),
      );
      expect(
        LanguageChoice.system.resolve(const Locale('es')),
        const Locale('es'),
      );
    });

    // El español es el idioma por defecto del producto, no un neutro: un Mac en
    // alemán ve la app en español, no en inglés.
    test('un idioma que no hablamos cae en español', () {
      expect(
        LanguageChoice.system.resolve(const Locale('de')),
        const Locale('es'),
      );
      expect(
        LanguageChoice.system.resolve(const Locale('ja')),
        const Locale('es'),
      );
    });
  });

  group('lo que se guarda', () {
    test('ida y vuelta', () {
      for (final choice in LanguageChoice.values) {
        expect(LanguageChoice.fromStored(choice.stored), choice);
      }
    });

    test('una preferencia ilegible no rompe: se sigue al sistema', () {
      expect(LanguageChoice.fromStored(null), LanguageChoice.system);
      expect(LanguageChoice.fromStored('klingon'), LanguageChoice.system);
    });
  });

  group('los textos', () {
    test('cada idioma trae los suyos', () {
      expect(NexusStrings.of(const Locale('es')), isA<NexusStringsEs>());
      expect(NexusStrings.of(const Locale('en')), isA<NexusStringsEn>());
    });

    // Que estén traducidos de verdad, no copiados. Se comprueban textos con
    // palabras distintas en cada idioma: `brand` o `nexus` son iguales a
    // propósito y no dirían nada.
    test('no son el mismo texto repetido', () {
      const es = NexusStringsEs();
      const en = NexusStringsEn();
      expect(es.asleep, isNot(en.asleep));
      expect(es.rightNow, isNot(en.rightNow));
      expect(es.settings, isNot(en.settings));
      expect(es.composerHint, isNot(en.composerHint));
      expect(es.canEditFilesIn('repo'), isNot(en.canEditFilesIn('repo')));
    });

    test('lo que lleva un dato dentro lo coloca', () {
      const es = NexusStringsEs();
      expect(es.canEditFilesIn('nexus'), contains('nexus'));
      expect(es.readOnlyIn('nexus'), contains('nexus'));
      expect(es.keySaveFailed('se cayó'), contains('se cayó'));
    });
  });
}
