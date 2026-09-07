import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/features/assistant/presentation/pages/home_page.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/domain/entities/workspace.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/screen_harness.dart';

/// El menú del permiso dice **de qué carpeta** habla.
///
/// 🔴 **Es la mitad que faltaba del permiso por carpeta.** Desde el #278 el
/// permiso es de la carpeta, pero el menú seguía rotulado en genérico —«Puede
/// editar»— y eso es exactamente lo que hizo creer que era de la app: el reporte
/// que destapó todo empezó con «la carpeta ya tiene permiso de puede editar».
/// Con tres conversaciones abiertas sobre repos distintos, un rótulo sin nombre
/// no dice a cuál se le está dando.
///
/// Los dos textos estaban traducidos en los dos idiomas y sin usar desde antes,
/// escritos para esto: eran deuda esperando a que la decisión existiera.
const _carpeta = '/Users/alguien/Workspace/front-mobile-b2c';

void main() {
  const textos = NexusStringsEs();
  late Directory support;

  setUp(() {
    support = prepareScreenTest();
    // 🔴 **Con el tour por ver, no se puede pulsar nada.** Su velo se pinta en
    // el `Overlay` de la app y cubre la ventana entera, así que el toque no
    // llega al compositor y la prueba falla por un sitio que no tiene nada que
    // ver con lo que afirma.
    SharedPreferences.setMockInitialValues({'tour_seen': true});
  });
  tearDown(() => support.deleteSync(recursive: true));

  testWidgets('las dos opciones llevan el nombre de la carpeta', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      const HomePage(),
      overrides: [
        workspaceControllerProvider.overrideWith(
          () => FixedWorkspace(
            const Workspace(
              folders: [
                PairedFolder(path: _carpeta, modality: FolderModality.textOnly),
              ],
              activePath: _carpeta,
            ),
          ),
        ),
      ],
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Por el botón y no por su texto: el rótulo del chip vive dentro de una
    // fila con el icono, y apuntar al texto suelto no acierta al botón.
    await tester.tap(find.byType(PopupMenuButton<FilePermission>));
    // `pump` y no `pumpAndSettle`: el orbe se anima en bucle y el árbol no se
    // queda quieto nunca — la misma piedra que ya está anotada en las otras
    // pruebas de esta pantalla.
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text(textos.canEditFilesIn('front-mobile-b2c')),
      findsOneWidget,
      reason: 'sin el nombre no se sabe a qué carpeta se le está dando',
    );
    expect(find.text(textos.readOnlyIn('front-mobile-b2c')), findsOneWidget);
  });
}
