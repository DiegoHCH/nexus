import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Guarda la memoria de conversaciones en las preferencias del sistema.
class ConversationMemoryDataSource {
  const ConversationMemoryDataSource();

  static const _key = 'conversation_memory';

  Future<Map<String, dynamic>> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : {};
    } on FormatException {
      // Preferencia ilegible: se arranca sin memoria en vez de arrastrar algo
      // corrupto. Perder el hilo es molesto; reanudar una sesión inventada, peor.
      return {};
    }
  }

  Future<void> write(Map<String, dynamic> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(value));
  }
}
