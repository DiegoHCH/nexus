import 'package:flutter/foundation.dart';

import 'package:nexus/features/assistant/domain/entities/audio_frame.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_input.dart';
import 'package:nexus/features/remote/domain/remote_voice_source.dart';

/// El micrófono de la sesión: el del teléfono si lo está sosteniendo, y si no el del
/// Mac.
///
/// Existe para que **la sesión de voz no sepa de dónde viene el audio**. Sin esto, la
/// voz remota habría obligado a tocar `HoldVoiceConversation` —el trozo con más lógica
/// del proyecto— para meterle un segundo camino; con esto, sigue pidiendo audio a un
/// puerto y ya está.
///
/// El teléfono manda cuando está activo, y no se mezclan: dos micrófonos en la misma
/// sesión son dos personas hablando encima, no una conversación.
///
/// **La elección es de una vez y para toda la sesión**, y de ahí salió un fallo que
/// costó encontrar: si el `stopVoice` del teléfono se colaba entre el `startVoice` y el
/// momento en que la sesión pedía audio, la fuente remota ya estaba cerrada y la sesión
/// se quedaba con **el micrófono del Mac** — escuchando la habitación mientras el
/// teléfono sostenía el botón y mandaba trozos que nadie leía. Se veía como «el orbe se
/// activa en los dos y no le llega nada al Mac». Lo que lo arregla no está aquí sino
/// donde nace el desorden: la superficie remota atiende encender y apagar **en fila**,
/// así que cuando se pregunta por la fuente, ya se sabe si la hay.
class VoiceInputCompartido implements VoiceInput {
  VoiceInputCompartido({required this.local, required this.remoto});

  final VoiceInput local;
  final RemoteVoiceSource remoto;

  /// El permiso del teléfono ya lo comprobó el teléfono: si está sosteniendo el botón,
  /// es que su sistema se lo concedió. Preguntar aquí por el micrófono del Mac negaría
  /// la voz remota en un Mac sin permiso de micro, que no hace falta para nada.
  @override
  Future<bool> hasPermission() =>
      remoto.activo ? Future.value(true) : local.hasPermission();

  @override
  Stream<AudioFrame> listen() {
    final delTelefono = remoto.flujo;
    // **Se dice de qué micrófono se va a escuchar.** El recuento de la sesión dice
    // «trozos del micro» sin decir de cuál, y con eso un Mac escuchando su propia
    // habitación mientras el teléfono sostenía el botón se leía igual que todo
    // bien — hicieron falta 587 trozos y una ronda entera de diagnóstico para verlo.
    // Se dice una vez por sesión, no por trozo: es una decisión, no un caudal.
    debugPrint(
      'voz · esta sesión escucha ${delTelefono == null ? 'el micrófono de este Mac' : 'el teléfono'}',
    );
    return delTelefono ?? local.listen();
  }
}
