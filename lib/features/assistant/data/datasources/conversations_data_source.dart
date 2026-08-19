import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Recuerda qué conversaciones estaban abiertas, para reabrirlas al arrancar.
class ConversationsDataSource {
  const ConversationsDataSource();

  static const _key = 'conversations';

  Future<Map<String, dynamic>> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : {};
    } on FormatException {
      return {};
    }
  }

  Future<void> write(Map<String, dynamic> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(value));
  }
}
