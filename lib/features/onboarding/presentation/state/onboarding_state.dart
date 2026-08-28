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

  /// Si se puede entrar ya.
  ///
  /// **Ni el micrófono ni la llave**, y eso es el arreglo: los dos eran
  /// obligatorios para pasar de esta pantalla, y los dos son de la voz — que
  /// está apagada por defecto en toda carpeta, y que un repositorio puede
  /// apagar del todo. Se pedían las credenciales de una función que nadie iba a
  /// usar todavía, y a una fintech se le pedía una llave de Google antes de
  /// enseñarle nada.
  ///
  /// Lo único obligatorio —la carpeta de trabajo— no se mira aquí sino en la
  /// pantalla, porque no vive en este estado: vive en el workspace.
  bool get canFinish => !saving;

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
