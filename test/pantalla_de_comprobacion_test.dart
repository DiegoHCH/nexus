import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/features/onboarding/domain/entities/readiness.dart';
import 'package:nexus/features/onboarding/presentation/pages/readiness_page.dart';

import 'support/screen_harness.dart';

/// Que la pantalla **abra y pinte**, en los dos temas, y que diga una sola cosa.
///
/// A esta pantalla no se puede llegar en un Mac que tenga Claude Code instalado
/// y con sesión, así que sin una prueba que la monte nadie la vería nunca hasta
/// el día en que hace falta — que es el peor día para descubrir que desborda.
void main() {
  late Directory soporte;

  setUp(() => soporte = prepareScreenTest());
  tearDown(() => soporte.deleteSync(recursive: true));

  const sinCli = Readiness(
    cli: CheckResult.failed,
    session: CheckResult.unknown,
    geminiKey: true,
  );
  const sinSesion = Readiness(
    cli: CheckResult.ok,
    session: CheckResult.failed,
    geminiKey: true,
  );

  for (final (nombre, tema) in [
    ('oscuro', NexusTheme.dark()),
    ('claro', NexusTheme.light()),
  ]) {
    testWidgets('abre y pinta en tema $nombre', (tester) async {
      await pumpScreen(
        tester,
        const ReadinessPage(readiness: sinCli),
        theme: tema,
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Claude Code no está instalado'), findsOne);
    });
  }

  testWidgets('dice una sola cosa: sin binario no manda a iniciar sesión', (
    tester,
  ) async {
    // Sin binario no se pudo preguntar por la sesión. Enseñar las dos filas
    // mandaría a arreglar algo que quizá ya está bien.
    await pumpScreen(tester, const ReadinessPage(readiness: sinCli));

    expect(find.textContaining('Claude Code no está instalado'), findsOne);
    expect(find.textContaining('Ninguna cuenta'), findsNothing);
  });

  testWidgets('y con binario sin sesión, solo la de la sesión', (tester) async {
    await pumpScreen(tester, const ReadinessPage(readiness: sinSesion));

    expect(find.textContaining('Ninguna cuenta'), findsOne);
    expect(find.textContaining('no está instalado'), findsNothing);
  });

  testWidgets('las dos salidas están siempre', (tester) async {
    // Una pantalla que informa y no deja salir es una pantalla que encierra.
    await pumpScreen(tester, const ReadinessPage(readiness: sinCli));

    expect(find.text('Comprobar de nuevo'), findsOne);
    expect(find.text('Entrar de todas formas'), findsOne);
  });

  /// No es una aserción: deja la pantalla en PNG para poder **mirarla**, que es
  /// la única forma de revisar algo a lo que no se puede llegar desde la app.
  testWidgets('se deja un retrato de la pantalla en los dos temas', (
    tester,
  ) async {
    final salida = Directory.systemTemp.path;
    for (final (nombre, tema) in [
      ('oscuro', NexusTheme.dark()),
      ('claro', NexusTheme.light()),
    ]) {
      await pumpScreen(
        tester,
        // El fondo del tema por debajo: un `RepaintBoundary` alrededor del
        // widget pinta sobre transparente, y cualquier visor enseña eso como
        // blanco. Ya se estuvo a punto de calibrar contra un fondo inexistente.
        RepaintBoundary(
          key: const ValueKey('retrato'),
          child: ColoredBox(
            color: tema.scaffoldBackgroundColor,
            child: const ReadinessPage(readiness: sinCli),
          ),
        ),
        theme: tema,
      );
      // `MaterialApp` **anima** el cambio de tema, y estos dos retratos comparten
      // el mismo árbol: con los 100 ms de `pumpScreen`, el claro salía a medio
      // camino del oscuro — medido, `#767A81`, que es justo la mitad de
      // `#E9EEF5`. Se espera a que la transición acabe.
      await tester.pump(const Duration(milliseconds: 400));

      final boundary =
          tester.renderObject(find.byKey(const ValueKey('retrato')))
              as RenderRepaintBoundary;
      // `runAsync` y no un `await` a secas: `toImage` espera al hilo de
      // rasterizado, y el reloj de una prueba de widgets no lo hace avanzar —
      // la primera versión de esto **colgó la suite entera** sin decir nada.
      final capturado = await tester.runAsync(() async {
        final imagen = await boundary.toImage();
        return (
          png: (await imagen.toByteData(format: ui.ImageByteFormat.png))!,
          crudo: (await imagen.toByteData(format: ui.ImageByteFormat.rawRgba))!,
        );
      });

      File(
        '$salida/nexus-comprobacion-$nombre.png',
      ).writeAsBytesSync(capturado!.png.buffer.asUint8List());

      // El aserto que convierte esto en una prueba y no en un diagnóstico: la
      // esquina tiene que ser el fondo del tema. Si vuelve a retratarse a medio
      // camino, aquí se ve.
      final crudo = capturado.crudo;
      expect(
        Color.fromARGB(
          255,
          crudo.getUint8(0),
          crudo.getUint8(1),
          crudo.getUint8(2),
        ),
        tema.scaffoldBackgroundColor,
        reason: 'el retrato en $nombre no salió sobre el fondo de su tema',
      );
    }

    expect(File('$salida/nexus-comprobacion-claro.png').existsSync(), isTrue);
  });
}
