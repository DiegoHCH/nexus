import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/assistant/data/datasources/voice_preferences_data_source.dart';
import 'package:nexus/features/assistant/domain/entities/nexus_voice.dart';

final voicePreferencesDataSourceProvider = Provider<VoicePreferencesDataSource>(
  (ref) => const VoicePreferencesDataSource(),
);

/// La voz elegida. Cambiarla vale desde la siguiente sesión: el timbre se fija
/// en el `setup` del socket y una sesión abierta no lo renegocia.
class VoicePreferenceController extends Notifier<NexusVoice> {
  @override
  NexusVoice build() {
    unawaited(_load());
    return NexusVoice.fallback;
  }

  Future<void> _load() async {
    final saved = await ref.read(voicePreferencesDataSourceProvider).read();
    state = NexusVoice.byName(saved);
  }

  Future<void> select(NexusVoice voice) async {
    state = voice;
    await ref.read(voicePreferencesDataSourceProvider).write(voice.name);
  }
}

final voicePreferenceProvider =
    NotifierProvider<VoicePreferenceController, NexusVoice>(
      VoicePreferenceController.new,
    );
