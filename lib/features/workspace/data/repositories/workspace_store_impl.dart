import 'package:file_selector/file_selector.dart';
import 'package:nexus/features/workspace/data/datasources/workspace_preferences_data_source.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/domain/entities/workspace.dart';
import 'package:nexus/features/workspace/domain/repositories/workspace_store.dart';

class WorkspaceStoreImpl implements WorkspaceStore {
  const WorkspaceStoreImpl(this._preferences);

  final WorkspacePreferencesDataSource _preferences;

  @override
  Future<Workspace> read() async {
    final json = await _preferences.read();
    if (json == null) return const Workspace();

    // Igual que con la modalidad, un valor desconocido cae en lo restrictivo.
    final permiso = FilePermission.values.firstWhere(
      (value) => value.name == json['permission'],
      orElse: () => FilePermission.readOnly,
    );

    final folders = <PairedFolder>[];
    for (final entry in json['folders'] as List<dynamic>? ?? const []) {
      if (entry is! Map<String, dynamic>) continue;
      final folder = PairedFolder.fromJson(entry);
      if (folder == null) continue;
      // 🔴 **Una carpeta guardada antes de que el permiso fuera suyo hereda el
      // de la app**, que es el que tenía de hecho: sin esto, al actualizar
      // Nexus todas las carpetas se quedarían en solo lectura de golpe y la
      // escritura habría que volver a darla una por una, sin que nada
      // explicara por qué. La clave se escribe siempre —también en `false`—
      // así que su ausencia solo puede significar «esto viene de antes».
      folders.add(
        entry.containsKey('puedeEditar')
            ? folder
            : folder.copyWith(puedeEditar: permiso.canWrite),
      );
    }

    final activePath = json['activePath'] as String?;
    return Workspace(
      folders: folders,
      // Una ruta activa que ya no está en la lista se descarta: quedaría
      // apuntando a una carpeta sin permisos declarados.
      activePath: folders.any((folder) => folder.path == activePath)
          ? activePath
          : null,
      permission: permiso,
    );
  }

  @override
  Future<void> save(Workspace workspace) {
    return _preferences.write({
      'folders': workspace.folders.map((folder) => folder.toJson()).toList(),
      'activePath': workspace.activePath,
      'permission': workspace.permission.name,
    });
  }
}

/// El diálogo nativo de macOS para elegir carpeta.
class SystemFolderPicker implements FolderPicker {
  const SystemFolderPicker();

  @override
  Future<String?> pickFolder() =>
      getDirectoryPath(confirmButtonText: 'Emparejar');
}
