import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/assistant/data/datasources/microphone_data_source.dart';
import 'package:nexus/features/assistant/data/repositories/voice_input_impl.dart';
import 'package:nexus/features/assistant/domain/repositories/voice_input.dart';

final microphoneDataSourceProvider = Provider<MicrophoneDataSource>((ref) {
  final dataSource = MicrophoneDataSource();
  ref.onDispose(dataSource.dispose);
  return dataSource;
});

final voiceInputProvider = Provider<VoiceInput>(
  (ref) => VoiceInputImpl(ref.watch(microphoneDataSourceProvider)),
);
