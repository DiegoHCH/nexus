import 'package:shared_preferences/shared_preferences.dart';

/// Recuerda qué voz eligió el usuario. Aparte de las carpetas porque no tiene
/// nada que ver con permisos: es preferencia de cómo suena, no de qué toca.
class VoicePreferencesDataSource {
  const VoicePreferencesDataSource();

  static const _key = 'voice_name';
  static const _keyAcento = 'voice_accent';

  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  Future<void> write(String voiceName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, voiceName);
  }

  Future<String?> readAccent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAcento);
  }

  /// Se borra la clave en vez de guardar vacío: «no lo he dicho» y «he pedido
  /// el neutro» son cosas distintas, y quien lee tiene que poder separarlas.
  Future<void> writeAccent(String? variante) async {
    final prefs = await SharedPreferences.getInstance();
    if (variante == null || variante.isEmpty) {
      await prefs.remove(_keyAcento);
      return;
    }
    await prefs.setString(_keyAcento, variante);
  }
}
