import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/remote/data/channel_link.dart';
import 'package:nexus/features/remote/domain/remote_mirror.dart';
import 'package:nexus/features/remote/presentation/providers/outbox_providers.dart';
import 'package:nexus/features/remote/presentation/providers/pairing_providers.dart';
import 'package:nexus_protocol/nexus_protocol.dart';

/// El espejo, mantenido al día por el enlace.
///
/// Aquí se junta todo lo que llega: los eventos que empuja el Mac, los snapshots
/// cuando el resync no cabía en eventos, y la lista de conversaciones cuando se
/// pide. El espejo en sí no sabe de dónde viene nada — eso es lo que permite
/// probarlo contra el puente de verdad sin socket.
class MirrorController extends Notifier<RemoteMirror> {
  @override
  RemoteMirror build() {
    final enlace = ref.watch(channelLinkProvider);

    final deEventos = enlace.eventos.listen((evento) {
      state = state.aplicar(evento);
    });
    final deFotos = enlace.fotos.listen((foto) {
      state = RemoteMirror.desdeSnapshot(foto);
      // Se guarda lo que llega, para poder leerlo sin red. **Solo el snapshot y la
      // lista**, no cada evento: guardar en disco por cada delta de texto sería
      // escribir cientos de veces por respuesta.
      unawaited(ref.read(mirrorCacheProvider).write(foto.data));
    });

    // Al conectar se pide la lista. Hace falta aunque haya snapshot: la foto trae lo
    // que se está escribiendo, pero **la carpeta de cada conversación sale de la
    // lista**, y sin ella las tarjetas se llamarían por su identificador.
    final deEstado = enlace.estado.listen((estado) {
      if (estado == LinkState.conectado) unawaited(refrescar());
    });

    ref.onDispose(() {
      deEventos.cancel();
      deFotos.cancel();
      deEstado.cancel();
    });

    // Lo último que se leyó, mientras no haya red. Se aplica **solo si el espejo
    // sigue vacío**: llega tarde por definición —viene de disco— y sobrescribir algo
    // que ya llegó del Mac con una foto de anoche es peor que no tener caché.
    unawaited(_restaurar());

    return const RemoteMirror();
  }

  Future<void> _restaurar() async {
    final guardada = await ref.read(mirrorCacheProvider).read();
    if (guardada == null || !state.vacio) return;
    state = RemoteMirror.desdeSnapshot(Snapshot(seq: 0, data: guardada));
  }

  /// Vuelve a pedir la lista. Lo llama el arranque y el tirón hacia abajo.
  Future<void> refrescar() async {
    try {
      final datos = await ref
          .read(channelLinkProvider)
          .pedir(RemoteMethod.conversations);
      final lista = (datos['conversations'] as List? ?? const [])
          .cast<Map<String, Object?>>();
      state = state.conLista(lista);
      unawaited(
        ref.read(mirrorCacheProvider).write({
          'conversations': [for (final c in state.visibles) c.toJson()],
        }),
      );
    } on LinkError {
      // Sin lista se sigue con lo que haya. Vaciar el espejo porque una petición
      // falló dejaría la pantalla en blanco justo cuando se pierde la cobertura —
      // que es cuando más falta hace poder leer lo último.
    }
  }

  /// Manda un encargo **a través de la cola**.
  ///
  /// Siempre por la cola, también con cobertura: si el camino con red fuera otro,
  /// habría dos formas de mandar un encargo y solo una tendría el `clientMsgId`
  /// guardado. La cola lo intenta al instante cuando hay enlace, así que con red el
  /// comportamiento es el mismo y sin ella el encargo no se pierde.
  ///
  /// Devuelve `false` si no cabe.
  Future<bool> mandar(String conversationId, String texto) async {
    final encolado = await ref
        .read(outboxProvider.notifier)
        .encolar(conversationId, texto);
    return encolado != null;
  }

  Future<LinkError?> detener(String conversationId) async {
    try {
      await ref
          .read(channelLinkProvider)
          .pedir(
            RemoteMethod.stopErrand,
            params: {'conversation': conversationId},
          );
      return null;
    } on LinkError catch (error) {
      return error;
    }
  }
}

final mirrorProvider = NotifierProvider<MirrorController, RemoteMirror>(
  MirrorController.new,
);

/// Una conversación del espejo. `null` si ya no está.
final conversationProvider = Provider.family<MirroredConversation?, String>(
  (ref, id) => ref.watch(mirrorProvider).conversations[id],
);

/// Hasta cuándo el canal puede escribir, según el Mac.
///
/// Se pregunta y no se adivina: el permiso es del canal y caduca por su cuenta, así
/// que un valor guardado en el teléfono estaría mintiendo la mitad del tiempo.
class WritePermission extends AsyncNotifier<DateTime?> {
  @override
  Future<DateTime?> build() async => null;

  Future<void> consultar(String conversationId) async {
    state = const AsyncLoading();
    try {
      final datos = await ref
          .read(channelLinkProvider)
          .pedir(
            RemoteMethod.permission,
            params: {'conversation': conversationId},
          );
      final hasta = datos['remoteWriteUntil'] as String?;
      final carpeta = datos['folderCanWrite'] == true;
      // **El AND de los dos.** Si la carpeta no concede, la frase no sube nada — y
      // enseñar «puede escribir» por tener la ventana abierta sería prometer algo que
      // el encargo no va a poder hacer.
      state = AsyncData(
        carpeta && hasta != null ? DateTime.tryParse(hasta) : null,
      );
    } on LinkError catch (error) {
      state = AsyncError(error, StackTrace.current);
    }
  }

  /// Abre la escritura con la frase. Devuelve el código del contrato si no se pudo.
  Future<String?> abrir(String frase) async {
    try {
      final datos = await ref
          .read(channelLinkProvider)
          .pedir(RemoteMethod.unlockWrites, params: {'phrase': frase});
      final hasta = datos['until'] as String?;
      state = AsyncData(hasta == null ? null : DateTime.tryParse(hasta));
      return null;
    } on LinkError catch (error) {
      // El código es lo que la pantalla convierte en algo que hacer: «define una
      // frase en el Mac» no es «te equivocaste» ni es «espera».
      return error.code ?? 'internal';
    }
  }
}

final writePermissionProvider =
    AsyncNotifierProvider<WritePermission, DateTime?>(WritePermission.new);
