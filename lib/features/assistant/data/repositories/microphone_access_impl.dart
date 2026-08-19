import 'package:flutter/services.dart';
import 'package:nexus/features/assistant/domain/repositories/microphone_access.dart';

/// Se lo pregunta al motor de audio nativo, que es quien puede mirar
/// `AVCaptureDevice.authorizationStatus` sin provocar el diálogo.
class MicrophoneAccessImpl implements MicrophoneAccess {
  const MicrophoneAccessImpl();

  static const _channel = MethodChannel('nexus/audio');

  @override
  Future<MicrophoneStatus> status() async {
    try {
      final raw = await _channel.invokeMethod<String>('permissionStatus');
      return switch (raw) {
        'granted' => MicrophoneStatus.granted,
        'denied' => MicrophoneStatus.denied,
        _ => MicrophoneStatus.notAsked,
      };
    } on PlatformException {
      // Sin canal al otro lado no se puede afirmar que esté denegado, y tratarlo
      // como tal cerraría la voz por un fallo nuestro. Se deja pasar: si de
      // verdad falta el permiso, el motor fallará al arrancar y eso ya se dice.
      return MicrophoneStatus.granted;
    } on MissingPluginException {
      return MicrophoneStatus.granted;
    }
  }
}
