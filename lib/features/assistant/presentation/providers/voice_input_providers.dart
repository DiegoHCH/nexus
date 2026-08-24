import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/assistant/data/datasources/native_audio_data_source.dart';
import 'package:nexus/features/assistant/data/repositories/voice_input_impl.dart';
import 'package:nexus/features/assistant/data/repositories/microphone_access_impl.dart';
import 'package:nexus/features/assistant/domain/repositories/microphone_access.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_input.dart';
import 'package:nexus/features/remote/presentation/providers/channel_providers.dart';
import 'package:nexus/features/remote/domain/voice_input_compartido.dart';

/// Uno solo para toda la app: el motor nativo lleva la cuenta de quién lo usa
/// —micrófono y altavoz lo piden por separado— y con dos instancias esa cuenta
/// se partiría en dos, con lo que cerrar el altavoz dejaría sordo al micro.
final nativeAudioDataSourceProvider = Provider<NativeAudioDataSource>(
  (ref) => NativeAudioDataSource(),
);

/// El micrófono de la sesión: el del teléfono si lo está sosteniendo, y si no el del
/// Mac.
///
/// **Un solo puerto y dos fuentes**, que es lo que hace que la voz remota no obligue a
/// tocar `HoldVoiceConversation` —el trozo con más lógica del proyecto— para meterle un
/// segundo camino.
final voiceInputProvider = Provider<VoiceInput>(
  (ref) => VoiceInputCompartido(
    local: VoiceInputImpl(ref.watch(nativeAudioDataSourceProvider)),
    remoto: ref.watch(remoteVoiceSourceProvider),
  ),
);

/// El permiso, para consultarlo sin pedirlo.
final microphoneAccessProvider = Provider<MicrophoneAccess>(
  (ref) => const MicrophoneAccessImpl(),
);
