import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/features/workspace/data/datasources/workspace_preferences_data_source.dart';
import 'package:nexus/features/workspace/data/repositories/workspace_store_impl.dart';
import 'package:nexus/features/workspace/domain/entities/config_del_repo.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/domain/entities/workspace.dart';
import 'package:nexus/features/workspace/domain/repositories/workspace_store.dart';
import 'package:nexus/features/workspace/domain/usecases/el_permiso_que_vale.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

/// El permiso de escritura, ahora **por carpeta**.
///
/// 🔴 **Era de la app y todo el mundo creía que no.** El reporte que lo destapó
/// empezó con «la carpeta ya tiene permiso de puede editar», que es el modelo
/// mental natural con tres conversaciones abiertas sobre repos distintos — y con
/// un solo interruptor global, dárselo a tu proyecto se lo daba también al del
/// trabajo, sin que nada lo dijera.
const _mio = '/Users/alguien/personal/nexus';
const _delTrabajo = '/Users/alguien/Workspace/front-mobile-b2c';

Workspace _espacio({
  FilePermission tope = FilePermission.canEdit,
  bool mio = true,
  bool delTrabajo = false,
  Map<String, ConfigDelRepo> delRepo = const {},
}) => Workspace(
  folders: [
    PairedFolder(path: _mio, modality: FolderModality.voice, puedeEditar: mio),
    PairedFolder(
      path: _delTrabajo,
      modality: FolderModality.textOnly,
      puedeEditar: delTrabajo,
    ),
  ],
  activePath: _mio,
  permission: tope,
  delRepo: delRepo,
);

class _Prefs implements WorkspacePreferencesDataSource {
  _Prefs(this.guardado);

  Map<String, dynamic>? guardado;

  @override
  Future<Map<String, dynamic>?> read() async => guardado;

  @override
  Future<void> write(Map<String, dynamic> json) async => guardado = json;
}

class _Store implements WorkspaceStore {
  _Store(this.workspace);

  Workspace workspace;

  @override
  Future<Workspace> read() async => workspace;

  @override
  Future<void> save(Workspace nuevo) async => workspace = nuevo;
}

void main() {
  group('quién opina, y en qué orden', () {
    test('la carpeta decide dentro de lo que el tope permite', () {
      final espacio = _espacio();

      expect(ElPermisoQueVale.enLaCarpeta(espacio, _mio), isTrue);
      expect(
        ElPermisoQueVale.enLaCarpeta(espacio, _delTrabajo),
        isFalse,
        reason: 'dar permiso en un repo no puede darlo en el de al lado',
      );
    });

    test('el tope de la app cierra todas', () {
      final espacio = _espacio(tope: FilePermission.readOnly, delTrabajo: true);

      expect(ElPermisoQueVale.enLaCarpeta(espacio, _mio), isFalse);
      expect(ElPermisoQueVale.enLaCarpeta(espacio, _delTrabajo), isFalse);
    });

    // Un `.nexus/config.json` puede negarse, y eso gana. Lo que no puede es
    // concederse: ampliar permisos es de quien empareja la carpeta, nunca del
    // contenido de la carpeta.
    test('el repo puede negarse, no concederse', () {
      final niega = _espacio(
        delRepo: const {_mio: ConfigDelRepo(soloLectura: true)},
      );
      expect(ElPermisoQueVale.enLaCarpeta(niega, _mio), isFalse);

      final quisiera = _espacio(
        mio: false,
        delRepo: const {
          _mio: ConfigDelRepo(comandosVetados: ['rm']),
        },
      );
      expect(ElPermisoQueVale.enLaCarpeta(quisiera, _mio), isFalse);
    });

    // La carpeta de documentos, o cualquier ruta que llegue de fuera: la
    // respuesta segura es no.
    test('una carpeta que no está emparejada no escribe', () {
      expect(
        ElPermisoQueVale.enLaCarpeta(_espacio(), '/Users/alguien/documentos'),
        isFalse,
      );
      expect(ElPermisoQueVale.enLaCarpeta(_espacio(), null), isFalse);
    });
  });

  group('al cambiarlo desde el compositor', () {
    late ProviderContainer contenedor;
    late _Store store;

    Future<WorkspaceController> mando({
      FilePermission tope = FilePermission.canEdit,
    }) async {
      store = _Store(_espacio(tope: tope, mio: false));
      contenedor = ProviderContainer(
        overrides: [workspaceStoreProvider.overrideWithValue(store)],
      );
      addTearDown(contenedor.dispose);
      final controller = contenedor.read(workspaceControllerProvider.notifier);
      await controller.recargar();
      return controller;
    }

    test('solo cambia esa carpeta', () async {
      final controller = await mando();
      await controller.setPermisoDeCarpeta(_mio, true);

      final espacio = contenedor.read(workspaceControllerProvider);
      expect(ElPermisoQueVale.enLaCarpeta(espacio, _mio), isTrue);
      expect(ElPermisoQueVale.enLaCarpeta(espacio, _delTrabajo), isFalse);
      // Y queda guardado: el permiso de una carpeta no puede durar lo que dura
      // la ventana abierta.
      expect(store.workspace.folders.first.puedeEditar, isTrue);
    });

    // 🔴 Con el tope cerrado, dar permiso aquí no haría escribir: sería un
    // control que no hace lo que dice, que es peor que uno que falta. Se sube
    // el tope y **se avisa en el menú antes de elegir**.
    test('con el tope cerrado, lo sube también', () async {
      final controller = await mando(tope: FilePermission.readOnly);
      await controller.setPermisoDeCarpeta(_mio, true);

      final espacio = contenedor.read(workspaceControllerProvider);
      expect(espacio.permission, FilePermission.canEdit);
      expect(ElPermisoQueVale.enLaCarpeta(espacio, _mio), isTrue);
      expect(
        ElPermisoQueVale.enLaCarpeta(espacio, _delTrabajo),
        isFalse,
        reason:
            'subir el tope no reparte permisos: las demás siguen como estaban',
      );
    });

    test('quitarlo no cierra el tope de todos', () async {
      final controller = await mando();
      await controller.setPermisoDeCarpeta(_mio, true);
      await controller.setPermisoDeCarpeta(_mio, false);

      final espacio = contenedor.read(workspaceControllerProvider);
      expect(ElPermisoQueVale.enLaCarpeta(espacio, _mio), isFalse);
      expect(
        espacio.permission,
        FilePermission.canEdit,
        reason: 'quitar la escritura en un sitio no es cerrar el cerrojo',
      );
    });
  });

  // 🔴 **Lo que se guardó antes de que el permiso fuera de la carpeta.** Sin
  // esto, al actualizar Nexus todas las carpetas se quedarían en solo lectura
  // de golpe y habría que volver a dar la escritura una por una, sin que nada
  // explicara por qué.
  group('lo guardado antes de este cambio', () {
    test('hereda el permiso que tenía la app', () async {
      final prefs = _Prefs({
        'folders': [
          {'path': _mio, 'modality': 'voice'},
        ],
        'activePath': _mio,
        'permission': 'canEdit',
      });

      final espacio = await WorkspaceStoreImpl(prefs).read();

      expect(espacio.folders.single.puedeEditar, isTrue);
      expect(ElPermisoQueVale.enLaCarpeta(espacio, _mio), isTrue);
    });

    test('y si la app estaba en solo lectura, nace cerrada', () async {
      final prefs = _Prefs({
        'folders': [
          {'path': _mio, 'modality': 'voice'},
        ],
        'permission': 'readOnly',
      });

      final espacio = await WorkspaceStoreImpl(prefs).read();

      expect(espacio.folders.single.puedeEditar, isFalse);
    });

    // La clave se escribe siempre, también en `false`: es lo que separa «esta
    // carpeta dijo no» de «esta carpeta viene de antes y nunca eligió».
    test(
      'un no guardado a mano se respeta, aunque la app pueda escribir',
      () async {
        final prefs = _Prefs({
          'folders': [
            {'path': _mio, 'modality': 'voice', 'puedeEditar': false},
          ],
          'permission': 'canEdit',
        });

        final espacio = await WorkspaceStoreImpl(prefs).read();

        expect(espacio.folders.single.puedeEditar, isFalse);
        expect(espacio.permission, FilePermission.canEdit);
      },
    );
  });
}
