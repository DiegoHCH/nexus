import 'package:shared_preferences/shared_preferences.dart';

/// Lo que se recuerda de los avisos: si están encendidos, cuánto antes y en qué
/// carpeta se mira el calendario.
///
/// En las preferencias de siempre y no en el llavero: no hay ningún secreto
/// aquí, y meter lo que no lo es donde van los secretos ensucia el sitio al que
/// hay que mirar cuando algo se filtra.
class AvisosPreferenciasDataSource {
  const AvisosPreferenciasDataSource();

  static const _encendidos = 'avisos_agenda_encendidos';
  static const _minutos = 'avisos_agenda_minutos';
  static const _carpeta = 'avisos_agenda_carpeta';

  Future<({bool encendidos, int minutos, String? carpeta})> leer() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      // Apagados de fábrica. Una app que empieza a hablarte sola el día que se
      // actualiza es una app que asusta, aunque lo que diga sea útil.
      encendidos: prefs.getBool(_encendidos) ?? false,
      minutos: prefs.getInt(_minutos) ?? 5,
      carpeta: prefs.getString(_carpeta),
    );
  }

  Future<void> escribir({
    required bool encendidos,
    required int minutos,
    String? carpeta,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_encendidos, encendidos);
    await prefs.setInt(_minutos, minutos);
    if (carpeta == null) {
      await prefs.remove(_carpeta);
    } else {
      await prefs.setString(_carpeta, carpeta);
    }
  }
}
