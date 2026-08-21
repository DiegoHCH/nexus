import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/remote/data/channel_link.dart';
import 'package:nexus/features/remote/presentation/providers/pairing_providers.dart';
import 'package:nexus_protocol/nexus_protocol.dart';

/// Lo que el teléfono lee del Mac sin que sea una conversación: el archivo, los
/// documentos y las carpetas.
///
/// Van aparte del espejo porque **no llegan por eventos**: el espejo se mantiene al día
/// con lo que el Mac empuja, y esto se **pide** cuando alguien abre la pantalla. Meterlo
/// en el espejo obligaría a decidir cuándo caduca una lista que nadie está mirando.

@immutable
class ArchiveEntry {
  const ArchiveEntry({
    required this.id,
    required this.folder,
    required this.title,
    required this.turns,
    required this.open,
    this.account,
  });

  factory ArchiveEntry.fromJson(Map<String, Object?> j) => ArchiveEntry(
    id: j['id']! as String,
    folder: (j['folder'] as String?) ?? '',
    title: (j['title'] as String?) ?? '',
    turns: (j['turns'] as int?) ?? 0,
    open: j['open'] == true,
    account: j['account'] as String?,
  );

  final String id;
  final String folder;
  final String title;
  final int turns;

  /// Si esa conversación está viva ahora mismo.
  final bool open;

  /// De qué cuenta de Claude es —`work`, `private`—. Nula si el Mac tiene una sola.
  final String? account;
}

@immutable
class FolderEntry {
  const FolderEntry({
    required this.path,
    required this.canWrite,
    required this.busy,
    this.account,
  });

  factory FolderEntry.fromJson(Map<String, Object?> j) => FolderEntry(
    path: j['path']! as String,
    canWrite: j['canWrite'] == true,
    busy: j['busy'] == true,
    account: j['account'] as String?,
  );

  final String path;
  final bool canWrite;
  final bool busy;

  /// Con qué cuenta trabaja. Abrir aquí es elegir cuenta, así que se ve antes.
  final String? account;
}

@immutable
class ArtifactEntry {
  const ArtifactEntry({
    required this.id,
    required this.name,
    required this.bytes,
    this.text = false,
    this.account,
  });

  factory ArtifactEntry.fromJson(Map<String, Object?> j) => ArtifactEntry(
    id: j['id']! as String,
    name: (j['name'] as String?) ?? '',
    bytes: (j['bytes'] as int?) ?? 0,
    text: j['text'] == true,
    account: j['account'] as String?,
  );

  final String id;
  final String name;
  final int bytes;

  /// Si se puede leer aquí. Un `.png` viaja mal por un canal de texto, y decirlo en
  /// la lista evita tocar algo que solo puede fallar.
  final bool text;

  /// De qué cuenta salió —`work`, `private`—, cuando están separados por perfil.
  final String? account;
}

/// El archivo de conversaciones.
class ArchiveController extends AsyncNotifier<List<ArchiveEntry>> {
  @override
  Future<List<ArchiveEntry>> build() async {
    // **Se sigue el cursor hasta el final.** Una sola página de 30 dejaba fuera lo que
    // pasara de ahí, y el corte no se veía: la lista acababa sin decir que había más.
    // En el archivo que hay medido —23 de `private`, 7 de `work` y 1 del almacén
    // propio— eso ya se pasa por una. Treinta títulos son unos pocos kilobytes, así
    // que traerlos todos por 4G no es el problema que el límite pretendía evitar.
    //
    // El tope de vueltas es un seguro contra un Mac que devolviera cursores para
    // siempre, no una decisión de producto: con 30 por página son 300 conversaciones,
    // más de las que nadie tiene, y si se llega **se dice** en vez de callarlo.
    final enlace = ref.read(channelLinkProvider);
    final todas = <ArchiveEntry>[];
    int? cursor = 0;
    var vueltas = 0;
    while (cursor != null && vueltas < 10) {
      vueltas++;
      final datos = await enlace.pedir(
        RemoteMethod.archive,
        params: {'limit': 30, 'cursor': cursor},
      );
      todas.addAll([
        for (final c in (datos['conversations'] as List? ?? const []))
          ArchiveEntry.fromJson(c as Map<String, Object?>),
      ]);
      final siguiente = datos['nextCursor'];
      cursor = siguiente is int ? siguiente : null;
    }
    if (cursor != null) {
      debugPrint(
        'el archivo se corto en ${todas.length}: el Mac sigue dando cursor',
      );
    }
    return todas;
  }

  /// Retoma una y devuelve el id de la conversación **viva**, que puede no ser la del
  /// archivo: si esa carpeta ya tenía una abierta, el Mac lleva a esa.
  Future<String?> retomar(String archivedId) async {
    try {
      final datos = await ref
          .read(channelLinkProvider)
          .pedir(
            RemoteMethod.resumeConversation,
            params: {'archived': archivedId},
          );
      return datos['conversation'] as String?;
    } on LinkError {
      return null;
    }
  }
}

final archiveProvider =
    AsyncNotifierProvider<ArchiveController, List<ArchiveEntry>>(
      ArchiveController.new,
    );

/// Las carpetas emparejadas en el Mac.
class FoldersController extends AsyncNotifier<List<FolderEntry>> {
  @override
  Future<List<FolderEntry>> build() async {
    final datos = await ref
        .read(channelLinkProvider)
        .pedir(RemoteMethod.folders);
    return [
      for (final f in (datos['folders'] as List? ?? const []))
        FolderEntry.fromJson(f as Map<String, Object?>),
    ];
  }

  /// Abre una conversación sobre una de ellas.
  ///
  /// **Solo entre las que el Mac ofrece**: la comprobación de verdad está en el
  /// escritorio, y esto no la repite — repetirla aquí daría dos ideas de qué carpeta
  /// vale, y la del teléfono se quedaría vieja.
  Future<String?> abrir(String path) async {
    try {
      final datos = await ref
          .read(channelLinkProvider)
          .pedir(RemoteMethod.openConversation, params: {'folder': path});
      return datos['conversation'] as String?;
    } on LinkError {
      return null;
    }
  }
}

final foldersProvider =
    AsyncNotifierProvider<FoldersController, List<FolderEntry>>(
      FoldersController.new,
    );

/// La lista de artifacts.
final artifactsListProvider = FutureProvider<List<ArtifactEntry>>((ref) async {
  final datos = await ref
      .read(channelLinkProvider)
      .pedir(RemoteMethod.artifacts);
  return [
    for (final a in (datos['artifacts'] as List? ?? const []))
      ArtifactEntry.fromJson(a as Map<String, Object?>),
  ];
});

/// El contenido de uno.
///
/// Por familia y no en la lista: **la lista se pide siempre y el contenido casi nunca**,
/// así que mandar los cuerpos con el listado sería mandar por 4G documentos que nadie
/// va a abrir.
final artifactProvider = FutureProvider.family<String, String>((ref, id) async {
  final datos = await ref
      .read(channelLinkProvider)
      .pedir(RemoteMethod.artifact, params: {'artifact': id});
  return (datos['content'] as String?) ?? '';
});
