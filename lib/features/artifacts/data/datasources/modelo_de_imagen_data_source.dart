import 'package:shared_preferences/shared_preferences.dart';

/// Recuerda con qué modelo se dibuja. Aparte del llavero: no es un secreto, es
/// una preferencia — y guardar una preferencia donde van los secretos ensucia
/// el sitio donde hay que mirar cuando algo se filtra.
class ModeloDeImagenDataSource {
  const ModeloDeImagenDataSource();

  static const _key = 'image_model';

  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  Future<void> write(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, id);
  }
}
