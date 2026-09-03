import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/features/artifacts/domain/entities/artifact.dart';
import 'package:nexus/features/artifacts/presentation/providers/artifacts_providers.dart';
import 'package:nexus/features/artifacts/presentation/widgets/artifacts_sheet.dart';
import 'package:nexus/features/e2e/domain/entities/cuenta_de_pruebas.dart';
import 'package:nexus/features/e2e/domain/entities/pasada_de_prueba.dart';
import 'package:nexus/features/e2e/presentation/providers/repo_de_pruebas_providers.dart';
import 'package:nexus/features/e2e/presentation/widgets/cuentas_de_un_proyecto.dart';
import 'package:nexus/features/e2e/presentation/widgets/publicar_prueba_dialogo.dart';

import 'support/screen_harness.dart';

/// Las tres pantallas que quedaban a cero, y cierran B4.
///
/// Mismo criterio que las de superpoderes: lo que se comprueba es lo que se
/// rompe sin avisar —lo vacío dicho, lo largo sin desbordar, y el tema claro,
/// que en estas tampoco se había mirado nunca—.
const _proyecto = '/Users/alguien/repo';

class _Carpeta extends ArtifactsFolder {
  @override
  String? build() {
    cargada = Future<void>.value();
    return '/Users/alguien/documentos';
  }
}

class _Cuentas extends CuentasDePrueba {
  _Cuentas(this.lista) : super(_proyecto);

  final List<CuentaDePruebas> lista;

  @override
  List<CuentaDePruebas> build() {
    cargadas = Future<void>.value();
    return lista;
  }
}

void main() {
  const textos = NexusStringsEs();

  void sinDesbordar(WidgetTester tester) {
    expect(
      tester.takeException(),
      isNull,
      reason: 'algo desbordó o reventó al pintar',
    );
  }

  group('las cuentas de un proyecto', () {
    Future<void> abrir(
      WidgetTester tester,
      List<CuentaDePruebas> cuentas, {
      ThemeData? tema,
    }) => pumpScreen(
      tester,
      // Dentro de un `ListView`, que es como la monta la app
      // (`cuentas_section.dart:37`). Sin él, un `Column` sin límite desborda —
      // y eso sería un fallo de la prueba, no del widget.
      Scaffold(
        body: ListView(
          children: const [CuentasDeUnProyecto(proyecto: _proyecto)],
        ),
      ),
      theme: tema,
      overrides: [
        cuentasDePruebaProvider(
          _proyecto,
        ).overrideWith(() => _Cuentas(cuentas)),
      ],
    );

    testWidgets('sin ninguna configurada no deja un hueco mudo', (
      tester,
    ) async {
      await abrir(tester, const []);

      sinDesbordar(tester);
      expect(
        find.byType(CuentasDeUnProyecto),
        findsOneWidget,
        reason: 'la sección existe aunque no haya cuentas: es donde se añaden',
      );
    });

    testWidgets('cada cuenta se ve por su clave', (tester) async {
      await abrir(tester, const [
        CuentaDePruebas(clave: 'pe', tags: {'smoke'}),
        CuentaDePruebas(clave: 'co', tags: {'smoke', 'regresion'}),
      ]);

      expect(find.textContaining('pe'), findsWidgets);
      expect(find.textContaining('co'), findsWidgets);
      sinDesbordar(tester);
    });

    // Un proyecto con una cuenta por país y etiquetas largas es lo normal, y es
    // donde una fila se sale.
    testWidgets('muchas cuentas con muchas etiquetas no desbordan', (
      tester,
    ) async {
      await abrir(tester, [
        for (final clave in const ['pe', 'co', 'mx', 'cl', 'ar', 'br', 'us'])
          CuentaDePruebas(
            clave: clave,
            tags: const {
              'smoke',
              'regresion-completa',
              'onboarding-con-documento',
              'pagos-internacionales',
            },
            descripcion:
                'La cuenta de $clave, con una descripción de las que ocupan '
                'una línea entera y a veces dos.',
          ),
      ]);

      sinDesbordar(tester);
    });

    testWidgets('también en claro', (tester) async {
      await abrir(tester, const [
        CuentaDePruebas(clave: 'pe', tags: {'smoke'}),
      ], tema: NexusTheme.light());

      sinDesbordar(tester);
    });
  });

  group('publicar una prueba', () {
    Future<void> abrir(WidgetTester tester, {ThemeData? tema}) => pumpScreen(
      tester,
      const Scaffold(
        body: PublicarPruebaDialogo(
          prueba: Prueba(
            ruta: '/Users/alguien/repo/.maestro/onboarding.yaml',
            nombre: 'onboarding',
          ),
        ),
      ),
      theme: tema,
    );

    // 🔴 El estado en el que alguien lo abre la primera vez, y el que el propio
    // widget documenta: «el repo tiene que estar clonado: sin él no hay dónde
    // escribir ni contra qué comparar. Se dice, en vez de dejar un botón que
    // falla al tocarlo».
    testWidgets('sin el repo clonado lo dice, y no ofrece publicar', (
      tester,
    ) async {
      await abrir(tester);

      expect(find.text(textos.e2ePublishNoRepo), findsOneWidget);
      expect(
        find.text(textos.e2ePublishTitle),
        findsNothing,
        reason: 'sin dónde escribir no se enseña el formulario de publicar',
      );
      sinDesbordar(tester);
    });

    testWidgets('también en claro', (tester) async {
      await abrir(tester, tema: NexusTheme.light());

      sinDesbordar(tester);
    });
  });

  group('los documentos', () {
    Future<void> abrir(
      WidgetTester tester,
      List<Artifact> documentos, {
      ThemeData? tema,
    }) => pumpScreen(
      tester,
      const Scaffold(body: ArtifactsSheet()),
      theme: tema,
      overrides: [
        // Sin carpeta la hoja enseña «elige una», que es otra rama: para ver la
        // lista hay que dársela.
        artifactsFolderProvider.overrideWith(_Carpeta.new),
        artifactsProvider.overrideWith((ref) async => documentos),
      ],
    );

    testWidgets('sin ninguno lo dice', (tester) async {
      await abrir(tester, const []);

      expect(find.text(textos.artifactsEmpty), findsOneWidget);
      sinDesbordar(tester);
    });

    testWidgets('cada uno se ve por su nombre', (tester) async {
      await abrir(tester, [
        Artifact(
          path: '/Users/alguien/documentos/diagrama.html',
          name: 'diagrama.html',
          at: DateTime(2026, 9, 3, 9, 30),
        ),
      ]);

      expect(find.textContaining('diagrama.html'), findsWidgets);
      sinDesbordar(tester);
    });

    // Un nombre largo de verdad: los documentos se nombran solos, con la frase
    // que los pidió y la fecha delante.
    testWidgets('una lista larga con nombres largos no desborda', (
      tester,
    ) async {
      await abrir(tester, [
        for (var i = 0; i < 60; i++)
          Artifact(
            path: '/Users/alguien/documentos/doc-$i.png',
            name:
                '20260903-09$i-un-zorro-naranja-leyendo-un-libro-junto-a-la-'
                'ventana-en-una-tarde-de-otono-$i.png',
            at: DateTime(2026, 9, 3, 9, i % 60),
            account: i.isEven ? 'work' : 'private',
          ),
      ]);

      sinDesbordar(tester);
    });

    testWidgets('también en claro', (tester) async {
      await abrir(tester, const [], tema: NexusTheme.light());

      sinDesbordar(tester);
    });
  });
}
