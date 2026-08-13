import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/assistant/data/datasources/conversations_data_source.dart';
import 'package:nexus/features/assistant/domain/entities/conversation.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

final conversationsDataSourceProvider = Provider<ConversationsDataSource>(
  (ref) => const ConversationsDataSource(),
);

/// Qué conversaciones hay abiertas y cuál escucha el micrófono.
class ConversationsController extends Notifier<Conversations> {
  /// Lo guardado en disco, leído una sola vez.
  List<Conversation>? _saved;
  String? _savedFocusId;

  @override
  Conversations build() {
    // **Escuchar y no leer**: las carpetas se cargan de disco en asíncrono, así
    // que al construir esto todavía no hay ninguna. Leerlas una vez dejaba la
    // pantalla vacía para siempre aunque hubiera dos emparejadas — nadie volvía
    // a mirar cuando llegaban.
    ref.listen(workspaceControllerProvider, (previous, next) {
      unawaited(_reconcile());
    }, fireImmediately: true);
    return const Conversations();
  }

  /// Cuadra lo guardado con las carpetas que existen ahora mismo.
  Future<void> _reconcile() async {
    if (_saved == null) {
      final json = await ref.read(conversationsDataSourceProvider).read();
      _saved = [
        for (final entry in json['items'] as List<dynamic>? ?? const [])
          if (entry is Map<String, dynamic>) ?Conversation.fromJson(entry),
      ];
      _savedFocusId = json['focusedId'] as String?;
    }

    final workspace = ref.read(workspaceControllerProvider);
    if (workspace.folders.isEmpty) return;

    // Una conversación cuya carpeta ya no está emparejada no se puede abrir:
    // se quedaría sin sitio donde trabajar y sin permisos declarados.
    final folders = workspace.folders.map((folder) => folder.path).toSet();
    final items = [
      for (final item in [...state.items, ..._saved!])
        if (folders.contains(item.folderPath) &&
            !state.items.any(
              (existing) => existing.id == item.id && item != existing,
            ))
          item,
    ];
    final unique = <String, Conversation>{
      for (final item in items) item.id: item,
    };

    // Ninguna se abre sola al arrancar. Antes se abría una con la primera carpeta para no
    // dejar la pantalla vacía, y el efecto era encontrarte trabajando en un
    // sitio que no elegiste: la comodidad no compensaba la sorpresa. La
    // pantalla vacía pregunta dónde quieres trabajar, que es mejor pregunta
    // que una respuesta inventada.
    if (unique.isEmpty) {
      if (state.items.isNotEmpty) await _persist(const Conversations());
      return;
    }

    final list = unique.values.toList();
    final focus =
        list.any((item) => item.id == (state.focusedId ?? _savedFocusId))
        ? (state.focusedId ?? _savedFocusId)
        : list.first.id;
    if (list.length == state.items.length && state.focusedId == focus) return;
    await _persist(Conversations(items: list, focusedId: focus));
  }

  Future<void> _persist(Conversations next) async {
    state = next;
    await ref.read(conversationsDataSourceProvider).write({
      'items': next.items.map((item) => item.toJson()).toList(),
      'focusedId': next.focusedId,
    });
  }

  /// Abre una conversación nueva sobre esa carpeta.
  ///
  /// Se permite repetir carpeta: son **sesiones independientes**, y tener dos
  /// sobre el mismo repo —una revisando, otra escribiendo— es un caso legítimo.
  /// Cada una lleva su memoria, así que no se pisan.
  Future<String?> open(String folderPath) async {
    if (state.isFull) return null;

    // El identificador se compone del reloj y la carpeta: no hace falta un
    // paquete de UUID para distinguir tres cosas que no salen de esta máquina.
    final id =
        '${DateTime.now().microsecondsSinceEpoch}-${folderPath.hashCode}';
    final conversation = Conversation(id: id, folderPath: folderPath);
    await _persist(
      Conversations(items: [...state.items, conversation], focusedId: id),
    );
    // La carpeta de la conversación en foco **es** la carpeta activa. Sin esto,
    // Ajustes marcaba una y la barra enseñaba otra: dos sitios contando cosas
    // distintas sobre dónde se está trabajando.
    await ref.read(workspaceControllerProvider.notifier).setActive(folderPath);
    return id;
  }

  Future<void> close(String id) async {
    final items = state.items.where((item) => item.id != id).toList();
    await _persist(
      Conversations(
        items: items,
        focusedId: state.focusedId == id
            ? items.firstOrNull?.id
            : state.focusedId,
      ),
    );
  }

  Future<void> focus(String id) async {
    final conversation = state.byId(id);
    if (state.focusedId == id || conversation == null) return;
    await _persist(state.copyWith(focusedId: id));
    await ref
        .read(workspaceControllerProvider.notifier)
        .setActive(conversation.folderPath);
  }
}

final conversationsProvider =
    NotifierProvider<ConversationsController, Conversations>(
      ConversationsController.new,
    );

/// La carpeta de una conversación concreta. Lo consultan el puente y el
/// guardia de permisos, que antes miraban una «carpeta activa» global.
final conversationFolderProvider = Provider.family<String?, String>(
  (ref, conversationId) =>
      ref.watch(conversationsProvider).byId(conversationId)?.folderPath,
);
