import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/usecase/usecase.dart';
import 'package:nexus/features/assistant/domain/entities/audio_frame.dart';
import 'package:nexus/features/assistant/presentation/providers/voice_input_providers.dart';
import 'package:nexus/features/onboarding/data/datasources/secure_storage_data_source.dart';
import 'package:nexus/features/onboarding/data/repositories/gemini_key_store_impl.dart';
import 'package:nexus/features/onboarding/domain/entities/onboarding_status.dart';
import 'package:nexus/features/onboarding/domain/repositories/gemini_key_store.dart';
import 'package:nexus/features/onboarding/domain/usecases/check_onboarding_status.dart';
import 'package:nexus/features/onboarding/domain/usecases/save_gemini_key.dart';
import 'package:nexus/features/onboarding/presentation/state/onboarding_state.dart';

final secureStorageDataSourceProvider = Provider<SecureStorageDataSource>(
  (ref) => SecureStorageDataSource(),
);

final geminiKeyStoreProvider = Provider<GeminiKeyStore>(
  (ref) => GeminiKeyStoreImpl(ref.watch(secureStorageDataSourceProvider)),
);

final checkOnboardingStatusProvider = Provider<CheckOnboardingStatus>(
  (ref) => CheckOnboardingStatus(ref.watch(geminiKeyStoreProvider)),
);

final saveGeminiKeyProvider = Provider<SaveGeminiKey>(
  (ref) => SaveGeminiKey(ref.watch(geminiKeyStoreProvider)),
);

/// Siempre pasa por el splash — el orbe apareciendo, nada más — antes de
/// decidir a dónde va: la duración mínima es la del propio splash, no la de
/// la lectura del Keychain, que resuelve casi al instante.
class AppRouteController extends Notifier<AppRouteState> {
  static const _minimumSplash = Duration(milliseconds: 900);

  @override
  AppRouteState build() {
    unawaited(_resolve());
    return const AppRouteLoading();
  }

  Future<void> _resolve() async {
    final results = await (
      Future<void>.delayed(_minimumSplash),
      ref.read(checkOnboardingStatusProvider)(const NoParams()),
    ).wait;
    final OnboardingStatus status = results.$2;
    state = status.hasGeminiKey ? const AppRouteReady() : const AppRouteNeedsSetup();
  }

  void completeSetup() => state = const AppRouteReady();
}

final appRouteControllerProvider = NotifierProvider<AppRouteController, AppRouteState>(
  AppRouteController.new,
);

/// El formulario de la configuración inicial: micrófono y llave de Gemini.
/// Vive aparte de [AppRouteController] porque su ciclo de vida es el de la
/// pantalla, no el de toda la app.
///
/// El micrófono se pide al pulsar "Solicitar", no al construir la pantalla —
/// si se concede, se abre el micrófono real (el mismo [VoiceInput] de la
/// Fase 2) para que la prueba de sonido reaccione a la voz de verdad, no hay
/// nada que simular.
class SetupController extends Notifier<SetupState> {
  StreamSubscription<AudioFrame>? _micSubscription;

  @override
  SetupState build() {
    ref.onDispose(() => _micSubscription?.cancel());
    return const SetupState();
  }

  Future<void> requestMicrophoneAccess() async {
    if (state.micStatus == MicrophoneStatus.checking) return;
    state = state.copyWith(micStatus: MicrophoneStatus.checking);

    final voiceInput = ref.read(voiceInputProvider);
    final granted = await voiceInput.hasPermission();
    if (!granted) {
      state = state.copyWith(micStatus: MicrophoneStatus.denied);
      return;
    }

    state = state.copyWith(micStatus: MicrophoneStatus.granted);
    _micSubscription = voiceInput.listen().listen(
      (frame) => state = state.copyWith(amplitude: frame.amplitude),
      onError: (Object _) {
        state = state.copyWith(micStatus: MicrophoneStatus.denied, amplitude: 0);
      },
    );
  }

  void updateKeyText(String value) => state = state.copyWith(keyText: value);

  Future<bool> finish() async {
    if (!state.canFinish) return false;
    state = state.copyWith(saving: true, errorMessage: null);
    try {
      await ref.read(saveGeminiKeyProvider)(state.keyText);
      await _micSubscription?.cancel();
      _micSubscription = null;
      return true;
    } catch (error) {
      state = state.copyWith(saving: false, errorMessage: error.toString());
      return false;
    }
  }
}

final setupControllerProvider = NotifierProvider<SetupController, SetupState>(
  SetupController.new,
);
