import 'package:flutter/foundation.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';

/// Qué puede **hacer** Nexus con tus archivos. Es el interruptor que el diseño
/// pone siempre visible en la barra superior, y va a nivel de app, no de
/// carpeta: es la pregunta «¿hoy estás dejando que toque cosas?».
///
/// Cómo se traduce a la herramienta concreta es asunto de la capa de datos:
/// aquí solo existe la pregunta «¿puede escribir?».
enum FilePermission {
  readOnly,
  canEdit;

  bool get canWrite => this == FilePermission.canEdit;
}

/// El estado completo de los permisos: qué carpetas hay emparejadas, en cuál
/// se está trabajando, y qué puede hacer Nexus con los archivos.
@immutable
class Workspace {
  const Workspace({
    this.folders = const [],
    this.activePath,
    this.permission = FilePermission.readOnly,
  });

  final List<PairedFolder> folders;

  /// La carpeta sobre la que trabaja Claude ahora mismo. `null` mientras no
  /// haya ninguna emparejada, y entonces **no hay dónde trabajar**: sin esto,
  /// `claude -p` heredaba el directorio de la app, que para un bundle lanzado
  /// por launchd es `/`, y cualquier encargo respondía sobre la raíz del disco.
  final String? activePath;

  final FilePermission permission;

  PairedFolder? get active {
    if (activePath == null) return null;
    for (final folder in folders) {
      if (folder.path == activePath) return folder;
    }
    return null;
  }

  bool get isEmpty => folders.isEmpty;

  /// Si se puede abrir una sesión de voz ahora mismo. Sin carpeta activa no se
  /// abre: hablarle a Nexus sin sitio donde trabajar solo produce respuestas
  /// sobre la nada.
  bool get allowsVoice => active?.modality.allowsVoice ?? false;

  Workspace copyWith({
    List<PairedFolder>? folders,
    String? activePath,
    bool clearActive = false,
    FilePermission? permission,
  }) {
    return Workspace(
      folders: folders ?? this.folders,
      activePath: clearActive ? null : (activePath ?? this.activePath),
      permission: permission ?? this.permission,
    );
  }
}
