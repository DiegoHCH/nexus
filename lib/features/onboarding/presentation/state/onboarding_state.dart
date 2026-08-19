import 'package:nexus/features/onboarding/domain/entities/readiness.dart';

/// A qué pantalla va la app al arrancar: siempre pasa por el splash
/// ([AppRouteLoading]), y desde ahí a la comprobación de que puede trabajar
/// ([AppRouteNotReady]), a la configuración inicial o directo a Reposo.
sealed class AppRouteState {
  const AppRouteState();
}

class AppRouteLoading extends AppRouteState {
  const AppRouteLoading();
}

/// Falta algo **del sistema**, no de la configuración de la app: Claude Code
/// sin instalar o sin ninguna cuenta con sesión.
///
/// Va delante de [AppRouteNeedsSetup] porque es más de fondo: sin las manos, la
/// llave de Gemini solo consigue que te contesten sin poder hacer nada. Lleva el
/// informe dentro para que la pantalla diga **qué** falta y no un «algo va mal».
class AppRouteNotReady extends AppRouteState {
  const AppRouteNotReady(this.readiness);

  final Readiness readiness;
}

class AppRouteNeedsSetup extends AppRouteState {
  const AppRouteNeedsSetup();
}

class AppRouteReady extends AppRouteState {
  const AppRouteReady();
}

/// El micrófono se pide con un botón ("Solicitar") — no al construir la
/// pantalla. [idle] es el estado antes de que el usuario lo pulse; [checking]
/// solo dura mientras el diálogo del sistema está resolviendo.
enum MicrophoneStatus { idle, checking, granted, denied }

class SetupState {
  const SetupState({
    this.micStatus = MicrophoneStatus.idle,
    this.amplitude = 0,
    this.keyText = '',
    this.saving = false,
    this.errorMessage,
  });

  final MicrophoneStatus micStatus;

  /// Volumen real del micrófono, 0..1, mientras dura la prueba de sonido.
  final double amplitude;

  final String keyText;
  final bool saving;
  final String? errorMessage;

  bool get canFinish =>
      micStatus == MicrophoneStatus.granted &&
      keyText.trim().isNotEmpty &&
      !saving;

  SetupState copyWith({
    MicrophoneStatus? micStatus,
    double? amplitude,
    String? keyText,
    bool? saving,
    String? errorMessage,
  }) {
    return SetupState(
      micStatus: micStatus ?? this.micStatus,
      amplitude: amplitude ?? this.amplitude,
      keyText: keyText ?? this.keyText,
      saving: saving ?? this.saving,
      errorMessage: errorMessage,
    );
  }
}
