import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/usecase/usecase.dart';
import 'package:nexus/features/onboarding/data/datasources/microphone_permission_data_source.dart';
import 'package:nexus/features/onboarding/data/datasources/secure_storage_data_source.dart';
import 'package:nexus/features/onboarding/data/repositories/gemini_key_store_impl.dart';
import 'package:nexus/features/onboarding/data/repositories/microphone_access_impl.dart';
import 'package:nexus/features/onboarding/domain/entities/onboarding_status.dart';
import 'package:nexus/features/onboarding/domain/repositories/gemini_key_store.dart';
import 'package:nexus/features/onboarding/domain/repositories/microphone_access.dart';
import 'package:nexus/features/onboarding/domain/usecases/check_onboarding_status.dart';
import 'package:nexus/features/onboarding/domain/usecases/request_microphone_permission.dart';
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

final microphonePermissionDataSourceProvider = Provider<MicrophonePermissionDataSource>(
  (ref) => MicrophonePermissionDataSource(),
);

final microphoneAccessProvider = Provider<MicrophoneAccess>(
  (ref) => MicrophoneAccessImpl(ref.watch(microphonePermissionDataSourceProvider)),
);

final requestMicrophonePermissionProvider = Provider<RequestMicrophonePermission>(
  (ref) => RequestMicrophonePermission(ref.watch(microphoneAccessProvider)),
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

/// El formulario de la configuración inicial: permiso de micrófono y llave
/// de Gemini. Vive aparte de [AppRouteController] porque su ciclo de vida es
/// el de la pantalla, no el de toda la app.
class SetupController extends Notifier<SetupState> {
  @override
  SetupState build() => const SetupState();

  void updateKeyText(String value) => state = state.copyWith(keyText: value);

  Future<void> requestMicrophonePermission() async {
    final granted = await ref.read(requestMicrophonePermissionProvider)(const NoParams());
    state = state.copyWith(
      micStatus: granted ? MicPermissionStatus.granted : MicPermissionStatus.denied,
    );
  }

  Future<bool> finish() async {
    if (!state.canFinish) return false;
    state = state.copyWith(saving: true, errorMessage: null);
    try {
      await ref.read(saveGeminiKeyProvider)(state.keyText);
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
