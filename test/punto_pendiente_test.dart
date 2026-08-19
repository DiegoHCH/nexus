import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/features/updates/domain/entities/release_check.dart';
import 'package:nexus/features/updates/domain/entities/update_stage.dart';
import 'package:nexus/features/updates/presentation/providers/updates_providers.dart';
import 'package:nexus/features/updates/presentation/widgets/pending_dot.dart';

import 'support/screen_harness.dart';

/// El punto rojo: que quede rastro de lo que se descartó.
///
/// Nace de un caso concreto: pulsar «más tarde» dejaba el aviso sin ninguna huella,
/// así que la versión nueva desaparecía de la vista hasta que el actualizador
/// volviera a preguntar —dos horas después—. «Ahora no» no es «nunca».
///
/// Lo que se vigila aquí es lo que puede salir mal en silencio: que el punto
/// aparezca cuando no hay nada pendiente, que desaparezca cuando sí lo hay, y que
/// **mueva de sitio lo que envuelve** — un icono que se desplaza al aparecer un
/// aviso molesta más que el aviso.
class _Fijo extends UpdatesController {
  _Fijo(this._e);
  final UpdatesState _e;
  @override
  UpdatesState build() => _e;
}

void main() {
  late Directory support;
  setUp(() => support = prepareScreenTest());
  tearDown(() => support.deleteSync(recursive: true));

  Future<Size> montar(WidgetTester tester, {String? publicada}) async {
    await pumpScreen(
      tester,
      const Center(
        child: PendingDot(child: Icon(Icons.add, size: 16, key: ValueKey('mas'))),
      ),
      overrides: [
        updatesControllerProvider.overrideWith(
          () => _Fijo(
            UpdatesState(
              notice: ReleaseCheck(current: '0.0.3', latest: publicada),
              stage: const UpdateIdle(),
            ),
          ),
        ),
      ],
    );
    return tester.getSize(find.byKey(const ValueKey('mas')));
  }

  testWidgets('sin nada pendiente no hay punto', (tester) async {
    await montar(tester);
    expect(find.byType(Icon), findsOne, reason: 'solo el icono envuelto');
    expect(find.byType(Stack), findsNothing, reason: 'ni se monta el envoltorio');
  });

  testWidgets('con una versión sin instalar aparece', (tester) async {
    await montar(tester, publicada: '0.0.4');
    // El punto es un contenedor circular rojo; se busca por su decoración para no
    // depender de cómo esté compuesto.
    final puntos = tester.widgetList<Container>(find.byType(Container)).where((c) {
      final d = c.decoration;
      return d is BoxDecoration && d.shape == BoxShape.circle;
    });
    expect(puntos.length, 1);
  });

  testWidgets('y no mueve ni redimensiona lo que envuelve', (tester) async {
    // El caso que se vigila: si el punto entrara en el flujo, el «+» cambiaría de
    // tamaño o de sitio justo cuando aparece una versión nueva.
    final sin = await montar(tester);
    final con = await montar(tester, publicada: '0.0.4');
    expect(con, sin);
  });

  testWidgets('una versión más vieja no cuenta como pendiente', (tester) async {
    await montar(tester, publicada: '0.0.1');
    expect(find.byType(Stack), findsNothing);
  });
}
