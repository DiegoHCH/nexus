import 'package:shared_preferences/shared_preferences.dart';

/// Recuerda qué voz eligió el usuario. Aparte de las carpetas porque no tiene
/// nada que ver con permisos: es preferencia de cómo suena, no de qué toca.
class VoicePreferencesDataSource {
  const VoicePreferencesDataSource();

  static const _key = 'voice_name';

  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  Future<void> write(String voiceName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, voiceName);
  }
}
