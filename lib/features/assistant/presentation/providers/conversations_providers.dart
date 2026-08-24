import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/assistant/data/datasources/conversations_data_source.dart';
import 'package:nexus/features/assistant/domain/entities/conversation.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:nexus/features/history/domain/entities/conversation_record.dart';
import 'package:nexus/features/assistant/presentation/providers/assistant_controller.dart';

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

    // Lo guardado se recupera **una sola vez**. Antes se volvía a fusionar en
    // cada cambio del espacio de trabajo —y cambiar el permiso es uno—, así que
    // una conversación cerrada reaparecía sola en cuanto tocabas cualquier
    // ajuste: parecía que la app abría un chat por su cuenta, y encima sobre
    // otra carpeta. A partir de aquí esto solo poda lo que ya no tiene carpeta.
    _saved = const [];
    _savedFocusId = null;

    // Ninguna se abre sola al arrancar. Antes se abría una con la primera carpeta para no
    // dejar la pantalla vacía, y el efecto era encontrarte trabajando en un
    // sitio que no elegiste: la comodidad no compensaba la sorpresa. La
    // pantalla vacía pregunta dónde quieres trabajar, que es mejor pregunta
    // que una respuesta inventada.
    if (unique.isEmpty) {
      // Vacío **ya leído**: es lo que distingue «no tienes ninguna abierta» de
      // «todavía no lo sé», y con eso la pantalla de primera vez deja de aparecer en
      // el arranque de una app que sí tenía conversaciones.
      //
      // Marcar que ya se leyó **no escribe en disco**: no hay nada nuevo que guardar, y
      // escribir por esto disparaba el guardado en sitios que solo estaban leyendo.
      if (state.items.isNotEmpty) {
        await _persist(const Conversations());
      } else if (!state.cargado) {
        state = state.copyCargado();
      }
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
    // Todo lo que se persiste sale de una lista ya leída, así que a partir de aquí
    // «vacío» significa vacío de verdad.
    state = next.copyCargado();
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
    // **Primero lo guardado, y luego se añade.** `build()` devuelve la lista vacía y
    // el disco se lee después, así que abrir una conversación en esa ventana persistía
    // una lista con **solo la nueva** y se llevaba por delante las que había. Es como
    // se perdió una conversación con su contenido: quedó un id nuevo sobre la misma
    // carpeta y el registro viejo huérfano en disco.
    //
    // `_reconcile` es idempotente y baratísimo después de la primera vez, así que
    // esperarlo aquí no cuesta nada y quita la ventana entera.
    await _reconcile();
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

  /// Le pone nombre a una conversación, o se lo quita.
  ///
  /// Vacío quita el nombre y devuelve al derivado —el primer encargo—, que es lo que
  /// hace falta para deshacer: sin eso, un nombre puesto por error se quedaría para
  /// siempre y habría que cerrar la conversación para librarse de él.
  Future<void> renombrar(String id, String nombre) async {
    // Mismo motivo que en `open`: renombrar reescribe la lista entera, y hacerlo con
    // la lista sin cargar borraría las demás.
    await _reconcile();
    final limpio = nombre.trim();
    final items = [
      for (final item in state.items)
        if (item.id == id)
          item.conNombre(limpio.isEmpty ? null : limpio)
        else
          item,
    ];
    await _persist(Conversations(items: items, focusedId: state.focusedId));
  }

  Future<void> close(String id) async {
    // Y aquí igual: cerrar reescribe la lista. Sin cargar, «cerrar una» se convertía en
    // «dejar la lista vacía».
    await _reconcile();
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

  /// Mueve una conversación a otra carpeta.
  ///
  /// Se usa cuando la que está abierta **no tiene nada dicho todavía**: cambiar
  /// de carpeta ahí es corregir el rumbo antes de empezar, no empezar otra
  /// cosa. Abrir una segunda dejaría una pestaña vacía por cada vez que dudas
  /// dónde ibas a trabajar.
  ///
  /// Con algo ya hablado no se mueve nunca: esa conversación tiene la memoria y
  /// la sesión de **su** carpeta, y llevársela a otra sería mezclar dos
  /// contextos que el producto mantiene separados a propósito.
  Future<void> moveTo(String id, String folderPath) async {
    final conversation = state.byId(id);
    if (conversation == null || conversation.folderPath == folderPath) return;

    final items = [
      for (final item in state.items)
        if (item.id == id)
          Conversation(id: item.id, folderPath: folderPath)
        else
          item,
    ];
    await _persist(state.copyWith(items: items));
    await ref.read(workspaceControllerProvider.notifier).setActive(folderPath);
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

/// Retomar una conversación del archivo.
///
/// **Fuera del notifier, y no por gusto:** los controladores de cada conversación
/// escuchan a `conversationsProvider`, así que si él los leyera habría dependencia
/// circular — Riverpod lo detecta y lanza. Aquí las lecturas pasan al llamar, no al
/// construir, así que no hay ciclo.
///
/// Tres desenlaces, y los tres importan:
///
/// - **Ya está abierta** → se va a su pestaña. Una conversación viva se guarda en el
///   archivo desde su primer turno, así que la de la lista puede ser exactamente la que
///   tienes delante; abrirla otra vez creaba una segunda pestaña escribiendo en el
///   **mismo registro**, y lo que escribías en una aparecía en la otra.
/// - **No está** → pestaña nueva, sobre su carpeta. Repetir carpeta está permitido a
///   propósito: son sesiones independientes con su propia memoria.
/// - **No cabe** → se dice. Antes no hacía nada, y no hacer nada en silencio se lee
///   como que la app se colgó.
final retomarDelArchivoProvider =
    Provider<Future<RetomarResultado> Function(ConversationRecord)>((ref) {
      return (registro) async {
        for (final item in ref.read(conversationsProvider).items) {
          final controlador = ref.read(
            assistantControllerProvider(item.id).notifier,
          );
          if (!controlador.isShowing(registro.id)) continue;
          ref.read(conversationsProvider.notifier).focus(item.id);
          return RetomarResultado.yaEstaba;
        }

        final id = await ref
            .read(conversationsProvider.notifier)
            .open(registro.folderPath);
        if (id == null) return RetomarResultado.noCabe;
        ref.read(assistantControllerProvider(id).notifier).resume(registro);
        return RetomarResultado.enPestanaNueva;
      };
    });

/// Qué pasó al retomar una del archivo.
enum RetomarResultado {
  /// Estaba abierta ya: se fue a su pestaña, sin duplicarla.
  yaEstaba,

  /// Se abrió una pestaña nueva con ella.
  enPestanaNueva,

  /// El muelle está lleno. Quien llama tiene que **decirlo**.
  noCabe,
}
