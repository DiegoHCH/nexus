import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/usecase/usecase.dart';
import 'package:nexus/features/assistant/domain/entities/audio_frame.dart';
import 'package:nexus/features/assistant/presentation/providers/voice_input_providers.dart';
import 'package:nexus/core/storage/secure_storage_data_source.dart';
import 'package:nexus/features/onboarding/data/repositories/gemini_key_store_impl.dart';
import 'package:nexus/features/onboarding/domain/repositories/gemini_key_store.dart';
import 'package:nexus/features/onboarding/domain/entities/readiness.dart';
import 'package:nexus/features/onboarding/domain/repositories/readiness_probe.dart';
import 'package:nexus/features/onboarding/data/repositories/readiness_probe_impl.dart';
import 'package:nexus/features/onboarding/domain/usecases/check_readiness.dart';
import 'package:nexus/features/onboarding/domain/usecases/save_gemini_key.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:nexus/features/onboarding/presentation/state/onboarding_state.dart';

final secureStorageDataSourceProvider = Provider<SecureStorageDataSource>(
  (ref) => SecureStorageDataSource(),
);

final geminiKeyStoreProvider = Provider<GeminiKeyStore>(
  (ref) => GeminiKeyStoreImpl(ref.watch(secureStorageDataSourceProvider)),
);

final readinessProbeProvider = Provider<ReadinessProbe>(
  (ref) => ReadinessProbeImpl(),
);

final checkReadinessProvider = Provider<CheckReadiness>(
  (ref) => CheckReadiness(
    ref.watch(readinessProbeProvider),
    ref.watch(geminiKeyStoreProvider),
  ),
);

final saveGeminiKeyProvider = Provider<SaveGeminiKey>(
  (ref) => SaveGeminiKey(ref.watch(geminiKeyStoreProvider)),
);

/// Siempre pasa por el splash — el orbe apareciendo, nada más — antes de
/// decidir a dónde va: la duración mínima es la del propio splash, no la de
/// la lectura del Keychain, que resuelve casi al instante.
class AppRouteController extends Notifier<AppRouteState> {
  static const _minimumSplash = Duration(milliseconds: 900);

  /// Lo último que se supo de si hay dónde trabajar.
  ///
  /// En un campo porque [continueAnyway] es síncrono y no puede esperar al
  /// disco, y porque la respuesta no cambia entre el splash y ese botón: la
  /// pantalla que lo enseña no empareja carpetas.
  bool _hayCarpeta = false;

  @override
  AppRouteState build() {
    unawaited(_resolve());
    return const AppRouteLoading();
  }

  Future<void> _resolve() async {
    // Pase lo que pase, de aquí se sale a alguna pantalla. Esto corre sin que
    // nadie espere su resultado, así que una excepción no aparece por ningún
    // lado: deja el estado en «cargando» para siempre y la app se queda en el
    // splash sin explicar nada. Ante la duda, se pide la configuración —que se
    // puede completar— en vez de quedarse mirando el orbe.
    try {
      final results = await (
        Future<void>.delayed(_minimumSplash),
        ref.read(checkReadinessProvider)(const NoParams()),
        ref.read(workspaceStoreProvider).read(),
      ).wait;
      final Readiness readiness = results.$2;
      _hayCarpeta = results.$3.folders.isNotEmpty;
      // Sale con `unawaited` y espera al menos lo que dure el splash: si la
      // pantalla se fue antes, el proveedor ya no existe.
      if (!ref.mounted) return;
      state = readiness.blocksWork
          ? AppRouteNotReady(readiness)
          : _dondeEntrar();
    } catch (error) {
      debugPrint('No se pudo resolver el arranque: $error');
      if (!ref.mounted) return;
      state = const AppRouteNeedsSetup();
    }
  }

  /// Resuelto lo del sistema, queda lo de la app: **una carpeta donde trabajar**.
  ///
  /// Antes era la llave de Gemini, y eso contradecía a la propia app: la regla
  /// de [Readiness.blocksWork] dice, escrito ahí mismo, que sin llave se puede
  /// trabajar por texto — y toda carpeta nace en solo texto, así que la llave se
  /// pedía en la puerta para una función que nadie iba a usar todavía. Encima la
  /// pantalla prometía «puedes cambiar esto después en Ajustes» y no había
  /// ningún sitio donde cambiarla.
  ///
  /// La carpeta sí es de verdad obligatoria y por un motivo que se puede
  /// enseñar: sin ella `claude -p` hereda el directorio de la app —que para un
  /// bundle lanzado por launchd es `/`— y el primer encargo responde sobre la
  /// raíz del disco.
  AppRouteState _dondeEntrar() =>
      _hayCarpeta ? const AppRouteReady() : const AppRouteNeedsSetup();

  /// Volver a preguntar tras instalar o iniciar sesión, sin reiniciar la app.
  /// Pasa por el splash otra vez a propósito: la comprobación tarda, y un botón
  /// que no cambia nada durante un segundo se siente roto.
  void recheck() {
    state = const AppRouteLoading();
    unawaited(_resolve());
  }

  /// Entrar de todas formas.
  ///
  /// Existe porque esta pantalla informa, no guarda la puerta: puede haber
  /// motivos para pasar —mirar el historial, cambiar los ajustes— y dejar a
  /// alguien encerrado fuera de su propia app por una comprobación nuestra sería
  /// peor que el fallo que viene a evitar.
  void continueAnyway() => state = _dondeEntrar();

  void completeSetup() => state = const AppRouteReady();
}

final appRouteControllerProvider =
    NotifierProvider<AppRouteController, AppRouteState>(AppRouteController.new);

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
        state = state.copyWith(
          micStatus: MicrophoneStatus.denied,
          amplitude: 0,
        );
      },
    );
  }

  void updateKeyText(String value) => state = state.copyWith(keyText: value);

  Future<bool> finish() async {
    if (!state.canFinish) return false;
    state = state.copyWith(saving: true, errorMessage: null);
    try {
      // **Solo si escribiste una.** Guardar la cadena vacía dejaría en el
      // llavero una llave que existe y no sirve, y entonces la pantalla de
      // salidas diría que Gemini está disponible cuando la sesión de voz va a
      // fallar en cuanto se abra.
      if (state.keyText.trim().isNotEmpty) {
        await ref.read(saveGeminiKeyProvider)(state.keyText);
      }
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
