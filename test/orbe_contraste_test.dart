import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/features/assistant/presentation/orb/nexus_orb.dart';
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';

/// Que el orbe **se vea** en los dos temas.
///
/// El dormido casi no se veía en claro y eso no lo detecta ninguna aserción de
/// las normales: no lanza, no desborda, no rompe una regla — solo se pierde
/// contra el fondo. Medido, tenía **1,80:1** de contraste contra los 3,3:1 del
/// oscuro, o sea la mitad.
///
/// Se mide el contraste **local** —el punto contra lo que tiene alrededor— y no
/// contra una esquina de la imagen. Con la esquina, subir el halo mejoraba el
/// número mientras empeoraba lo que se ve: teñía toda la zona del orbe de azul
/// y los puntos se separaban menos de su entorno. Esa medida mentía.
///
/// El suelo es holgado a propósito: el orbe gira, así que según el fotograma que
/// toque hay más o menos puntos de frente y la cifra se mueve unas décimas.
void main() {
  /// Suelo con margen de verdad.
  ///
  /// Estaba en 2,4 y el oscuro llegó a dar **2,55** en una corrida: el orbe gira
  /// y su fase arranca aleatoria —a propósito, para que dos orbes no respiren
  /// sincronizados— así que según el fotograma hay más o menos puntos de frente
  /// y la cifra se mueve hasta siete décimas. Un suelo a 0,15 de un valor
  /// observado es una prueba que falla sola algún martes.
  ///
  /// 2,0 sigue estando muy por encima del defecto que esto vigila —1,80:1, el
  /// orbe perdido en el fondo claro— y por debajo de todo lo medido después.
  const suelo = 2.0;

  double luminancia(int r, int g, int b) {
    double canal(int v) {
      final x = v / 255;
      return x <= 0.03928
          ? x / 12.92
          : math.pow((x + 0.055) / 1.055, 2.4) as double;
    }

    return 0.2126 * canal(r) + 0.7152 * canal(g) + 0.0722 * canal(b);
  }

  double contraste(int a, int b) {
    final la = luminancia((a >> 16) & 0xFF, (a >> 8) & 0xFF, a & 0xFF);
    final lb = luminancia((b >> 16) & 0xFF, (b >> 8) & 0xFF, b & 0xFF);
    final alto = math.max(la, lb), bajo = math.min(la, lb);
    return (alto + 0.05) / (bajo + 0.05);
  }

  /// El contraste del punto que más destaca contra su propio entorno.
  Future<double> mejorContraste(WidgetTester tester, ThemeData tema) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final clave = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: tema,
        home: Scaffold(
          body: RepaintBoundary(
            key: clave,
            // Con el fondo del tema **dentro** del recorte: sin él el orbe se
            // captura sobre transparente y se acaba juzgando el contraste
            // contra un blanco que no existe.
            child: ColoredBox(
              color: tema.scaffoldBackgroundColor,
              child: const SizedBox(
                width: 600,
                height: 600,
                child: NexusOrb(state: NexusOrbState.sleep),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    var mejor = 1.0;
    await tester.runAsync(() async {
      final limite =
          clave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final imagen = await limite.toImage();
      final datos = await imagen.toByteData(format: ui.ImageByteFormat.rawRgba);
      final bytes = datos!.buffer.asUint8List();
      final ancho = imagen.width;

      int pixel(int x, int y) {
        final i = (y * ancho + x) * 4;
        return (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
      }

      for (var y = 40; y < imagen.height - 40; y += 3) {
        for (var x = 40; x < ancho - 40; x += 3) {
          final c = contraste(pixel(x, y), pixel(x - 20, y));
          if (c > mejor) mejor = c;
        }
      }

      // La imagen se deja a mano para poder mirarla: el número dice si separa,
      // no si está bonito.
      final png = await imagen.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/orbe')..createSync(recursive: true);
      final nombre = tema.brightness == Brightness.light ? 'claro' : 'oscuro';
      File(
        '${dir.path}/contraste-$nombre.png',
      ).writeAsBytesSync(png!.buffer.asUint8List());
    });
    return mejor;
  }

  testWidgets('el orbe dormido se ve en oscuro', (tester) async {
    expect(await mejorContraste(tester, NexusTheme.dark()), greaterThan(suelo));
  });

  testWidgets('y también en claro, que era el que se perdía', (tester) async {
    final claro = await mejorContraste(tester, NexusTheme.light());
    expect(
      claro,
      greaterThan(suelo),
      reason:
          'con las opacidades calibradas solo para el tema oscuro esto daba '
          '1,80:1 y el orbe parecía polvo sobre la hoja',
    );
  });
}
