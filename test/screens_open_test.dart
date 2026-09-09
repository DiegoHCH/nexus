import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/features/assistant/presentation/pages/home_page.dart';
import 'package:nexus/features/history/domain/entities/conversation_summary.dart';
import 'package:nexus/features/history/presentation/providers/archive_providers.dart';
import 'package:nexus/features/history/presentation/widgets/conversation_history_sheet.dart';
import 'package:nexus/features/onboarding/presentation/pages/initial_setup_page.dart';
import 'package:nexus/features/onboarding/presentation/pages/splash_page.dart';
import 'package:nexus/features/workspace/presentation/pages/settings_page.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

import 'support/screen_harness.dart';

/// Que cada pantalla **abra**. Nada más, y ese es el punto: los tres fallos que
/// motivaron esto —textos fuera de alcance, una sección sin listar, providers
/// leídos en mitad del build— no rompen ninguna regla, solo el montaje.
void main() {
  const strings = NexusStringsEs();
  late Directory support;

  setUp(() => support = prepareScreenTest());
  tearDown(() => support.deleteSync(recursive: true));

  testWidgets('el splash', (tester) async {
    await pumpScreen(tester, const SplashPage());
    expect(find.text(strings.starting), findsOneWidget);
  });

  testWidgets('la configuración inicial', (tester) async {
    await pumpScreen(tester, const InitialSetupPage());
    expect(find.text(strings.beforeWeStart), findsOneWidget);
    expect(find.text(strings.geminiKey), findsOneWidget);
  });

  testWidgets('la casa, sin ninguna conversación abierta', (tester) async {
    await pumpScreen(
      tester,
      const HomePage(),
      overrides: [
        workspaceControllerProvider.overrideWith(
          () => FixedWorkspace(workspaceWith()),
        ),
      ],
    );

    // La caja siempre está disponible, también sin conversación.
    expect(find.text(strings.composerHint), findsOneWidget);
  });

  group('ajustes', () {
    Future<void> abrir(WidgetTester tester) => pumpScreen(
      tester,
      const SettingsPage(),
      overrides: [
        workspaceControllerProvider.overrideWith(
          () => FixedWorkspace(workspaceWith()),
        ),
      ],
    );

    testWidgets('abre por permisos', (tester) async {
      await abrir(tester);
      expect(find.text(strings.settings), findsOneWidget);
      expect(find.text(strings.filePermissionsTitle), findsOneWidget);
    });

    // Las cuatro secciones se abren de verdad: una que existiera y no
    // estuviera en la lista —o que reventara al pintarse— pasaría inadvertida
    // hasta que alguien la pulsara. Ya pasó.
    testWidgets('y sus cuatro secciones', (tester) async {
      await abrir(tester);

      for (final (seccion, titulo) in [
        ('voice', strings.nexusVoice),
        ('history', strings.archiveTitle),
        // Del idioma se comprueba su explicación y no el título: «IDIOMA» es
        // también el nombre del enlace del menú, y encontrarlo dos veces no
        // diría si la sección llegó a pintarse.
        ('language', strings.languageExplainer),
        ('permissions', strings.filePermissionsTitle),
      ]) {
        await tester.tap(find.byKey(ValueKey('seccion-$seccion')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text(titulo), findsOneWidget, reason: seccion);
      }
    });
  });

  testWidgets('el historial, sin nada guardado todavía', (tester) async {
    await pumpScreen(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => ConversationHistorySheet.open(
            context,
            onPick: (_) {},
            onForget: () {},
          ),
          child: const Text('abrir'),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(strings.history), findsOneWidget);
    expect(find.text(strings.nothingAskedYet), findsOneWidget);
  });

  // 🔴 **Con cosas guardadas, el historial se lee por días.** Pedido tras
  // arreglar la fecha: «que se organicen por fechas, que tengan una separación
  // visual y que aparezca la fecha». Antes era una tira de filas con la marca
  // de tiempo completa repetida en cada una.
  testWidgets('el historial agrupa por días y pone su cabecera', (
    tester,
  ) async {
    final hoy = DateTime.now();
    // A otra hora, o las dos filas enseñarían la misma y no se podría
    // comprobar que cada una lleva la suya.
    final ayer = hoy.subtract(const Duration(days: 1, hours: 3));
    ConversationSummary ficha(String id, DateTime cuando) =>
        ConversationSummary(
          id: id,
          folderPath: '/Users/alguien/Workspace/tienda',
          startedAt: cuando,
          usadaEn: cuando,
          title: id,
          turns: 3,
        );

    await pumpScreen(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => ConversationHistorySheet.open(
            context,
            onPick: (_) {},
            onForget: () {},
          ),
          child: const Text('abrir'),
        ),
      ),
      overrides: [
        allSavedConversationsProvider.overrideWith(
          (ref) => Future.value([
            ficha('la de esta mañana', hoy),
            ficha('la de ayer', ayer),
          ]),
        ),
      ],
    );

    await tester.tap(find.text('abrir'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(strings.historialHoy.toUpperCase()), findsOneWidget);
    expect(find.text(strings.historialAyer.toUpperCase()), findsOneWidget);
    expect(find.text('la de esta mañana'), findsOneWidget);
    expect(find.text('la de ayer'), findsOneWidget);
    // Y la fila enseña la hora, no la fecha entera: el día ya lo dice su
    // cabecera.
    String dos(int v) => v.toString().padLeft(2, '0');
    expect(find.text('${dos(hoy.hour)}:${dos(hoy.minute)}'), findsOneWidget);
    expect(
      find.textContaining('${hoy.year}-'),
      findsNothing,
      reason: 'la fecha repetida en cada fila era la tira sin cortes',
    );
  });
}
