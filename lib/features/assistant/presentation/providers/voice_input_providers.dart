import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/assistant/data/datasources/native_audio_data_source.dart';
import 'package:nexus/features/assistant/data/repositories/voice_input_impl.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_input.dart';

/// Uno solo para toda la app: el motor nativo lleva la cuenta de quién lo usa
/// —micrófono y altavoz lo piden por separado— y con dos instancias esa cuenta
/// se partiría en dos, con lo que cerrar el altavoz dejaría sordo al micro.
final nativeAudioDataSourceProvider = Provider<NativeAudioDataSource>(
  (ref) => NativeAudioDataSource(),
);

final voiceInputProvider = Provider<VoiceInput>(
  (ref) => VoiceInputImpl(ref.watch(nativeAudioDataSourceProvider)),
);
