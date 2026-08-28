import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nexus/core/platform/system_files.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/assistant/presentation/providers/assistant_controller.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/history/data/datasources/local_conversation_store.dart';
import 'package:nexus/features/history/data/datasources/vault_reader.dart';
import 'package:nexus/features/history/data/datasources/notion_api.dart';
import 'package:nexus/features/history/data/repositories/markdown_archive.dart';
import 'package:nexus/features/history/data/repositories/notion_archive.dart';
import 'package:nexus/features/onboarding/presentation/providers/onboarding_providers.dart';
import 'package:nexus/features/history/domain/entities/conversation_record.dart';
import 'package:nexus/features/history/domain/entities/conversation_summary.dart';
import 'package:nexus/features/history/domain/repositories/conversation_archive.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dónde se archivan las conversaciones y en qué carpeta, recordado entre
/// arranques.
@immutable
class ArchiveSettings {
  const ArchiveSettings({
    this.destination = ArchiveDestination.none,
    this.folderPath,
    this.notionPage,
    this.hasNotionToken = false,
  });

  final ArchiveDestination destination;

  /// La carpeta elegida —o el vault—. Con destino de disco y sin carpeta no se
  /// guarda nada: no se inventa un sitio en el que dejar tus conversaciones.
  final String? folderPath;

  bool get isReady => switch (destination) {
    ArchiveDestination.none => false,
    ArchiveDestination.folder ||
    ArchiveDestination.obsidian => (folderPath ?? '').isNotEmpty,
    ArchiveDestination.notion =>
      hasNotionToken && NotionApi.pageIdFrom(notionPage ?? '') != null,
  };

  /// La página de Notion donde cuelga todo, tal como la pegó el usuario.
  final String? notionPage;

  /// El token está o no está; **su valor no vive aquí**. Igual que la llave de
  /// Gemini: se guarda cifrado en el llavero y se pide en el momento de usarlo,
  /// no se pasea por el estado de la interfaz.
  final bool hasNotionToken;

  ArchiveSettings copyWith({
    ArchiveDestination? destination,
    String? folderPath,
    String? notionPage,
    bool? hasNotionToken,
  }) => ArchiveSettings(
    destination: destination ?? this.destination,
    folderPath: folderPath ?? this.folderPath,
    notionPage: notionPage ?? this.notionPage,
    hasNotionToken: hasNotionToken ?? this.hasNotionToken,
  );
}

class ArchiveController extends Notifier<ArchiveSettings> {
  static const _destinationKey = 'archive_destination';
  static const _folderKey = 'archive_folder';
  static const _notionPageKey = 'archive_notion_page';
  static const _notionTokenKey = 'notion_token';

  /// Las páginas ya creadas en Notion y cuánto se ha mandado de cada
  /// conversación. Sin esto, cada arranque crearía páginas nuevas de lo mismo
  /// y repetiría los mensajes ya subidos.
  static const _notionPagesKey = 'archive_notion_pages';
  static const _notionSentKey = 'archive_notion_sent';

  /// Se completa cuando los ajustes **ya se leyeron del disco**.
  ///
  /// Existe por un fallo concreto: `build()` devuelve los de por defecto —«sin
  /// archivo configurado»— y carga después. El escritorio no lo nota porque su
  /// pantalla sigue mirando y se redibuja cuando llegan; el teléfono **pregunta una
  /// vez y se queda con la respuesta**, así que veía una conversación en vez de
  /// treinta y una si preguntaba en los primeros milisegundos de la app.
  ///
  /// Nunca falla: si el llavero no abre, se completa igual con lo que se pudo leer.
  /// Esperar algo que puede lanzar convertiría un ajuste ilegible en un canal roto.
  late final Future<void> cargado;

  @override
  ArchiveSettings build() {
    cargado = _load().catchError((Object _) {});
    return const ArchiveSettings();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    // El llavero **aparte y sin poder tumbar al resto**: si no abre —bloqueado, lento,
    // o simplemente ausente— antes se perdía la carga entera, y con ella la carpeta del
    // vault. El síntoma era «no tengo archivo configurado», que es lo mismo que dice
    // un Mac recién instalado, así que no había forma de distinguirlo de la verdad.
    //
    // Lo único que se pierde ahora es saber si hay token de Notion, que es exactamente
    // lo que el llavero guardaba.
    String? token;
    try {
      token = await ref
          .read(secureStorageDataSourceProvider)
          .read(_notionTokenKey);
    } on Object {
      token = null;
    }
    state = ArchiveSettings(
      destination: ArchiveDestination.fromStored(
        prefs.getString(_destinationKey),
      ),
      folderPath: prefs.getString(_folderKey),
      notionPage: prefs.getString(_notionPageKey),
      hasNotionToken: (token ?? '').isNotEmpty,
    );
  }

  /// El token, cifrado en el llavero — nunca en las preferencias en claro.
  Future<void> saveNotionToken(String token) async {
    await ref
        .read(secureStorageDataSourceProvider)
        .write(_notionTokenKey, token.trim());
    state = state.copyWith(hasNotionToken: token.trim().isNotEmpty);
  }

  Future<void> saveNotionPage(String pageUrl) async {
    state = state.copyWith(notionPage: pageUrl.trim());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_notionPageKey, pageUrl.trim());
  }

  Future<String?> readNotionToken() =>
      ref.read(secureStorageDataSourceProvider).read(_notionTokenKey);

  Future<Map<String, String>> notionPages() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_notionPagesKey);
    if (raw == null) return {};
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic>
        ? decoded.map((key, value) => MapEntry(key, value.toString()))
        : {};
  }

  Future<Map<String, int>> notionSent() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_notionSentKey);
    if (raw == null) return {};
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic>
        ? decoded.map(
            (key, value) => MapEntry(key, (value as num?)?.toInt() ?? 0),
          )
        : {};
  }

  Future<void> rememberNotionPage(String key, String pageId) async {
    final prefs = await SharedPreferences.getInstance();
    final pages = await notionPages()
      ..[key] = pageId;
    await prefs.setString(_notionPagesKey, jsonEncode(pages));
  }

  Future<void> rememberNotionSent(String key, int count) async {
    final prefs = await SharedPreferences.getInstance();
    final sent = await notionSent()
      ..[key] = count;
    await prefs.setString(_notionSentKey, jsonEncode(sent));
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
/// El archivo activo, ya montado con lo que el usuario configuró.
///
/// Notion necesita más piezas que una carpeta —token, página, y la memoria de
/// lo ya subido—, así que se arma aparte y de forma asíncrona: leer el llavero
/// no es instantáneo.
final conversationArchiveProvider = FutureProvider<ConversationArchive?>((
  ref,
) async {
  final settings = ref.watch(archiveControllerProvider);
  if (!settings.isReady) return null;

  if (settings.destination == ArchiveDestination.notion) {
    final controller = ref.read(archiveControllerProvider.notifier);
    final token = await controller.readNotionToken();
    final page = NotionApi.pageIdFrom(settings.notionPage ?? '');
    if (token == null || token.isEmpty || page == null) return null;
    return NotionArchive(
      token: token,
      rootPageId: page,
      pageIds: await controller.notionPages(),
      onPageCreated: controller.rememberNotionPage,
      sentMessages: await controller.notionSent(),
      onSent: controller.rememberNotionSent,
    );
  }

  return MarkdownArchive(
    root: settings.folderPath!,
    // Los `[[enlaces]]` solo tienen sentido dentro de un vault. En una carpeta
    // normal serían símbolos raros en medio del texto.
    wikilinks: settings.destination == ArchiveDestination.obsidian,
  );
});

/// El historial de la app: siempre encendido, pase lo que pase con el destino
/// que haya elegido el usuario.
final localConversationStoreProvider = Provider<LocalConversationStore>(
  (ref) => const LocalConversationStore(),
);

/// El lector del vault, **uno solo y vivo**.
///
/// No es un detalle de cableado: dentro se queda lo leído de cada nota con su
/// fecha de modificación, y eso es lo que hace que refrescar el historial en
/// cada turno no vuelva a recorrer el vault entero. Construir uno nuevo en cada
/// uso —como se hacía— tiraba esa memoria cada vez.
final vaultReaderProvider = Provider<VaultReader>((ref) => VaultReader());

/// Las conversaciones de una carpeta: las de la app **y las que ya hubiera** en
/// la carpeta o el vault elegido.
///
/// Se juntan a propósito. Ese vault puede traer conversaciones de La Oficina
/// sobre los mismos repos y con el mismo Claude; esconderlas porque las escribió
/// otra app sería una frontera que solo existe en el código. Se recarga al
/// invalidar, que es lo que se hace al terminar un turno.
final savedConversationsProvider =
    FutureProvider.family<List<ConversationSummary>, String>((
      ref,
      folderPath,
    ) async {
      final propias = await ref
          .watch(localConversationStoreProvider)
          .list(folderPath);

      final settings = ref.watch(archiveControllerProvider);
      final root = settings.destination.needsFolder
          ? settings.folderPath
          : null;
      if (root == null || root.isEmpty) return propias;

      final delVault = await ref
          .watch(vaultReaderProvider)
          .list(root, folderPath: folderPath);

      // Lo de la app manda cuando se repiten: es lo que se puede retomar con
      // todo su detalle, mientras que la nota es una copia para leer fuera.
      final vistas = {for (final record in propias) record.id};
      final todas = [
        ...propias,
        ...delVault.where((record) => !vistas.contains(record.id)),
      ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
      return todas;
    });

/// La nota de esa conversación en el vault, si la hay. Se busca por el
/// identificador porque el nombre del archivo lo pone el título, y un título se
/// recorta y se normaliza: reconstruirlo para adivinar la ruta sería adivinar.
Future<String?> _noteFor(Ref ref, ConversationSummary record) async {
  final settings = ref.read(archiveControllerProvider);
  if (!settings.destination.needsFolder) return null;
  final root = settings.folderPath;
  if (root == null || root.isEmpty) return null;

  final notas = await ref.read(vaultReaderProvider).list(root);
  for (final nota in notas) {
    if (nota.id == record.id) return nota.sourcePath;
  }
  return null;
}

/// Todo lo guardado, sin filtrar por carpeta: la vista por perfiles necesita el
/// vault entero, porque un perfil abarca varios proyectos.
final allSavedConversationsProvider = FutureProvider<List<ConversationSummary>>(
  (ref) async {
    final propias = await ref.watch(localConversationStoreProvider).listAll();

    final settings = ref.watch(archiveControllerProvider);
    final root = settings.destination.needsFolder ? settings.folderPath : null;
    if (root == null || root.isEmpty) return propias;

    final delVault = await ref.watch(vaultReaderProvider).list(root);
    final vistas = {for (final record in propias) record.id};
    return [
      ...propias,
      ...delVault.where((record) => !vistas.contains(record.id)),
    ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  },
);

/// La conversación entera detrás de una ficha, o `null` si ya no está.
///
/// Es la otra mitad del índice: las listas traen fichas, y esto es lo que se
/// paga **al abrir una**. De dónde se lee lo dice la propia ficha — si trae
/// `sourcePath` es una nota del vault, y si no, el almacén de la app.
final conversationDetailProvider =
    Provider<Future<ConversationRecord?> Function(ConversationSummary)>((ref) {
      return (ficha) async {
        if (ficha.sourcePath case final path? when path.isNotEmpty) {
          return VaultReader.readOne(path);
        }
        return ref.read(localConversationStoreProvider).read(ficha);
      };
    });

/// Borra una conversación de donde esté: del historial de la app y de la nota
/// del vault, si vino de una.
///
/// La nota **se manda a la papelera**, no se destruye: está en una carpeta del
/// usuario, junto a cosas que no ha escrito esta app, y un clic no puede ser
/// irreversible ahí. El JSON interno sí se borra: es una copia de trabajo de
/// Nexus y se puede rehacer.
final deleteConversationProvider =
    Provider<Future<void> Function(ConversationSummary)>((ref) {
      return (record) async {
        // `debugPrint` y no `developer.log`: lo segundo no aparece ni en el log
        // del sistema ni en la consola de `flutter run`, y por eso los primeros
        // intentos de diagnosticar esto no enseñaron nada.
        debugPrint(
          'nexus.archivo · borrando «${record.title}» · id ${record.id} · '
          'nota ${record.sourcePath ?? 'ninguna'}',
        );
        await ref.read(localConversationStoreProvider).delete(record);

        // De dónde salió lo que se está viendo, y **su nota**: son dos copias
        // de la misma conversación. Borrando solo la de la app, la del vault
        // reaparecía sola en la lista —dejaba de estar duplicada— y parecía que
        // el borrado no había hecho nada.
        final source = record.sourcePath ?? await _noteFor(ref, record);
        if (source != null && source.isNotEmpty && File(source).existsSync()) {
          // Si el sistema no deja, se queda la nota y se sigue: lo que no puede
          // pasar es que un fallo aquí impida cerrar la conversación y refrescar
          // la lista, que era lo que hacía que borrar «a veces no hiciera nada».
          final movida = await SystemFiles.moveToTrash(source);
          if (!movida) {
            debugPrint(
              'nexus.archivo · la nota no se fue a la papelera: $source',
            );
          }
        }

        // Si esa conversación está abierta, se cierra: borrarla del historial
        // y dejarla en pantalla sería enseñar algo que ya no existe, y el
        // siguiente turno la resucitaría escribiéndola otra vez.
        for (final conversation in ref.read(conversationsProvider).items) {
          final controller = ref.read(
            assistantControllerProvider(conversation.id).notifier,
          );
          if (!controller.isShowing(record.id)) continue;
          await ref.read(conversationsProvider.notifier).close(conversation.id);
        }

        ref.invalidate(allSavedConversationsProvider);
        ref.invalidate(savedConversationsProvider(record.folderPath));
      };
    });
