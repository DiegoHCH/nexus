import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/remote/data/channel_link.dart';
import 'package:nexus/features/remote/data/microfono_del_movil.dart';
import 'package:nexus/features/remote/presentation/providers/pairing_providers.dart';
import 'package:nexus_protocol/nexus_protocol.dart';

final microfonoProvider = Provider<Microfono>((ref) => MicrofonoDelMovil());

/// En qué anda el micrófono del teléfono.
enum Voz {
  /// Cerrado.
  callado,

  /// Pidiendo permiso, o abriendo el micrófono.
  abriendo,

  /// Abierto: lo que se dice va saliendo hacia el Mac.
  hablando,

  /// El sistema no da micrófono. **Es un estado y no una excepción**: hay que poder
  /// enseñarlo, y quien lo negó fue el sistema, no un fallo del canal.
  sinMicrofono,

  /// Se abrió el micrófono pero el Mac no está escuchando. Pasa al perder el enlace a
  /// mitad, y hay que decirlo: seguir capturando sería grabar para nadie.
  sinMac,
}

/// Abrir el micrófono y cerrarlo.
///
/// **El teléfono no habla con Gemini**: manda trozos al Mac y el Mac hace el resto
/// (`lo8`). Así que aquí solo hay tres cosas: pedir que abra la sesión, ir mandando lo
/// que capture el micrófono, y pedir que la cierre.
class VozController extends Notifier<Voz> {
  StreamSubscription<Uint8List>? _escucha;
  var _seq = 0;
  var _sinLlegar = 0;

  @override
  Voz build() {
    // El micrófono **se coge aquí y no dentro del cierre**: Riverpod prohíbe leer
    // providers en el ciclo de vida, y con razón — al desecharse esto, lo que se lea
    // puede estar desechado también. Cogerlo antes no cuesta nada.
    final microfono = ref.read(microfonoProvider);
    ref.onDispose(() {
      unawaited(_escucha?.cancel());
      // Y se cierra pase lo que pase: un micrófono abierto porque la pantalla se fue
      // es lo peor que puede dejar esto detrás.
      unawaited(microfono.cerrar());
    });
    return Voz.callado;
  }

  /// Empieza a hablar sobre esa conversación.
  Future<void> sostener(String conversationId) async {
    if (state != Voz.callado && state != Voz.sinMicrofono) return;
    state = Voz.abriendo;

    final microfono = ref.read(microfonoProvider);
    if (!await microfono.tienePermiso()) {
      state = Voz.sinMicrofono;
      return;
    }

    // **El Mac primero, y el micrófono después.** Si se abriera el micrófono antes,
    // los primeros trozos llegarían a un Mac que todavía no tiene sesión y se
    // perderían — y son justo los del principio de la frase.
    final enlace = ref.read(channelLinkProvider);
    try {
      await enlace.pedir(
        RemoteMethod.startVoice,
        params: {'conversation': conversationId},
      );
    } on LinkError {
      state = Voz.sinMac;
      return;
    }

    _seq = 0;
    _sinLlegar = 0;
    final trozos = await microfono.escuchar();
    _escucha = trozos.listen(
      _mandar,
      onError: (Object _) => soltar(conversationId),
    );
    state = Voz.hablando;
  }

  void _mandar(Uint8List pcm) {
    final salio = ref
        .read(channelLinkProvider)
        .mandarAudio(Audio(seq: _seq++, pcmBase64: base64Encode(pcm)));
    if (salio) {
      _sinLlegar = 0;
      return;
    }
    // **Se cuenta y se corta.** Un trozo perdido es normal —el contrato dice que un
    // hueco es mejor que un reenvío tarde— pero muchos seguidos significan que no hay
    // Mac al otro lado, y seguir capturando sería grabar para nadie.
    _sinLlegar++;
    if (_sinLlegar >= 10) state = Voz.sinMac;
  }

  /// Suelta el botón: cierra el micrófono y le dice al Mac que ya está.
  Future<void> soltar(String conversationId) async {
    await _escucha?.cancel();
    _escucha = null;
    await ref.read(microfonoProvider).cerrar();

    // **El cierre se manda aunque el enlace vaya mal.** Es idempotente y se reintenta
    // con el mismo id: dejar el micrófono abierto en el Mac es el peor final posible.
    try {
      await ref
          .read(channelLinkProvider)
          .pedir(
            RemoteMethod.stopVoice,
            params: {'conversation': conversationId},
          );
    } on LinkError catch (error) {
      debugPrint('no se pudo cerrar la voz en el Mac: $error');
    }
    state = Voz.callado;
  }
}

final vozProvider = NotifierProvider<VozController, Voz>(VozController.new);
