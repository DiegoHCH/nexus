/// A qué pantalla va la app al arrancar: siempre pasa por el splash
/// ([AppRouteLoading]), y desde ahí a configuración inicial o directo a
/// Reposo según si ya hay una llave de Gemini guardada.
sealed class AppRouteState {
  const AppRouteState();
}

class AppRouteLoading extends AppRouteState {
  const AppRouteLoading();
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
      micStatus == MicrophoneStatus.granted && keyText.trim().isNotEmpty && !saving;

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
