import 'package:nexus/features/workspace/domain/entities/workspace.dart';

/// Dónde viven las carpetas emparejadas y sus permisos entre arranques.
abstract class WorkspaceStore {
  Future<Workspace> read();

  Future<void> save(Workspace workspace);
}

/// Quien sabe pedirle una carpeta al usuario. Es un puerto y no una llamada
/// directa al selector porque abrir un diálogo del sistema es un detalle de
/// plataforma: el dominio solo necesita «devuélveme una ruta o nada».
abstract class FolderPicker {
  /// `null` si el usuario cancela.
  Future<String?> pickFolder();
}
