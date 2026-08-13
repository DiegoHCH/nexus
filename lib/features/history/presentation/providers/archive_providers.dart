import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/history/data/repositories/markdown_archive.dart';
import 'package:nexus/features/history/domain/repositories/conversation_archive.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dónde se archivan las conversaciones y en qué carpeta, recordado entre
/// arranques.
@immutable
class ArchiveSettings {
  const ArchiveSettings({
    this.destination = ArchiveDestination.none,
    this.folderPath,
  });

  final ArchiveDestination destination;

  /// La carpeta elegida —o el vault—. Con destino de disco y sin carpeta no se
  /// guarda nada: no se inventa un sitio en el que dejar tus conversaciones.
  final String? folderPath;

  bool get isReady => switch (destination) {
    ArchiveDestination.none => false,
    ArchiveDestination.folder ||
    ArchiveDestination.obsidian => (folderPath ?? '').isNotEmpty,
    // Todavía no: falta la parte de la API.
    ArchiveDestination.notion => false,
  };

  ArchiveSettings copyWith({
    ArchiveDestination? destination,
    String? folderPath,
  }) => ArchiveSettings(
    destination: destination ?? this.destination,
    folderPath: folderPath ?? this.folderPath,
  );
}

class ArchiveController extends Notifier<ArchiveSettings> {
  static const _destinationKey = 'archive_destination';
  static const _folderKey = 'archive_folder';

  @override
  ArchiveSettings build() {
    unawaited(_load());
    return const ArchiveSettings();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = ArchiveSettings(
      destination: ArchiveDestination.fromStored(
        prefs.getString(_destinationKey),
      ),
      folderPath: prefs.getString(_folderKey),
    );
  }

  Future<void> selectDestination(ArchiveDestination destination) async {
    state = state.copyWith(destination: destination);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_destinationKey, destination.stored);
  }

  Future<void> selectFolder(String path) async {
    state = state.copyWith(folderPath: path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_folderKey, path);
  }
}

final archiveControllerProvider =
    NotifierProvider<ArchiveController, ArchiveSettings>(ArchiveController.new);

/// El archivo activo, o `null` si el usuario no ha elegido ninguno — que es lo
/// normal hasta que lo configure, y no un error.
final conversationArchiveProvider = Provider<ConversationArchive?>((ref) {
  final settings = ref.watch(archiveControllerProvider);
  if (!settings.isReady) return null;
  return MarkdownArchive(
    root: settings.folderPath!,
    // Los `[[enlaces]]` solo tienen sentido dentro de un vault. En una carpeta
    // normal serían símbolos raros en medio del texto.
    wikilinks: settings.destination == ArchiveDestination.obsidian,
  );
});
