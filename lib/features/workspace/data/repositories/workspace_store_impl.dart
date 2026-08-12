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

    final folders = <PairedFolder>[];
    for (final entry in json['folders'] as List<dynamic>? ?? const []) {
      if (entry is! Map<String, dynamic>) continue;
      final folder = PairedFolder.fromJson(entry);
      if (folder != null) folders.add(folder);
    }

    final activePath = json['activePath'] as String?;
    return Workspace(
      folders: folders,
      // Una ruta activa que ya no está en la lista se descarta: quedaría
      // apuntando a una carpeta sin permisos declarados.
      activePath: folders.any((folder) => folder.path == activePath)
          ? activePath
          : null,
      // Igual que con la modalidad, un valor desconocido cae en lo restrictivo.
      permission: FilePermission.values.firstWhere(
        (value) => value.name == json['permission'],
        orElse: () => FilePermission.readOnly,
      ),
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
