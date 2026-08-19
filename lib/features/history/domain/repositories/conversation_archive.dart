import 'package:nexus/features/history/domain/entities/conversation_record.dart';

/// Dónde acaban guardadas las conversaciones.
///
/// Hay tres destinos y son del usuario, no del programa: una carpeta suya, un
/// vault de Obsidian, o Notion. Los dos primeros son el mismo mecanismo —un
/// vault **es** una carpeta de Markdown— y se distinguen en cómo se enlazan las
/// notas; el tercero es una API.
abstract class ConversationArchive {
  /// Guarda —o actualiza— la conversación. Se llama varias veces sobre la misma
  /// conversación según avanza, así que tiene que ser idempotente: la última
  /// escritura manda y no se acumulan copias.
  Future<void> save(ConversationRecord record);
}

/// Los destinos que el usuario puede elegir.
enum ArchiveDestination {
  /// Sin guardar nada. Es el estado de partida: archivar conversaciones fuera
  /// de la app es una decisión suya, no algo que ocurra por omisión.
  none,

  /// Una carpeta cualquiera, con Markdown legible en cualquier editor.
  folder,

  /// Un vault de Obsidian: lo mismo, con enlaces `[[wiki]]` que agrupan cada
  /// proyecto en su propio grafo.
  obsidian,

  /// Notion, por su API.
  notion;

  static ArchiveDestination fromStored(String? value) => switch (value) {
    'folder' => ArchiveDestination.folder,
    'obsidian' => ArchiveDestination.obsidian,
    'notion' => ArchiveDestination.notion,
    _ => ArchiveDestination.none,
  };

  String get stored => name;

  /// Si este destino guarda en el disco del usuario y necesita que elija dónde.
  bool get needsFolder =>
      this == ArchiveDestination.folder || this == ArchiveDestination.obsidian;
}
