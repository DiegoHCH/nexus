import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/assistant/data/datasources/voice_preferences_data_source.dart';
import 'package:nexus/features/assistant/domain/entities/el_acento.dart';
import 'package:nexus/features/assistant/domain/entities/nexus_voice.dart';

final voicePreferencesDataSourceProvider = Provider<VoicePreferencesDataSource>(
  (ref) => const VoicePreferencesDataSource(),
);

/// La voz elegida. Cambiarla vale desde la siguiente sesión: el timbre se fija
/// en el `setup` del socket y una sesión abierta no lo renegocia.
class VoicePreferenceController extends Notifier<NexusVoice> {
  final _leida = Completer<void>();

  /// Cuando la voz elegida ya se ha leído del disco.
  ///
  /// 🔴 **Nace en `fallback` y el disco se lee después**, así que quien conecte
  /// en el arranque abre la sesión con la voz de fábrica. Para una conversación
  /// eso no se nota —se abre cuando tú la abres, mucho después— pero la puerta
  /// del arranque conecta sola, y saludaba con una voz que nadie eligió.
  Future<void> get leida => _leida.future;

  @override
  NexusVoice build() {
    unawaited(_load());
    return NexusVoice.fallback;
  }

  Future<void> _load() async {
    try {
      await _leerla();
    } finally {
      // Pase lo que pase: quien espera tiene que poder seguir, aunque sea con
      // la voz de fábrica.
      if (!_leida.isCompleted) _leida.complete();
    }
  }

  Future<void> _leerla() async {
    final saved = await ref.read(voicePreferencesDataSourceProvider).read();
    // Sale con `unawaited`: si la pantalla se fue mientras tanto, el proveedor
    // ya no existe y esto lanzaria en vez de no hacer nada.
    if (!ref.mounted) return;
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

/// El acento con el que se pide que hable.
///
/// Vive al lado de la voz porque es lo mismo —cómo suena— y se guarda en el
/// mismo sitio. Pero al revés que el timbre, **esto sí puede cambiar a mitad
/// de sesión**: el timbre se fija en el `setup` del socket y el acento viaja en
/// la instrucción del sistema, que se compone al conectar. En la práctica los
/// dos valen desde la siguiente sesión; se dice aquí para que nadie asuma que
/// comparten el motivo.
class ElAcentoController extends Notifier<ElAcento> {
  @override
  ElAcento build() {
    unawaited(_load());
    return const ElAcento.sinElegir();
  }

  Future<void> _load() async {
    final saved = await ref
        .read(voicePreferencesDataSourceProvider)
        .readAccent();
    if (!ref.mounted) return;
    state = ElAcento.porNombre(saved);
  }

  Future<void> select(ElAcento acento) async {
    state = acento;
    await ref
        .read(voicePreferencesDataSourceProvider)
        .writeAccent(acento.guardado);
  }
}

final elAcentoProvider = NotifierProvider<ElAcentoController, ElAcento>(
  ElAcentoController.new,
);
