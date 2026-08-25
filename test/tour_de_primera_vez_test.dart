import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/features/assistant/presentation/pages/home_page.dart';
import 'package:nexus/features/onboarding/presentation/providers/tour_providers.dart';
import 'package:nexus/features/onboarding/presentation/state/tour_state.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/screen_harness.dart';

/// El tour de la primera vez: nadie te decía qué es cada pieza del HUD.
///
/// Lo que se comprueba aquí no es que «haya un tour», es lo que puede salir mal:
/// que aparezca **una vez** y no en cada arranque, que señale piezas que están de
/// verdad en pantalla, y que se pueda salir.
void main() {
  late Directory support;

  setUp(() => support = prepareScreenTest());
  tearDown(() => support.deleteSync(recursive: true));

  Future<ProviderContainer> abrirCasa(
    WidgetTester tester, {
    double alto = 800,
  }) async {
    await pumpScreen(
      tester,
      const HomePage(),
      size: Size(1280, alto),
      overrides: [
        workspaceControllerProvider.overrideWith(
          () =>
              FixedWorkspace(workspaceWith(modality: FolderModality.textOnly)),
        ),
      ],
    );
    // El tour arranca en el primer fotograma —antes no hay rectángulos— y la
    // preferencia se lee de disco, así que hacen falta unos cuantos.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return ProviderScope.containerOf(tester.element(find.byType(HomePage)));
  }

  group('el recorrido', () {
    testWidgets('arranca solo la primera vez y señala una pieza real', (
      tester,
    ) async {
      final container = await abrirCasa(tester);
      final tour = container.read(tourControllerProvider);

      expect(tour.running, isTrue);
      expect(
        tour.stop,
        TourStop.orb,
        reason: 'el orbe es lo primero que se ve',
      );
      expect(
        tour.total,
        greaterThan(1),
        reason: 'la casa vacía tiene orbe, caja, muelle y el círculo del cupo',
      );

      // Y la pieza señalada tiene rectángulo: un foco sobre la nada sería peor
      // que no señalar.
      final anchors = container.read(tourAnchorsProvider);
      expect(tourRectOf(anchors, TourStop.orb), isNotNull);
    });

    testWidgets('se ve el paso y la explicación', (tester) async {
      final container = await abrirCasa(tester);
      final total = container.read(tourControllerProvider).total;

      expect(find.text('paso 1 de $total'), findsOne);
      expect(find.textContaining('Háblale'), findsOne);
      expect(find.text('Siguiente'), findsOne);
      expect(find.text('Saltar el tour'), findsOne);
    });

    testWidgets('«Siguiente» avanza, y el último dice «Entendido»', (
      tester,
    ) async {
      final container = await abrirCasa(tester);
      final total = container.read(tourControllerProvider).total;

      for (var paso = 1; paso < total; paso++) {
        expect(find.text('paso $paso de $total'), findsOne);
        await tester.tap(find.text('Siguiente'));
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.text('paso $total de $total'), findsOne);
      expect(find.text('Entendido'), findsOne);
      expect(find.text('Siguiente'), findsNothing);

      await tester.tap(find.text('Entendido'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(container.read(tourControllerProvider).running, isFalse);
    });

    testWidgets('y no vuelve en el siguiente arranque', (tester) async {
      final container = await abrirCasa(tester);
      container.read(tourControllerProvider.notifier).finish();
      await tester.pump(const Duration(milliseconds: 50));

      // Segunda apertura, con la preferencia ya guardada.
      final otra = await abrirCasa(tester);
      expect(
        otra.read(tourControllerProvider).running,
        isFalse,
        reason: 'plantar el tour en cada arranque es un peaje',
      );
    });

    testWidgets('saltarlo cuenta igual que terminarlo', (tester) async {
      // Quien lo salta no quiere verlo: volver a enseñarlo mañana es ignorar lo
      // que acaba de decir.
      final container = await abrirCasa(tester);
      await tester.tap(find.text('Saltar el tour'));
      await tester.pump(const Duration(milliseconds: 50));

      expect(container.read(tourControllerProvider).running, isFalse);
      expect(
        SharedPreferences.getInstance().then((p) => p.getBool('tour_seen')),
        completion(isTrue),
      );
    });
  });

  // Reportado viéndolo: cuadros de casi el alto de la ventana, con el texto
  // arriba y el resto vacío, cruzando la pantalla por el medio. El `Flexible`
  // que permite encoger el cuerpo estiraba la columna hasta el tope de alto.
  //
  // **Esto fija la causa y no el aspecto, a propósito.** Medir el alto aquí no
  // sirve: la fuente de las pruebas pinta cada carácter como un cuadrado y
  // engorda el texto casi al doble, así que cualquier umbral en píxeles mediría
  // la fuente. Y «que no cambie al crecer la ventana» tampoco vale — comprobado,
  // cambia por otros caminos: el hueco que se señala crece con la pantalla y con
  // él la rama de colocación. Lo que sí es determinista es de quién toma el alto
  // la columna. El aspecto se revisa mirando la app.
  testWidgets('la tarjeta toma su alto del texto, no del espacio libre', (
    tester,
  ) async {
    await abrirCasa(tester);

    final columna = tester.widget<Column>(
      find
          .descendant(
            of: find.byKey(const ValueKey('tour-card')),
            matching: find.byType(Column),
          )
          .first,
    );

    expect(
      columna.mainAxisSize,
      MainAxisSize.min,
      reason:
          'con `max`, el Flexible del cuerpo rellena todo el tope de alto y '
          'salen cuadros de casi 800 px con el texto arriba',
    );
  });

  group('verlo otra vez, desde Ajustes', () {
    testWidgets('vuelve a salir aunque ya se hubiera visto', (tester) async {
      final container = await abrirCasa(tester);
      container.read(tourControllerProvider.notifier).finish();
      await tester.pump(const Duration(milliseconds: 50));
      expect(container.read(tourControllerProvider).running, isFalse);

      container.read(tourControllerProvider.notifier).replay();
      // Tres bombeos, y cada uno hace una cosa: el velo se entera al
      // construirse, arranca en el `post-frame` siguiente —cuando ya puede
      // preguntar por los rectángulos— y solo entonces pide mostrarse, que
      // también va aplazado. Con dos, el estado ya dice «corriendo» y el cuadro
      // todavía no está.
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final tour = container.read(tourControllerProvider);
      expect(
        tour.running,
        isTrue,
        reason:
            'el velo ya se había dado por intentado; sin enterarse de la '
            'petición, el botón de Ajustes no haría nada visible',
      );
      expect(
        tour.stop,
        TourStop.orb,
        reason: 'empieza otra vez por el principio',
      );
      expect(find.text('paso 1 de 4'), findsOne);
    });

    test('y se olvida la marca de disco, no solo la de esta sesión', () async {
      // Si solo se desarmara en memoria, el tour volvería a no salir en el
      // siguiente arranque y «ver otra vez» sería una promesa a medias.
      SharedPreferences.setMockInitialValues({'flutter.tour_seen': true});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(tourControllerProvider.notifier).replay();
      await Future<void>.delayed(Duration.zero);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('tour_seen'), isNull);
    });
  });

  group('el estado, sin pantalla', () {
    test('el paso se cuenta contra el total fijado al arrancar', () {
      const cuatro = TourState(
        stop: TourStop.orb,
        pending: [TourStop.composer, TourStop.dock, TourStop.meter],
        total: 4,
      );
      expect(cuatro.index, 1);
      expect(
        const TourState(stop: TourStop.meter, pending: [], total: 4).index,
        4,
        reason: 'si el total se recalculara, «4 de 4» sería «1 de 1»',
      );
    });

    test('sin parada no está corriendo', () {
      expect(const TourState().running, isFalse);
      expect(const TourState().index, 0);
    });
  });

  testWidgets('el velo no deja tocar lo que hay debajo', (tester) async {
    // Durante el tour, tocar el orbe abriría una sesión de voz por detrás de la
    // explicación: se estaría hablando con algo que no se ve.
    final container = await abrirCasa(tester);
    expect(container.read(tourControllerProvider).running, isTrue);

    await tester.tapAt(const Offset(200, 400));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      container.read(tourControllerProvider).running,
      isTrue,
      reason: 'el toque se lo come el velo, no llega al orbe ni cierra el tour',
    );
  });

  testWidgets('abre y pinta en tema claro', (tester) async {
    await pumpScreen(
      tester,
      const HomePage(),
      theme: NexusTheme.light(),
      overrides: [
        workspaceControllerProvider.overrideWith(
          () =>
              FixedWorkspace(workspaceWith(modality: FolderModality.textOnly)),
        ),
      ],
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Háblale'), findsOne);
  });
}
