import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/assistant/presentation/providers/assistant_controller.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/assistant/presentation/state/chat_message.dart';
import 'package:nexus/features/remote/domain/remote_surface.dart';
import 'package:nexus/features/remote/domain/write_phrase.dart';
import 'package:nexus/features/remote/presentation/providers/write_phrase_providers.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

/// El único sitio que sabe **a la vez** del canal y de cómo está montada la app.
///
/// Aquí vive todo el acoplamiento, a propósito y en un archivo. El canal habla con
/// [RemoteSurface] y no sabe que existe Riverpod; esto lee providers y no sabe que
/// existe un socket. El día que `submit` baje a un caso de uso, cambia este archivo
/// y nada más.
class AssistantSurface implements RemoteSurface {
  AssistantSurface(this._ref);

  final Ref _ref;

  /// Traduce el id que manda el teléfono a la conversación que existe aquí.
  ///
  /// Lanza si no está, y eso no es pesimismo: el teléfono guarda ids y una
  /// conversación se puede cerrar en el Mac mientras el móvil la tenía en
  /// pantalla. Sin esto, cada método tendría que recordar comprobarlo.
  String _existente(String id) {
    final hay = _ref.read(conversationsProvider).byId(id);
    if (hay == null) throw UnknownConversation(id);
    return id;
  }

  @override
  Future<List<RemoteConversation>> conversations() async {
    final estado = _ref.read(conversationsProvider);
    return [
      for (final item in estado.items)
        RemoteConversation(
          id: item.id,
          folder: item.folderPath,
          focused: item.id == estado.focusedId,
        ),
    ];
  }

  @override
  Future<RemotePage<RemoteMessage>> history(
    String conversationId, {
    int cursor = 0,
    int limit = 50,
  }) async {
    final id = _existente(conversationId);
    final mensajes = _ref.read(assistantControllerProvider(id)).messages;

    // Del final hacia atrás, y por eso el cursor cuenta desde el final: lo que un
    // teléfono quiere ver al abrir es lo último, no el principio de una sesión de
    // hace tres horas.
    final total = mensajes.length;
    final hasta = (total - cursor).clamp(0, total);
    final desde = (hasta - limit).clamp(0, total);
    final trozo = mensajes.sublist(desde, hasta);

    return RemotePage(
      items: [
        for (final m in trozo)
          RemoteMessage(mine: m.author == ChatAuthor.user, text: m.text),
      ],
      // `null` cuando ya se llegó al principio: un cursor que siempre existe
      // invita a pedir páginas para siempre.
      nextCursor: desde == 0 ? null : cursor + trozo.length,
    );
  }

  @override
  Future<RemoteMeter> meter(String conversationId) async {
    final medidor = _ref
        .read(assistantControllerProvider(_existente(conversationId)))
        .meter;
    return RemoteMeter(
      model: medidor.model,
      contextTokens: medidor.contextTokens,
      // La ventana se manda resuelta: es lo que evita que el teléfono repita el
      // cálculo — y el error— que ya se cometió aquí.
      contextWindow: medidor.contextWindow,
    );
  }

  @override
  Future<RemotePermission> permission(String conversationId) async {
    _existente(conversationId);
    final grant = _ref.read(writeUnlockProvider).grant;
    return RemotePermission(
      // Del espacio de trabajo, que es de donde sale al lanzar cada encargo.
      folderCanWrite: _ref.read(workspaceControllerProvider).permission.canWrite,
      remoteWriteUntil: grant?.until,
    );
  }

  @override
  Future<void> sendErrand(
    String conversationId,
    String text, {
    required bool allowWrites,
  }) async {
    final id = _existente(conversationId);
    await _ref
        .read(assistantControllerProvider(id).notifier)
        .submit(text, allowWrites: allowWrites);
  }

  @override
  Future<void> stopErrand(String conversationId) async {
    await _ref
        .read(assistantControllerProvider(_existente(conversationId)).notifier)
        .stopWork();
  }
}

final remoteSurfaceProvider = Provider<RemoteSurface>(AssistantSurface.new);

/// Lo que el canal puede escribir ahora mismo.
///
/// Vive aquí y no en el adaptador porque es la respuesta a una pregunta del canal,
/// no un dato de la app: **el AND** de lo que concede la carpeta y de lo que la
/// frase de escritura tenga abierto. Gana el más estricto.
final remoteAllowWritesProvider = Provider<bool>((ref) {
  final carpeta = ref.watch(workspaceControllerProvider).permission.canWrite;
  return carpeta && ref.read(writeUnlockProvider).puedeEscribir;
});

/// El tipo se reexporta para que el canal no tenga que importar el dominio del
/// asistente ni el del espacio de trabajo.
typedef ChannelWritePhrase = WritePhrase;
