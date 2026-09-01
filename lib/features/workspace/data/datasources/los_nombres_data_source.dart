import 'package:shared_preferences/shared_preferences.dart';

import 'package:nexus/features/workspace/domain/entities/los_nombres.dart';

/// Los dos nombres, en las preferencias de siempre.
///
/// No en el llavero: no hay ningún secreto aquí. Meter lo que no lo es donde van
/// los secretos ensucia el sitio al que hay que mirar cuando algo se filtra — es
/// la misma razón que ya está escrita en las preferencias de los avisos.
class LosNombresDataSource {
  const LosNombresDataSource();

  static const _agente = 'nombre_del_agente';
  static const _tuyo = 'nombre_del_usuario';

  Future<LosNombres> leer() async {
    final prefs = await SharedPreferences.getInstance();
    return LosNombres(
      agente: _limpio(prefs.getString(_agente)),
      tuyo: _limpio(prefs.getString(_tuyo)),
    );
  }

  Future<void> escribir(LosNombres nombres) async {
    final prefs = await SharedPreferences.getInstance();
    await _guardar(prefs, _agente, nombres.agente);
    await _guardar(prefs, _tuyo, nombres.tuyo);
  }

  /// Se borra la clave en vez de guardar vacío: «no lo he dicho» y «lo he dicho
  /// en blanco» tienen que leerse igual, y la ausencia es la forma honesta de
  /// decirlo.
  static Future<void> _guardar(
    SharedPreferences prefs,
    String clave,
    String? valor,
  ) async {
    final limpio = _limpio(valor);
    if (limpio == null) {
      await prefs.remove(clave);
    } else {
      await prefs.setString(clave, limpio);
    }
  }

  static String? _limpio(String? crudo) {
    final valor = crudo?.trim();
    return valor == null || valor.isEmpty ? null : valor;
  }
}
