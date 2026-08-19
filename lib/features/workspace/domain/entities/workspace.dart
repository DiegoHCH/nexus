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

  /// La carpeta de **solo texto** que contiene [path], si alguna.
  ///
  /// Existe por el único hueco que le quedaba a i5. La carpeta de artefactos —el
  /// cajón de salida— es la única excepción a «ninguna otra carpeta»: viaja como
  /// `--add-dir` en **todos** los encargos. Si cae dentro de una carpeta
  /// emparejada en solo texto, una conversación con voz podría leer de ahí y
  /// Gemini narrarlo, que es exactamente lo que ese modo viene a impedir.
  ///
  /// Se mira por prefijo y no por igualdad porque `--add-dir` da acceso a **todo
  /// el subárbol**: el cajón puesto en una subcarpeta abre la misma puerta que
  /// puesto en la raíz.
  PairedFolder? textOnlyOwnerOf(String? path) {
    if (path == null || path.isEmpty) return null;
    final limpio = path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;

    for (final folder in folders) {
      if (folder.modality.allowsVoice) continue;
      if (limpio == folder.path || limpio.startsWith('${folder.path}/')) {
        return folder;
      }
    }
    return null;
  }

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
