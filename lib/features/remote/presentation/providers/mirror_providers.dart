import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/remote/data/channel_link.dart';
import 'package:nexus/features/remote/domain/remote_mirror.dart';
import 'package:nexus/features/remote/presentation/providers/outbox_providers.dart';
import 'package:nexus/features/remote/presentation/providers/pairing_providers.dart';
import 'package:nexus_protocol/nexus_protocol.dart';
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';

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
    // Sale con `unawaited`: si la pantalla se fue mientras tanto, el proveedor
    // ya no existe y esto lanzaria en vez de no hacer nada.
    if (!ref.mounted) return;
    state = RemoteMirror.desdeSnapshot(Snapshot(seq: 0, data: guardada));
  }

  /// Vuelve a pedir la lista. Lo llama el arranque y el tirón hacia abajo.
  /// Si la última vez que se pidió la lista, el Mac contestó.
  var _preguntado = false;
  bool get preguntado => _preguntado;

  Future<void> refrescar() async {
    try {
      final datos = await ref
          .read(channelLinkProvider)
          .pedir(RemoteMethod.conversations);
      final lista = (datos['conversations'] as List? ?? const [])
          .cast<Map<String, Object?>>();
      // Sale con `unawaited`: si la pantalla se fue mientras tanto, el proveedor
      // ya no existe y esto lanzaria en vez de no hacer nada.
      if (!ref.mounted) return;
      state = state.conLista(lista);
      // Sin lista no había nada que distinguir; con ella, el espejo ya sabe si el Mac
      // contestó. De aquí sale poder decir «nada abierto» en vez de «no pude
      // preguntar», que eran lo mismo en pantalla.
      _preguntado = true;
      unawaited(
        ref.read(mirrorCacheProvider).write({
          'conversations': [for (final c in state.visibles) c.toJson()],
        }),
      );
    } on LinkError {
      // Sin lista se sigue con lo que haya. Vaciar el espejo porque una petición
      // falló dejaría la pantalla en blanco justo cuando se pierde la cobertura —
      // que es cuando más falta hace poder leer lo último.
      //
      // Lo que sí cambia es que **se sabe que no se pudo preguntar**: «nada abierto en
      // el Mac» y «no conseguí preguntar» se dibujaban idénticos, y son cosas
      // distintas.
      _preguntado = false;
    }
  }

  /// Trae una página de historial.
  ///
  /// **Se pide y no llega solo**, al contrario que la respuesta en curso: lo dicho
  /// antes puede ser una sesión de tres horas, y empujarlo entero sería mandar por 4G
  /// lo que casi nunca se va a leer. Por eso el Mac lo pagina desde el final.
  ///
  /// Devuelve `false` si no se pudo, para que la pantalla no se quede prometiendo que
  /// viene más.
  Future<bool> masHistorial(String conversationId) async {
    final conv = state.conversations[conversationId];
    // `cursor` cuenta desde el final: 0 es lo último dicho. Si ya se llegó al
    // principio, `masHistorial` es `null` y no se pide nada — pedirlo devolvería la
    // misma página para siempre.
    if (conv == null) return false;
    final cursor = conv.history.isEmpty ? 0 : conv.masHistorial;
    if (conv.history.isNotEmpty && cursor == null) return false;

    try {
      final datos = await ref
          .read(channelLinkProvider)
          .pedir(
            RemoteMethod.history,
            params: {'conversation': conversationId, 'cursor': cursor ?? 0},
          );
      state = state.conHistorial(
        conversationId,
        (datos['messages'] as List? ?? const []).cast<Map<String, Object?>>(),
        siguiente: datos['nextCursor'] as int?,
      );
      return true;
    } on LinkError {
      return false;
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

  /// Le pone nombre a una conversación. Vacío se lo quita.
  ///
  /// **Sin espejo optimista**: el nombre llega de vuelta por el evento `title` que ya
  /// existe, así que pintarlo aquí crearía una segunda fuente para el mismo dato — y la
  /// de aquí se quedaría vieja el día que el Mac decida otro.
  Future<LinkError?> renombrar(String conversationId, String nombre) async {
    try {
      await ref
          .read(channelLinkProvider)
          .pedir(
            RemoteMethod.renameConversation,
            params: {'conversation': conversationId, 'name': nombre},
          );
      return null;
    } on LinkError catch (error) {
      return error;
    }
  }

  /// Cierra una conversación en el Mac. No borra nada: sigue en el archivo.
  Future<LinkError?> cerrar(String conversationId) async {
    try {
      await ref
          .read(channelLinkProvider)
          .pedir(
            RemoteMethod.closeConversation,
            params: {'conversation': conversationId},
          );
      return null;
    } on LinkError catch (error) {
      return error;
    }
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
/// El orbe que se dibuja en el teléfono, que **no siempre es el del Mac**.
///
/// Con el enlace caído se fuerza a `sleep`, y en eso está toda la pieza: el espejo se
/// queda con lo último que supo, así que si el Mac estaba trabajando cuando se perdió
/// la cobertura, el teléfono seguiría girando su orbe sobre una pantalla que dice «se
/// perdió el enlace». **Un orbe girando promete trabajo que está pasando**, y aquí no
/// está pasando nada: el Mac puede haber terminado, haber fallado o estar dormido, y
/// el teléfono no tiene forma de saberlo.
///
/// Dormido no es «no pasa nada»: es «no sé nada», que es exactamente lo que hay.
NexusOrbState orbeParaElMovil({
  required LinkState enlace,
  required NexusOrbState delMac,
}) => enlace == LinkState.conectado ? delMac : NexusOrbState.sleep;

/// El orbe de una conversación, ya con la regla puesta.
final orbeProvider = Provider.family<NexusOrbState, String>((ref, id) {
  return orbeParaElMovil(
    enlace: ref.watch(linkStateProvider).value ?? LinkState.sinConexion,
    delMac: ref.watch(conversationProvider(id))?.orb ?? NexusOrbState.sleep,
  );
});

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
