import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/features/e2e/data/datasources/repo_de_pruebas_data_source.dart';
import 'package:nexus/features/e2e/presentation/providers/repo_de_pruebas_providers.dart';
import 'package:nexus/features/e2e/presentation/widgets/repo_de_pruebas_seccion.dart';
import 'package:nexus/features/stats/domain/entities/transcript_turn.dart';
import 'package:nexus/features/stats/presentation/providers/stats_providers.dart';
import 'package:nexus/features/stats/presentation/widgets/stats_section.dart';
import 'package:nexus/features/superpowers/presentation/widgets/superpowers_section.dart';
import 'package:nexus/features/workspace/data/datasources/claude_profiles_data_source.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

import 'support/screen_harness.dart';

class _Slug extends SlugDelRepoDePruebas {
  @override
  String build() {
    cargada = Future<void>.value();
    return 'equipo/pruebas';
  }
}

/// Las secciones de Ajustes que estaban por debajo del 10 %.
///
/// La ronda de esta mañana cubrió los **paneles** de superpoderes y se dejó las
/// **secciones** que los contienen. Y lo que decide una sección no es lo mismo
/// que lo que decide un panel: aquí se resuelve **con qué cuenta se mira**, que
/// es la regla que estas tres comparten con el historial —«las pestañas separan
/// cuentas, así que solo existen si hay más de una en el Mac»—.
const _work = ClaudeProfile(
  path: '/Users/alguien/.claude-work',
  name: 'work',
  signedIn: true,
);
const _personal = ClaudeProfile(
  path: '/Users/alguien/.claude',
  name: 'por defecto',
  signedIn: true,
);

void main() {
  const textos = NexusStringsEs();

  void sinDesbordar(WidgetTester tester) {
    expect(tester.takeException(), isNull, reason: 'desbordó o reventó');
  }

  List<Object> con(
    List<ClaudeProfile> cuentas, {
    List<TranscriptTurn>? turnos,
  }) => [
    claudeProfilesProvider.overrideWith((ref) async => cuentas),
    for (final cuenta in cuentas)
      transcriptTurnsProvider(
        cuenta.path,
      ).overrideWith((ref) async => turnos ?? const []),
  ];

  TranscriptTurn turno({int input = 1000, int output = 200}) => TranscriptTurn(
    at: DateTime.now().subtract(const Duration(hours: 1)),
    sessionId: 's1',
    fromAssistant: true,
    model: 'claude-opus-5',
    input: input,
    output: output,
  );

  group('las estadísticas', () {
    Future<void> abrir(
      WidgetTester tester, {
      required List<ClaudeProfile> cuentas,
      List<TranscriptTurn>? turnos,
      ThemeData? tema,
    }) => pumpScreen(
      tester,
      const Scaffold(body: StatsSection()),
      theme: tema,
      overrides: con(cuentas, turnos: turnos),
    );

    // 🔴 Sin cuenta no hay nada que contar, y decirlo es lo que separa «no has
    // trabajado» de «no encuentro tus cuentas».
    testWidgets('sin ninguna cuenta lo dice', (tester) async {
      await abrir(tester, cuentas: const []);

      expect(find.text(textos.statsNoAccounts), findsOneWidget);
      sinDesbordar(tester);
    });

    // Con una sola, dividir en pestañas inventa una frontera donde no la hay.
    testWidgets('con una cuenta no hay pestañas', (tester) async {
      await abrir(tester, cuentas: const [_work]);

      expect(find.text('WORK'), findsNothing);
      sinDesbordar(tester);
    });

    testWidgets('con dos, sí, y se ven las dos', (tester) async {
      await abrir(tester, cuentas: const [_work, _personal]);

      expect(find.text('WORK'), findsOneWidget);
      expect(find.text('POR DEFECTO'), findsOneWidget);
      sinDesbordar(tester);
    });

    // Una cuenta con sesión pero sin turnos todavía no es un error.
    testWidgets('con cuenta y sin turnos lo dice, no deja un hueco', (
      tester,
    ) async {
      await abrir(tester, cuentas: const [_work]);

      expect(find.text(textos.statsNothingYet), findsOneWidget);
      sinDesbordar(tester);
    });

    testWidgets('con turnos pinta las cifras sin desbordar', (tester) async {
      await abrir(
        tester,
        cuentas: const [_work],
        turnos: [for (var i = 0; i < 200; i++) turno(input: 900000)],
      );

      expect(find.text(textos.statsNothingYet), findsNothing);
      sinDesbordar(tester);
    });

    testWidgets('y también en claro', (tester) async {
      await abrir(
        tester,
        cuentas: const [_work, _personal],
        turnos: [turno()],
        tema: NexusTheme.light(),
      );

      sinDesbordar(tester);
    });
  });

  group('los superpoderes', () {
    Future<void> abrir(
      WidgetTester tester, {
      required List<ClaudeProfile> cuentas,
      ThemeData? tema,
    }) => pumpScreen(
      tester,
      const Scaffold(body: SuperpowersSection()),
      theme: tema,
      overrides: con(cuentas),
    );

    testWidgets('sin ninguna cuenta lo dice', (tester) async {
      await abrir(tester, cuentas: const []);

      expect(find.text(textos.statsNoAccounts), findsOneWidget);
      sinDesbordar(tester);
    });

    testWidgets('con una cuenta no hay pestañas', (tester) async {
      await abrir(tester, cuentas: const [_work]);

      expect(find.text('WORK'), findsNothing);
      sinDesbordar(tester);
    });

    testWidgets('con dos, cada cuenta tiene la suya', (tester) async {
      await abrir(tester, cuentas: const [_work, _personal]);

      expect(find.text('WORK'), findsOneWidget);
      expect(find.text('POR DEFECTO'), findsOneWidget);
      sinDesbordar(tester);
    });

    testWidgets('y también en claro', (tester) async {
      await abrir(
        tester,
        cuentas: const [_work, _personal],
        tema: NexusTheme.light(),
      );

      sinDesbordar(tester);
    });
  });

  // La tercera de las que estaban a cero. Solo sus dos ramas de arriba: la de
  // abajo cuelga de un grafo de seis proveedores —clon, flows, piezas,
  // emuladores, dispositivos, destinos— y montarlo entero para una prueba de
  // pintado sería montar la app.
  group('el repo de pruebas', () {
    Future<void> abrir(WidgetTester tester, List<Object> overrides) =>
        pumpScreen(
          tester,
          const Scaffold(body: RepoDePruebasSeccion(proyecto: '/casa/tienda')),
          overrides: [
            slugDelRepoDePruebasProvider.overrideWith(_Slug.new),
            ...overrides,
          ],
        );

    // 🔴 Un «no hay flows» que dura tres segundos y luego se llena es
    // indistinguible de un repo vacío, y quien lo lea ya se fue a mirar por
    // qué. Por eso mientras clona se dice que está clonando.
    testWidgets('mientras clona lo dice, y no enseña una lista vacía', (
      tester,
    ) async {
      await abrir(tester, [
        clonDelRepoProvider.overrideWith(
          (ref) => Completer<ResultadoDeSync>().future,
        ),
      ]);

      expect(find.text(textos.e2eRepoUpdating), findsOneWidget);
      sinDesbordar(tester);
    });

    testWidgets('si el clon falla, se enseña el motivo', (tester) async {
      await abrir(tester, [
        clonDelRepoProvider.overrideWith(
          (ref) async => throw StateError('no hay red'),
        ),
      ]);
      await tester.pump();

      expect(find.text(textos.e2eRepoFailed), findsOneWidget);
      expect(find.textContaining('no hay red'), findsOneWidget);
      sinDesbordar(tester);
    });
  });
}
