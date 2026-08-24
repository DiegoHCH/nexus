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
  Stream<AudioFrame> listen() =>
      remoto.activo ? remoto.abrir() : local.listen();
}
