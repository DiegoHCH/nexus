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

enum MicPermissionStatus { pending, granted, denied }

class SetupState {
  const SetupState({
    this.micStatus = MicPermissionStatus.pending,
    this.keyText = '',
    this.saving = false,
    this.errorMessage,
  });

  final MicPermissionStatus micStatus;
  final String keyText;
  final bool saving;
  final String? errorMessage;

  bool get canFinish =>
      micStatus == MicPermissionStatus.granted && keyText.trim().isNotEmpty && !saving;

  SetupState copyWith({
    MicPermissionStatus? micStatus,
    String? keyText,
    bool? saving,
    String? errorMessage,
  }) {
    return SetupState(
      micStatus: micStatus ?? this.micStatus,
      keyText: keyText ?? this.keyText,
      saving: saving ?? this.saving,
      errorMessage: errorMessage,
    );
  }
}
