import 'package:flutter/services.dart';
import 'package:nexus/features/assistant/domain/repositories/voz_de_la_maquina.dart';

/// [VozDeLaMaquina] sobre el canal nativo `NexusVozLocal`.
///
/// Traduce y no decide: lo que se puede y lo que no lo dice el lado de Swift,
/// que es quien sabe si este Mac reconoce sin red.
class VozDeLaMaquinaImpl implements VozDeLaMaquina {
  const VozDeLaMaquinaImpl();

  static const canal = MethodChannel('com.katanalabs.nexus/voz-local');

  @override
  Future<bool> disponible() async {
    try {
      return await canal.invokeMethod<bool>('disponible') ?? false;
    } on MissingPluginException {
      // En una prueba de widget o en otra plataforma no hay canal. Eso es «no
      // disponible», no un fallo que haya que enseñar.
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> pedirPermiso() async {
    try {
      return await canal.invokeMethod<bool>('permiso') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// **Los fallos suben tal cual**, al revés que los de arriba: aquí sí hay
  /// alguien esperando a que pase algo, y un `''` silencioso se leería como «no
  /// entendí» cuando lo que pasó fue que este Mac no puede reconocer sin red.
  @override
  Future<String> escuchar() async =>
      await canal.invokeMethod<String>('escuchar') ?? '';

  @override
  Future<void> decir(String texto) async {
    if (texto.trim().isEmpty) return;
    await canal.invokeMethod<void>('decir', {'texto': texto});
  }

  @override
  Future<void> callar() async => canal.invokeMethod<void>('callar');
}
