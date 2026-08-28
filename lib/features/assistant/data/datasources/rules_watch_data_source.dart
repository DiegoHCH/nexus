import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:nexus/features/assistant/data/repositories/project_context_prompt.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Se acuerda de cómo estaban los archivos de reglas de cada carpeta, para
/// poder decir cuándo cambian.
///
/// Delimitar el texto del repositorio evita que mande; esto es la otra mitad,
/// y es la que se ve: un `CLAUDE.md` que cambia de un día para otro —porque
/// alguien lo commiteó, porque cambiaste de rama, porque el clon se
/// actualizó— es un cambio silencioso en lo que Claude lee **antes de cada
/// encargo**. No bloquea nada. Solo convierte ese cambio en una noticia.
///
/// La primera vez que se ve una carpeta no se avisa de nada: eso no es un
/// cambio, es la línea base. Avisar ahí haría que emparejar una carpeta nueva
/// empezara con una alarma, y una alarma que salta siempre deja de leerse.
class RulesWatchDataSource {
  const RulesWatchDataSource();

  /// Una entrada por carpeta emparejada, y dentro una huella por archivo. Cabe
  /// de sobra en las preferencias: son unas pocas carpetas y una línea por
  /// archivo de reglas.
  static const _key = 'reglas_vistas';

  /// Qué archivos de reglas han cambiado desde la última vez que se miró.
  ///
  /// Cuenta también uno **nuevo**: un `CLAUDE.md` que aparece en una carpeta
  /// superior no estaba y ahora manda, que es el mismo cambio visto de otra
  /// forma. Uno que desaparece no se cuenta: dejar de leer reglas no añade
  /// nada que no estuviera.
  Future<List<String>> revisar(String folder, List<ContextFile> rules) async {
    final prefs = await SharedPreferences.getInstance();
    final todas = _read(prefs);

    final ahora = {
      for (final file in rules)
        file.path: sha256.convert(utf8.encode(file.content)).toString(),
    };
    final antes = todas[folder];

    if (antes == null) {
      // Línea base: se guarda y se calla.
      todas[folder] = ahora;
      await prefs.setString(_key, jsonEncode(todas));
      return const [];
    }

    final cambios = [
      for (final entry in ahora.entries)
        if (antes[entry.key] != entry.value) entry.key,
    ];

    // Se escribe solo si hay algo que escribir: esto corre en cada encargo, y
    // guardar lo mismo otra vez es trabajo de disco por turno a cambio de nada.
    if (cambios.isNotEmpty || antes.length != ahora.length) {
      todas[folder] = ahora;
      await prefs.setString(_key, jsonEncode(todas));
    }

    return cambios;
  }

  /// Lo guardado, o vacío. Unas preferencias ilegibles no pueden impedir un
  /// encargo: se pierde la memoria de las huellas y se vuelve a empezar, que
  /// es exactamente lo que pasa en un Mac recién instalado.
  Map<String, Map<String, String>> _read(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.value case final Map<String, dynamic> archivos)
            entry.key: {
              for (final archivo in archivos.entries)
                if (archivo.value case final String huella) archivo.key: huella,
            },
      };
    } on FormatException {
      return {};
    }
  }
}
