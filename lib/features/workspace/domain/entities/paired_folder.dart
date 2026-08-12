import 'package:flutter/foundation.dart';

/// Qué puede **salir** de una carpeta hacia el servicio de voz.
///
/// Es el segundo eje de permisos, decidido en i5: no basta con controlar qué
/// puede *hacer* Nexus con una carpeta, porque en cuanto Gemini narra un
/// resultado, lo que Claude leyó del repo viaja hacia Google dentro del
/// `toolResponse`. Restringir solo el micrófono dejaría la fuga abierta por el
/// otro lado, así que en [textOnly] **Gemini no participa**: se trabaja por el
/// camino de escribir → Claude → subtítulo.
enum FolderModality {
  /// Nada sale hacia el servicio de voz. Ni tu micrófono, ni lo que Claude lea.
  textOnly,

  /// Se puede abrir sesión de voz sobre esta carpeta.
  voice;

  bool get allowsVoice => this == FolderModality.voice;
}

/// Una carpeta emparejada: el sitio donde Nexus tiene permiso para trabajar.
@immutable
class PairedFolder {
  const PairedFolder({required this.path, required this.modality});

  final String path;
  final FolderModality modality;

  /// Lo que se enseña en la interfaz: la ruta con `~` en vez del home, que es
  /// como la escribe el mockup y como la lee cualquiera.
  String displayPath(String home) {
    if (home.isNotEmpty && path.startsWith(home)) {
      return '~${path.substring(home.length)}';
    }
    return path;
  }

  /// El último tramo de la ruta, para cuando no cabe entera.
  String get name {
    final trimmed = path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    final slash = trimmed.lastIndexOf('/');
    return slash == -1 ? trimmed : trimmed.substring(slash + 1);
  }

  PairedFolder copyWith({FolderModality? modality}) =>
      PairedFolder(path: path, modality: modality ?? this.modality);

  Map<String, dynamic> toJson() => {'path': path, 'modality': modality.name};

  static PairedFolder? fromJson(Map<String, dynamic> json) {
    final path = json['path'] as String?;
    if (path == null || path.isEmpty) return null;
    return PairedFolder(
      path: path,
      // Si el valor guardado no se reconoce se cae al modo restrictivo, no al
      // permisivo: un dato corrupto no puede abrir el micrófono.
      modality: FolderModality.values.firstWhere(
        (value) => value.name == json['modality'],
        orElse: () => FolderModality.textOnly,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PairedFolder && other.path == path && other.modality == modality;

  @override
  int get hashCode => Object.hash(path, modality);
}
