import 'package:nexus/features/e2e/presentation/providers/correr_una_prueba_desde_la_voz.dart';
import 'package:nexus/features/history/presentation/providers/el_parte_desde_la_voz.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/i18n/language_preference.dart';
import 'package:nexus/features/assistant/data/datasources/gemini_live_data_source.dart';
import 'package:nexus/features/assistant/data/repositories/audio_output_impl.dart';
import 'package:nexus/features/assistant/data/repositories/gemini_voice_gateway.dart';
import 'package:nexus/features/assistant/domain/repositories/audio_output.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_gateway.dart';
import 'package:nexus/features/agenda/presentation/providers/el_vigilante_de_la_agenda.dart';
import 'package:nexus/features/assistant/domain/usecases/hold_voice_conversation.dart';
import 'package:nexus/features/assistant/presentation/providers/claude_bridge_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/voice_input_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/voice_preference_providers.dart';
import 'package:nexus/features/remote/domain/audio_output_compartido.dart';
import 'package:nexus/features/remote/presentation/providers/channel_providers.dart';
import 'package:nexus/features/onboarding/presentation/providers/onboarding_providers.dart';

final geminiLiveDataSourceProvider = Provider<GeminiLiveDataSource>(
  (ref) => const GeminiLiveDataSource(),
);

/// La llave la pone onboarding, que es quien la guardó. El puente entre las
/// dos features se hace aquí, en el cableado, y no dentro del gateway: así
/// `assistant` no depende de `onboarding` más que en este punto.
final voiceGatewayProvider = Provider<VoiceGateway>((ref) {
  final keyStore = ref.watch(geminiKeyStoreProvider);
  return GeminiVoiceGateway(
    ref.watch(geminiLiveDataSourceProvider),
    keyStore.read,
    () => ref.read(voicePreferenceProvider).name,
    () => ref.read(stringsProvider).languageName,
  );
});

/// El altavoz de la sesión: **el del teléfono si la pregunta vino de ahí, y si no el
/// del Mac**.
///
/// El gemelo de `voiceInputProvider`, y el mismo motivo para existir: la sesión de voz
/// sigue hablándole a un solo puerto, así que la voz de vuelta no obliga a tocar
/// `HoldVoiceConversation` para meterle un segundo camino.
final audioOutputProvider = Provider<AudioOutput>((ref) {
  final delMac = AudioOutputImpl(ref.watch(nativeAudioDataSourceProvider));
  ref.onDispose(delMac.stop);
  return AudioOutputCompartido(
    local: delMac,
    remoto: ref.watch(remoteAudioSinkProvider),
    fuente: ref.watch(remoteVoiceSourceProvider),
  );
});

/// Por conversación, porque el encargo que salga de la voz tiene que ir a la
/// carpeta de **esa** conversación. El micrófono y el altavoz siguen siendo
/// únicos: los comparten porque solo la del foco puede abrir sesión.
final holdVoiceConversationProvider =
    Provider.family<HoldVoiceConversation, String>(
      (ref, conversationId) => HoldVoiceConversation(
        ref.watch(voiceInputProvider),
        ref.watch(voiceGatewayProvider),
        ref.watch(audioOutputProvider),
        ref.watch(askClaudeProvider(conversationId)),
        // `debugPrint` y no `developer.log`: es lo único que sale por la
        // consola de `flutter run`, que es donde se leen estas sesiones. Aquí
        // sí se puede, porque esto es cableado y ya conoce Flutter.
        debugPrint,
        ref.watch(correrUnaPruebaProvider),
        ref.watch(elParteDelDiaProvider(conversationId)),
        ref.watch(laAgendaDeHoyProvider),
      ),
    );
