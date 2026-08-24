import 'dart:io';
import 'package:nexus/features/artifacts/domain/entities/artifact.dart';
import 'package:nexus/features/artifacts/presentation/providers/artifacts_providers.dart';
import 'package:nexus/features/history/domain/entities/conversation_record.dart';
import 'package:nexus/features/history/presentation/providers/archive_providers.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/assistant/presentation/providers/assistant_controller.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/assistant/presentation/state/chat_message.dart';
import 'package:nexus/features/remote/domain/remote_surface.dart';
import 'package:nexus/features/remote/domain/write_phrase.dart';
import 'package:nexus/features/remote/presentation/providers/write_phrase_providers.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:nexus/features/remote/presentation/providers/channel_providers.dart';

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
      folderCanWrite: _ref
          .read(workspaceControllerProvider)
          .permission
          .canWrite,
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

  // ─────────── lo que salió de usar el teléfono de verdad ───────────

  @override
  Future<RemotePage<ArchivedConversation>> archive({
    int cursor = 0,
    int limit = 30,
  }) async {
    // **Las dos fuentes, no una.** La primera versión leía solo el almacén propio de
    // la app y enseñaba **una** conversación mientras el escritorio enseñaba treinta y una:
    // el resto vive en el vault que el usuario eligió —la carpeta de Obsidian, con sus
    // pestañas de cuenta— y el historial del escritorio suma los dos.
    //
    // Se reusa el provider que ya hace esa suma en vez de repetirla aquí: repetirla
    // daría dos ideas de qué es «el archivo», y la del teléfono se quedaría vieja el
    // día que se añada un destino.
    // **Primero que los ajustes estén leídos del disco.** Los notifiers de ajustes
    // devuelven «nada configurado» mientras su lectura va de camino, y el escritorio
    // no lo nota porque su pantalla sigue mirando y se redibuja cuando llegan. Aquí no
    // hay segunda oportunidad: se contesta una vez, y contestar «hay una» cuando hay
    // treinta y una es peor que tardar 20 ms más.
    //
    // Se espera aquí y no dentro del provider: un provider que mira el estado que va a
    // cambiar y encima espera se queda sin futuro a mitad —Riverpod lo destruye al
    // llegar el cambio— y el teléfono recibiría un fallo en vez de una lista.
    await _ref.read(archiveControllerProvider.notifier).cargado;
    final guardadas = await _ref.read(allSavedConversationsProvider.future);

    final vivas = _ref.read(conversationsProvider);
    final trozo = guardadas.skip(cursor).take(limit).toList();

    return RemotePage(
      items: [
        for (final r in trozo)
          ArchivedConversation(
            id: r.id,
            folder: r.folderPath,
            // El primer encargo como título: es lo que el escritorio ya usa, y
            // resulta ser el mejor título que nadie ha escrito.
            title: _titulo(r),
            when: r.startedAt,
            turns: r.messages.length,
            // Si ya está abierta, se dice: ofrecer «retomar» algo vivo lleva a abrir
            // una segunda sobre la misma carpeta, que el escritorio no permite.
            open: vivas.hasFolder(r.folderPath),
            account: r.profileName,
          ),
      ],
      nextCursor: cursor + trozo.length >= guardadas.length
          ? null
          : cursor + trozo.length,
    );
  }

  static String _titulo(ConversationRecord registro) {
    for (final m in registro.messages) {
      if (m.author == ChatAuthor.user && m.text.trim().isNotEmpty) {
        return m.text.trim();
      }
    }
    return registro.projectName;
  }

  @override
  Future<String> resumeConversation(String archivedId) async {
    // La **misma** fuente que `archive()`, y no el almacén propio: si se listan
    // veintiséis y se buscan entre una, retomar cualquiera del vault contestaba
    // «conversación desconocida» — un archivo que enseña cosas que no se pueden abrir.
    await _ref.read(archiveControllerProvider.notifier).cargado;
    final guardadas = await _ref.read(allSavedConversationsProvider.future);
    final registro = guardadas.where((r) => r.id == archivedId).firstOrNull;
    if (registro == null) throw UnknownConversation(archivedId);

    // **Retomar es abrir su carpeta**, y `open` ya devuelve la que hubiera si esa
    // carpeta tenía una viva. Eso es lo correcto: dos conversaciones sobre el mismo
    // repo compartirían la sesión de Claude y se pisarían el contexto.
    final id = await _ref
        .read(conversationsProvider.notifier)
        .open(registro.folderPath);
    if (id == null) throw UnknownConversation(archivedId);
    return id;
  }

  /// Que esa conversación exista. Un id viejo guardado en el teléfono no puede abrir
  /// el micrófono de una conversación que ya se cerró.
  void _existe(String conversationId) {
    if (!_ref
        .read(conversationsProvider)
        .items
        .any((c) => c.id == conversationId)) {
      throw UnknownConversation(conversationId);
    }
  }

  @override
  Future<void> startVoice(String conversationId) async {
    _existe(conversationId);
    // La fuente se abre **antes** de la sesión: cuando la sesión pida audio, el puerto
    // compartido tiene que ver ya el micrófono del teléfono activo, o le daría el del
    // Mac y estaríamos escuchando la habitación equivocada.
    _ref.read(remoteVoiceSourceProvider).abrir();
    final hud = _ref.read(assistantControllerProvider(conversationId));
    if (hud.voiceActive) return;
    await _ref
        .read(assistantControllerProvider(conversationId).notifier)
        .toggleVoice();
  }

  @override
  Future<void> stopVoice(String conversationId) async {
    _existe(conversationId);
    final hud = _ref.read(assistantControllerProvider(conversationId));
    if (hud.voiceActive) {
      await _ref
          .read(assistantControllerProvider(conversationId).notifier)
          .stopVoice();
    }
    // La fuente se cierra **después**: cerrarla antes dejaría a la sesión leyendo un
    // stream ya terminado, y eso se ve como que la voz se corta sola en vez de
    // terminar.
    _ref.read(remoteVoiceSourceProvider).cerrar();
  }

  @override
  Future<void> renameConversation(String conversationId, String name) async {
    // **Solo una que exista.** Sin esto, un id viejo guardado en el teléfono crearía
    // un nombre huérfano que nadie vería nunca y que se quedaría en las preferencias.
    if (!_ref
        .read(conversationsProvider)
        .items
        .any((c) => c.id == conversationId)) {
      throw UnknownConversation(conversationId);
    }
    await _ref
        .read(conversationsProvider.notifier)
        .renombrar(conversationId, name);
  }

  @override
  Future<void> closeConversation(String conversationId) async {
    // Cerrar lo ya cerrado **no es un error**: es el estado que se pedía. Lanzar aquí
    // convertiría un reintento —y estos se reintentan con el mismo id— en un fallo en
    // pantalla por algo que ya está hecho.
    if (!_ref
        .read(conversationsProvider)
        .items
        .any((c) => c.id == conversationId)) {
      return;
    }
    await _ref.read(conversationsProvider.notifier).close(conversationId);
  }

  @override
  Future<List<RemoteFolder>> folders() async {
    final espacio = _ref.read(workspaceControllerProvider);
    final vivas = _ref.read(conversationsProvider);
    // El nombre de la cuenta y no la ruta de su perfil: `.claude-work` es un detalle
    // del disco del Mac, y «work» es lo que se lee en las dos pantallas. Si el Mac no
    // sabe de perfiles, no se inventa ninguno.
    final cuentas = await _ref.read(claudeProfilesProvider.future);
    String? nombreDe(String? perfil) => perfil == null
        ? null
        : cuentas.where((c) => c.path == perfil).firstOrNull?.name;

    return [
      for (final carpeta in espacio.folders)
        RemoteFolder(
          path: carpeta.path,
          canWrite: carpeta.modality != FolderModality.textOnly,
          busy: vivas.hasFolder(carpeta.path),
          account: nombreDe(carpeta.claudeProfile),
        ),
    ];
  }

  @override
  Future<String> openConversation(String folderPath) async {
    final espacio = _ref.read(workspaceControllerProvider);
    // **Solo entre las que el Mac ya tiene.** Es lo que separa esto de emparejar: sin
    // esta comprobación, el teléfono podría mandar cualquier ruta del disco y estaría
    // haciendo justo lo que la decisión dejó fuera.
    if (!espacio.folders.any((f) => f.path == folderPath)) {
      throw UnknownConversation(folderPath);
    }
    final id = await _ref.read(conversationsProvider.notifier).open(folderPath);
    if (id == null) throw UnknownConversation(folderPath);
    return id;
  }

  @override
  Future<List<RemoteArtifact>> artifacts() async {
    // Igual que el archivo: la carpeta de documentos se lee del disco después de
    // construirse el notifier, y sin esperarla se contestaba «no hay ninguno» habiendo
    // uno. Es el mismo fallo dos veces, así que va escrito en los dos sitios.
    await _ref.read(artifactsFolderProvider.notifier).cargada;
    final lista = await _ref.read(artifactsProvider.future);
    return [
      for (final a in lista)
        RemoteArtifact(
          // La ruta como id: es lo que el escritorio ya usa para abrirlos, y no hace
          // falta inventar otro identificador que habría que mantener en paralelo.
          id: a.path,
          name: a.name,
          when: a.at,
          bytes: File(a.path).existsSync() ? File(a.path).lengthSync() : 0,
          text: Artifact.isTextual(a.path),
          account: a.account,
        ),
    ];
  }

  @override
  Future<String> artifact(String artifactId) async {
    await _ref.read(artifactsFolderProvider.notifier).cargada;
    final lista = await _ref.read(artifactsProvider.future);
    // **Solo los que están en la lista.** Sin esto, el `artifactId` sería una ruta
    // libre y el método se convertiría en «leer cualquier archivo del Mac», que es
    // exactamente lo que ningún método de este canal puede ser.
    if (!lista.any((a) => a.path == artifactId)) {
      throw UnknownConversation(artifactId);
    }
    // Y solo los de texto: sin esto, pedir un `.png` acaba en un error de
    // codificación a mitad de leer, que el teléfono no puede explicar.
    if (!Artifact.isTextual(artifactId)) throw BinaryArtifact(artifactId);
    return File(artifactId).readAsString();
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
