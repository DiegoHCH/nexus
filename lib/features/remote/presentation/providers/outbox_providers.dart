import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/remote/data/channel_link.dart';
import 'package:nexus/features/remote/data/outbox_store_impl.dart';
import 'package:nexus/features/remote/domain/outbox.dart';
import 'package:nexus/features/remote/presentation/providers/pairing_providers.dart';
import 'package:nexus_protocol/nexus_protocol.dart';

final outboxStoreProvider = Provider<OutboxStore>(
  (ref) => const OutboxStoreImpl(),
);

final mirrorCacheProvider = Provider<MirrorCache>(
  (ref) => const MirrorCacheImpl(),
);

/// Genera los identificadores de encargo.
///
/// Inyectable porque la prueba de que **el mismo id sobrevive al reintento** no se
/// puede escribir contra un generador que cambia solo.
final clientMsgIdProvider = Provider<String Function()>((ref) {
  var n = 0;
  return () => '${DateTime.now().microsecondsSinceEpoch}-${n++}';
});

/// Lo que se dice cuando un encargo sale de la cola sin ejecutarse.
typedef OutboxAviso =
    void Function(PendingErrand encargo, DiscardReason motivo);

/// La cola de encargos, con su drenado.
///
/// Lo que hace es sencillo y lo delicado es **cuándo**: se drena de uno en uno al
/// conectar, y cada resultado tiene una respuesta distinta según lo que signifique
/// para el encargo.
class OutboxController extends AsyncNotifier<List<PendingErrand>> {
  Outbox? _cola;
  var _drenando = false;

  /// Para avisar de lo que se descarta. Sin esto, un encargo caducado desaparecería
  /// en silencio — y desaparecer en silencio es peor que no haberse mandado.
  final _avisos = <OutboxAviso>[];

  void escuchar(OutboxAviso aviso) => _avisos.add(aviso);

  @override
  Future<List<PendingErrand>> build() async {
    final guardados = await ref.read(outboxStoreProvider).read();
    final cola = Outbox(inicial: guardados);
    _cola = cola;

    // Lo que caducó estando la app cerrada se tira al arrancar y **se dice**. Un
    // encargo de anoche ejecutándose por la mañana sobre un repo que ya cambió es el
    // caso que la caducidad existe para evitar.
    final caducados = cola.caducar();
    for (final e in caducados) {
      _avisar(e, DiscardReason.caducado);
    }
    if (caducados.isNotEmpty) await _guardar();

    ref.listen(linkStateProvider, (_, estado) {
      if (estado.value == LinkState.conectado) unawaited(drenar());
    });

    return cola.pendientes;
  }

  /// Encola un encargo. Devuelve `null` si la cola está llena.
  Future<PendingErrand?> encolar(String conversationId, String texto) async {
    final cola = _cola;
    if (cola == null) return null;
    final encargo = cola.encolar(
      // El id se crea **aquí, al escribir**, no al mandar: es lo único que separa
      // reintentar de ejecutar dos veces, y tiene que sobrevivir a cerrar la app.
      clientMsgId: ref.read(clientMsgIdProvider)(),
      conversationId: conversationId,
      text: texto,
    );
    if (encargo == null) return null;
    await _guardar();
    unawaited(drenar());
    return encargo;
  }

  /// Manda lo que haya, de uno en uno.
  Future<void> drenar() async {
    final cola = _cola;
    if (cola == null || _drenando) return;
    // Un solo drenado a la vez. Dos en paralelo mandarían el mismo primer encargo
    // dos veces —con el mismo id, así que el Mac no lo ejecutaría dos veces, pero la
    // cola sí se descuadraría.
    _drenando = true;
    try {
      final enlace = ref.read(channelLinkProvider);
      while (enlace.ahora == LinkState.conectado) {
        for (final e in cola.caducar()) {
          _avisar(e, DiscardReason.caducado);
        }
        final encargo = cola.siguiente;
        if (encargo == null) break;

        final descarte = await _mandar(enlace, cola, encargo);
        if (descarte != null) _avisar(encargo, descarte);
        await _guardar();
        // Si el encargo sigue en la cola es que falló y toca esperar: seguir el
        // bucle sería reintentar en redondo sin dejar respirar a la red.
        if (cola.siguiente?.clientMsgId == encargo.clientMsgId) break;
      }
    } finally {
      _drenando = false;
    }
  }

  Future<DiscardReason?> _mandar(
    ChannelLink enlace,
    Outbox cola,
    PendingErrand encargo,
  ) async {
    try {
      await enlace.pedir(
        RemoteMethod.sendErrand,
        params: {'conversation': encargo.conversationId, 'text': encargo.text},
        // **El mismo id de siempre.** Es la razón de que el outbox sea seguro: el
        // deduplicador del Mac reconoce el reenvío y no vuelve a ejecutarlo.
        clientMsgId: encargo.clientMsgId,
      );
      cola.confirmar(encargo.clientMsgId);
      return null;
    } on LinkError catch (error) {
      return switch (error.failure) {
        // **Llegó.** Que no haya contestado no significa que no se hiciera, y
        // reintentarlo solo obtendría «duplicada». Se da por entregado, que es lo
        // que de verdad pasó.
        LinkFailure.sinRespuesta => _entregado(cola, encargo),
        // Pudo no llegar: se reintenta, con el mismo id.
        LinkFailure.sinConfirmacion ||
        LinkFailure.desconectado => cola.falloReintentable(encargo.clientMsgId),
        // El Mac dijo que no por algo que insistir no arregla.
        LinkFailure.rechazada => cola.falloDefinitivo(encargo.clientMsgId),
      };
    }
  }

  DiscardReason? _entregado(Outbox cola, PendingErrand encargo) {
    cola.confirmar(encargo.clientMsgId);
    return null;
  }

  void _avisar(PendingErrand encargo, DiscardReason motivo) {
    for (final aviso in _avisos) {
      aviso(encargo, motivo);
    }
  }

  Future<void> _guardar() async {
    final cola = _cola;
    if (cola == null) return;
    await ref.read(outboxStoreProvider).write(cola.pendientes);
    state = AsyncData(cola.pendientes);
  }
}

final outboxProvider =
    AsyncNotifierProvider<OutboxController, List<PendingErrand>>(
      OutboxController.new,
    );

/// Los encargos pendientes de una conversación.
final pendingForProvider = Provider.family<List<PendingErrand>, String>(
  (ref, id) => [
    for (final e in ref.watch(outboxProvider).value ?? const <PendingErrand>[])
      if (e.conversationId == id) e,
  ],
);
