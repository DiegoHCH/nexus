import 'dart:convert';

import 'package:nexus/features/remote/domain/outbox.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// La cola, en las preferencias.
///
/// **No en el almacén seguro**, y es deliberado: aquí no hay secretos —el texto de un
/// encargo lo escribió el usuario y ya está en su pantalla— y meterlo en el llavero
/// haría que un fallo de este perdiera encargos escritos sin cobertura. El secreto es
/// el token, y ese sí está donde toca.
///
/// La frase de escritura **nunca pasa por aquí**: se teclea cuando hace falta y no se
/// encola. Un outbox con la frase dentro sería la frase guardada en el teléfono, que
/// es exactamente lo que la decisión 2.4 viene a evitar.
class OutboxStoreImpl implements OutboxStore {
  const OutboxStoreImpl();

  static const _clave = 'channel_outbox';

  @override
  Future<List<PendingErrand>> read() async {
    final prefs = await SharedPreferences.getInstance();
    final crudo = prefs.getString(_clave);
    if (crudo == null || crudo.isEmpty) return const [];
    try {
      return Outbox.leer(jsonDecode(crudo) as List<Object?>);
    } on Object {
      // Una cola ilegible se tira. Es lo menos malo: dejarla ahí haría fallar cada
      // arranque en el mismo sitio, y lo que se pierde son encargos que de todas
      // formas no se podían mandar.
      await prefs.remove(_clave);
      return const [];
    }
  }

  @override
  Future<void> write(List<PendingErrand> encargos) async {
    final prefs = await SharedPreferences.getInstance();
    if (encargos.isEmpty) {
      await prefs.remove(_clave);
      return;
    }
    await prefs.setString(
      _clave,
      jsonEncode([for (final e in encargos) e.toJson()]),
    );
  }
}

/// La última foto del Mac, para poder leerla sin red.
class MirrorCacheImpl implements MirrorCache {
  const MirrorCacheImpl();

  static const _clave = 'channel_mirror_cache';

  @override
  Future<Map<String, Object?>?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final crudo = prefs.getString(_clave);
    if (crudo == null || crudo.isEmpty) return null;
    try {
      return jsonDecode(crudo) as Map<String, Object?>;
    } on Object {
      await prefs.remove(_clave);
      return null;
    }
  }

  @override
  Future<void> write(Map<String, Object?> foto) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_clave, jsonEncode(foto));
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_clave);
  }
}
