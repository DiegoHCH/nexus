import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/features/onboarding/domain/repositories/gemini_key_store.dart';
import 'package:nexus/features/onboarding/presentation/providers/onboarding_providers.dart';
import 'package:nexus/features/onboarding/presentation/pages/initial_setup_page.dart';
import 'package:nexus/features/onboarding/presentation/state/onboarding_state.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/presentation/pages/settings_page.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

import 'support/screen_harness.dart';

/// Lo que Nexus pide antes de dejarte entrar.
///
/// Pedía tres cosas: micrófono, una llave de Gemini y una carpeta. Dos de las
/// tres son de la voz, que está apagada en toda carpeta hasta que alguien la
/// encienda —y que desde el `.nexus/` un repositorio puede apagar del todo—, así
/// que se estaban pidiendo las credenciales de una función que nadie iba a usar
/// todavía. A quien no quisiera dar una llave de Google no le quedaba ninguna
/// forma de usar la app.
///
/// Y encima la pantalla prometía «puedes cambiar esto después en Ajustes»,
/// donde no había ningún sitio para cambiarla.

/// Un llavero que apunta lo que se le manda guardar.
class _Llavero implements GeminiKeyStore {
  _Llavero();

  String? _value;
  final guardadas = <String>[];

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> save(String key) async {
    guardadas.add(key);
    _value = key;
  }
}

void main() {
  const es = NexusStringsEs();

  group('qué hace falta para entrar', () {
    test('ni el micrófono ni la llave', () {
      // El estado de recién abierta la pantalla: nada pedido, nada escrito.
      expect(const SetupState().canFinish, isTrue);
    });

    test('mientras guarda, no', () {
      expect(const SetupState(saving: true).canFinish, isFalse);
    });
  });

  group('lo que se guarda al terminar', () {
    ProviderContainer conLlavero(_Llavero llavero) {
      final container = ProviderContainer(
        overrides: [geminiKeyStoreProvider.overrideWithValue(llavero)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('una llave escrita se guarda', () async {
      final llavero = _Llavero();
      final container = conLlavero(llavero);
      final setup = container.read(setupControllerProvider.notifier);

      setup.updateKeyText('  una-llave  ');
      expect(await setup.finish(), isTrue);
      expect(llavero.guardadas, ['una-llave']);
    });

    // El fallo concreto que evita: una cadena vacía en el llavero **es** una
    // llave para quien pregunte si la hay, así que la pantalla de salidas diría
    // que Gemini está disponible y la sesión de voz fallaría al abrirse.
    test('no haber escrito ninguna no guarda una vacía', () async {
      final llavero = _Llavero();
      final container = conLlavero(llavero);

      expect(
        await container.read(setupControllerProvider.notifier).finish(),
        isTrue,
        reason: 'se entra igual',
      );
      expect(llavero.guardadas, isEmpty);
    });

    test('ni una de solo espacios', () async {
      final llavero = _Llavero();
      final container = conLlavero(llavero);
      final setup = container.read(setupControllerProvider.notifier);

      setup.updateKeyText('   ');
      await setup.finish();
      expect(llavero.guardadas, isEmpty);
    });
  });

  group('lo que queda por debajo del borde', () {
    late Directory support;

    setUp(() => support = prepareScreenTest());
    tearDown(() => support.deleteSync(recursive: true));

    // La pantalla se desplaza —en 1280×800 sobran unos 500 píxeles— y eso está
    // bien; lo que no puede ser es que no se note. La barra del sistema no lo
    // resuelve: en macOS se pinta al desplazar y desaparece sola, o sea que
    // aparece cuando ya sabes que hay más.
    testWidgets('no se anuncia con una barra', (tester) async {
      await pumpScreen(tester, const InitialSetupPage());
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(Scrollbar), findsNothing);
    });

    testWidgets('se anuncia con una flecha, y solo mientras haga falta', (
      tester,
    ) async {
      await pumpScreen(tester, const InitialSetupPage());
      await tester.pump(const Duration(milliseconds: 200));

      final flecha = find.byIcon(Icons.keyboard_arrow_down);
      expect(
        flecha,
        findsOneWidget,
        reason: 'hay contenido debajo y no se dice',
      );

      // Al final del todo ya no queda nada: una flecha que se quedara fija
      // dejaría de mirarse la próxima vez.
      final scroll = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      scroll.jumpTo(scroll.maxScrollExtent);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(flecha, findsNothing);
    });

    // Sin ventana pequeña no hay nada que anunciar, y anunciarlo igual sería
    // una flecha que apunta al vacío.
    testWidgets('en una ventana donde todo cabe, no aparece', (tester) async {
      await pumpScreen(
        tester,
        const InitialSetupPage(),
        size: const Size(1280, 2000),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
    });
  });

  group('la promesa de «cámbialo después en Ajustes»', () {
    late Directory support;

    setUp(() => support = prepareScreenTest());
    tearDown(() => support.deleteSync(recursive: true));

    // La pantalla de arranque lleva esa frase desde siempre. Hasta ahora era
    // falsa: `saveGeminiKey` solo se llamaba desde el propio arranque, y una
    // llave mal escrita solo se arreglaba tocando el llavero a mano.
    testWidgets('tiene dónde aterrizar, y guarda', (tester) async {
      final llavero = _Llavero();

      await pumpScreen(
        tester,
        const SettingsPage(),
        overrides: [
          geminiKeyStoreProvider.overrideWithValue(llavero),
          workspaceControllerProvider.overrideWith(
            // En solo texto a propósito: con la carpeta en voz, su interruptor
            // dice «VOZ» y choca con la pestaña de la sección, que dice lo
            // mismo. Y es además el estado real de una carpeta recién
            // emparejada.
            () => FixedWorkspace(
              workspaceWith(modality: FolderModality.textOnly),
            ),
          ),
        ],
      );

      await tester.tap(find.text(es.sectionVoice.toUpperCase()));
      await tester.pump(const Duration(milliseconds: 100));

      // Sin llave se dice, y se dice qué significa no tenerla.
      expect(find.text(es.geminiKeyMissing), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'la-llave-nueva');
      await tester.tap(find.text(es.geminiKeySave));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(llavero.guardadas, ['la-llave-nueva']);
    });
  });
}
