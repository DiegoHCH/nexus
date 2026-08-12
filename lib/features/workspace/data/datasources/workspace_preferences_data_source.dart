import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Guarda la configuración de carpetas en las preferencias del sistema.
///
/// No va al llavero como la llave de Gemini: una ruta de carpeta y un modo de
/// permiso no son secretos, y meterlos ahí obligaría a desbloquear el llavero
/// para pintar la barra superior.
class WorkspacePreferencesDataSource {
  const WorkspacePreferencesDataSource();

  static const _key = 'workspace';

  Future<Map<String, dynamic>?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      // Preferencia corrupta: se ignora y se arranca de cero. Mejor pedir la
      // carpeta otra vez que arrastrar un estado ilegible.
      return null;
    }
  }

  Future<void> write(Map<String, dynamic> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(value));
  }
}
