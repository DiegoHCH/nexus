import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/features/workspace/domain/entities/config_del_repo.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/domain/entities/workspace.dart';
import 'package:nexus/features/workspace/presentation/pages/settings/permissions_section.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:nexus/features/workspace/presentation/widgets/permission_switch.dart';

import 'support/screen_harness.dart';

/// La pantalla donde se decide **qué carpeta puede escribir y cuál sale hacia
/// la voz**.
///
/// 🔴 **Estaba al 38,9 %, y es la más delicada de Ajustes.** El mismo día
/// aparecieron dos fallos de permisos —el tope de escritura que no viajaba al
/// enrutar un encargo, y la frase de escritura que se saltaba hablando—. Los dos
/// estaban en el cableado y no aquí, así que cubrir esta pantalla no los habría
/// pescado. Pero **es el sitio al que iría alguien a comprobar que un cambio así
/// no rompió nada**, y no había nada que lo sujetara.
const _carpeta = '/Users/alguien/Workspace/front-mobile-b2c';
const _otra = '/Users/alguien/personal/nexus';

class _Espacio extends WorkspaceController {
  _Espacio(this._inicial);

  final Workspace _inicial;

  @override
  Workspace build() => _inicial;
}

void main() {
  const textos = NexusStringsEs();

  Future<void> abrir(
    WidgetTester tester, {
    FilePermission permiso = FilePermission.readOnly,
    List<PairedFolder>? carpetas,
    Map<String, ConfigDelRepo> delRepo = const {},
    String? activa = _carpeta,
    ThemeData? tema,
  }) => pumpScreen(
    tester,
    const Scaffold(body: PermissionsSection()),
    theme: tema,
    overrides: [
      workspaceControllerProvider.overrideWith(
        () => _Espacio(
          Workspace(
            folders:
                carpetas ??
                [PairedFolder(path: _carpeta, modality: FolderModality.voice)],
            activePath: activa,
            permission: permiso,
            delRepo: delRepo,
          ),
        ),
      ),
    ],
  );

  void sinDesbordar(WidgetTester tester) {
    expect(tester.takeException(), isNull, reason: 'desbordó o reventó');
  }

  group('el permiso de archivos', () {
    testWidgets('se enseña siempre, y nace en solo lectura', (tester) async {
      await abrir(tester);

      expect(find.text(textos.filePermissionsTitle), findsOneWidget);
      final interruptor = tester.widget<PermissionSwitch>(
        find.byType(PermissionSwitch),
      );
      expect(interruptor.permission, FilePermission.readOnly);
      expect(interruptor.bloqueado, isFalse);
      sinDesbordar(tester);
    });

    testWidgets('con edición concedida, se ve concedida', (tester) async {
      await abrir(tester, permiso: FilePermission.canEdit);

      expect(
        tester
            .widget<PermissionSwitch>(find.byType(PermissionSwitch))
            .permission,
        FilePermission.canEdit,
      );
    });

    // 🔴 **El repositorio solo puede apretar.** Si su `.nexus/config.json` dice
    // solo lectura, el interruptor se bloquea: no se puede subir a mano lo que
    // el repo bajó. Es la mitad de la promesa de `docs/NEXUS-CONFIG.md`.
    testWidgets('si el repo manda solo lectura, el interruptor se bloquea', (
      tester,
    ) async {
      await abrir(
        tester,
        delRepo: const {_carpeta: ConfigDelRepo(soloLectura: true)},
      );

      expect(
        tester
            .widget<PermissionSwitch>(find.byType(PermissionSwitch))
            .bloqueado,
        isTrue,
        reason: 'el repo aprieta y no se puede aflojar desde aquí',
      );
    });

    // Y la otra mitad: un repo que **no** dice nada no bloquea nada.
    testWidgets('un repo que no lo pide no bloquea', (tester) async {
      await abrir(
        tester,
        delRepo: const {
          _carpeta: ConfigDelRepo(comandosVetados: ['rm']),
        },
      );

      expect(
        tester
            .widget<PermissionSwitch>(find.byType(PermissionSwitch))
            .bloqueado,
        isFalse,
      );
    });

    // El bloqueo es de **la carpeta activa**: la config de otra no manda aquí.
    testWidgets('la config de otra carpeta no bloquea esta', (tester) async {
      await abrir(
        tester,
        delRepo: const {_otra: ConfigDelRepo(soloLectura: true)},
      );

      expect(
        tester
            .widget<PermissionSwitch>(find.byType(PermissionSwitch))
            .bloqueado,
        isFalse,
        reason: 'apretar la de al lado apretaría la carpeta equivocada',
      );
    });
  });

  group('lo que declara el repositorio', () {
    testWidgets('si declara algo, se enseña', (tester) async {
      await abrir(
        tester,
        delRepo: const {
          _carpeta: ConfigDelRepo(
            soloTexto: true,
            comandosVetados: ['rm', 'build_runner'],
          ),
        },
      );

      expect(find.text(textos.repoDeclaraTitle), findsOneWidget);
      expect(find.text('· ${textos.repoSoloTexto}'), findsOneWidget);
      expect(
        find.text('· ${textos.repoComandosVetados(2)}'),
        findsOneWidget,
        reason: 'se dice cuántos hay, no cuáles: la lista vive en el repo',
      );
      sinDesbordar(tester);
    });

    testWidgets('sus avisos también', (tester) async {
      await abrir(
        tester,
        delRepo: const {
          _carpeta: ConfigDelRepo(avisos: ['la clave «modelo» no se entendió']),
        },
      );

      expect(find.textContaining('no se entendió'), findsOneWidget);
    });

    testWidgets('y si no declara nada, no ocupa sitio', (tester) async {
      await abrir(tester);

      expect(find.text(textos.repoDeclaraTitle), findsNothing);
      sinDesbordar(tester);
    });
  });

  group('las carpetas', () {
    testWidgets('sin ninguna emparejada no revienta', (tester) async {
      await abrir(tester, carpetas: const [], activa: null);

      expect(find.text(textos.filePermissionsTitle), findsOneWidget);
      sinDesbordar(tester);
    });

    // Seis carpetas con rutas largas es lo normal en cuanto se trabaja con dos
    // clientes, y es donde una fila se sale.
    testWidgets('seis carpetas con rutas largas no desbordan', (tester) async {
      await abrir(
        tester,
        carpetas: [
          for (var i = 0; i < 6; i++)
            PairedFolder(
              path:
                  '/Users/alguien/Workspace/cliente-$i/'
                  'monorepo-de-la-plataforma/apps/front-mobile-b2c-$i',
              modality: i.isEven
                  ? FolderModality.voice
                  : FolderModality.textOnly,
            ),
        ],
      );

      // Y que estén de verdad: sin esto la prueba pasaría igual pintando cero
      // filas, que es como pasan en vacío las pruebas de desbordamiento.
      expect(find.byType(PermissionSwitch), findsOneWidget);
      expect(find.textContaining('front-mobile-b2c-5'), findsWidgets);
      sinDesbordar(tester);
    });

    testWidgets('y también en claro', (tester) async {
      await abrir(
        tester,
        permiso: FilePermission.canEdit,
        delRepo: const {_carpeta: ConfigDelRepo(soloLectura: true)},
        tema: NexusTheme.light(),
      );

      sinDesbordar(tester);
    });
  });
}
