import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/assistant/presentation/providers/voice_input_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Un aparato por el que puede sonar la respuesta.
@immutable
class AudioDeviceOption {
  const AudioDeviceOption({
    required this.id,
    required this.name,
    required this.isDefault,
  });

  final int id;
  final String name;

  /// El que el sistema usa ahora mismo. Se marca para que elegir «el del
  /// sistema» no sea elegir a ciegas.
  final bool isDefault;
}

final audioOutputDevicesProvider = FutureProvider<List<AudioDeviceOption>>((
  ref,
) async {
  final devices = await ref
      .watch(nativeAudioDataSourceProvider)
      .outputDevices();
  return [
    for (final device in devices)
      AudioDeviceOption(
        id: (device['id'] as num).toInt(),
        name: device['name'] as String? ?? '',
        isDefault: device['isDefault'] as bool? ?? false,
      ),
  ];
});

/// Por dónde suena Nexus. `null` es «el que diga el sistema», que es lo
/// correcto por defecto: cambiar de auriculares en macOS ya cambia la salida de
/// todo, y una app empeñada en la suya es la que se queda sonando por el
/// altavoz cuando te pones los cascos.
class AudioOutputController extends Notifier<int?> {
  static const _key = 'audio_output_device';

  @override
  int? build() {
    unawaited(_load());
    return null;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_key);
    if (stored == null) return;
    // Sale con `unawaited`: si la pantalla se fue mientras tanto, el proveedor
    // ya no existe y esto lanzaria en vez de no hacer nada.
    if (!ref.mounted) return;
    state = stored;
    await ref.read(nativeAudioDataSourceProvider).setOutputDevice(stored);
  }

  Future<void> select(int? id) async {
    state = id;
    await ref.read(nativeAudioDataSourceProvider).setOutputDevice(id);
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setInt(_key, id);
    }
  }
}

final audioOutputControllerProvider =
    NotifierProvider<AudioOutputController, int?>(AudioOutputController.new);
