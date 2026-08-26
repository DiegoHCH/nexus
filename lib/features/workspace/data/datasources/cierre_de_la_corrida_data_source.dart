import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Cómo terminó una tarea. Son tres y no dos porque **lo que se mide cambia en cada una**.
enum ComoTermino {
  /// Terminó y va a producción. Cuenta entera.
  cerrada,

  /// Un POC o una medición que sí avanzó y no va a producción.
  ///
  /// Existe para evitar un error concreto: cancelar algo que avanzó pierde la medición
  /// —cancelar no mira el gate— y tres horas de trabajo real acaban apareciendo como
  /// «plan 1m · construyendo — · cierre —». Se mide, pero no se promedia con trabajo
  /// verificado.
  sinProduccion,

  /// No dejó nada: una prueba, algo que se abandonó. No mide.
  cancelada;

  /// Si esta salida entra en los promedios de trabajo verificado.
  bool get promedia => this == cerrada;
}

/// El cierre de una corrida: cómo terminó y en una frase, qué se hizo.
///
/// **La narrativa es obligatoria y por eso no es opcional aquí.** Un cierre sin ella es un
/// booleano con más pasos: el valor de esto no es marcar la tarea, es que quede escrito en
/// palabras de una persona qué salió — que es lo único que después sirve para contarlo a
/// quien no programa.
@immutable
class Cierre {
  const Cierre({
    required this.como,
    required this.narrativa,
    required this.cuando,
  });

  final ComoTermino como;

  /// Lo que se hizo, o por qué se cancela. La misma casilla y dos preguntas distintas:
  /// las dos exigen escribir algo, que es el punto.
  final String narrativa;

  final DateTime cuando;

  Map<String, Object?> toJson() => {
    'como': como.name,
    'narrativa': narrativa,
    'cuando': cuando.millisecondsSinceEpoch ~/ 1000,
  };

  static Cierre? fromJson(Object? crudo) {
    if (crudo is! Map) return null;
    final narrativa = (crudo['narrativa'] as String?)?.trim() ?? '';
    if (narrativa.isEmpty) return null;
    final cuando = crudo['cuando'];
    if (cuando is! num) return null;
    return Cierre(
      como: ComoTermino.values.firstWhere(
        (valor) => valor.name == crudo['como'],
        orElse: () => ComoTermino.cerrada,
      ),
      narrativa: narrativa,
      cuando: DateTime.fromMillisecondsSinceEpoch(
        (cuando * 1000).round(),
        isUtc: true,
      ),
    );
  }
}

/// Los cierres de una carpeta, por rama.
///
/// **Una lista y no el último**, y esa es la decisión de fondo del archivo: una rama se
/// cierra más de una vez. El PR vuelve con observaciones, se corrige y se cierra otra vez
/// — y ahí hay dos corridas del mismo trabajo que no son la misma cosa. Guardar solo la
/// última haría desaparecer la primera, que suele ser la más larga.
class CierreDeLaCorridaDataSource {
  const CierreDeLaCorridaDataSource();

  static const _sinRama = ':sin-rama';

  Directory _dir(String configDir) => Directory('$configDir/nexus-cierres');

  /// Todos los cierres de esa rama, del más antiguo al más reciente.
  Future<List<Cierre>> leer(
    String configDir,
    String carpeta, {
    String? rama,
  }) async {
    final guardado = await _guardado(configDir, carpeta);
    final ramas = guardado?['ramas'];
    if (ramas is! Map) return const [];
    final suyos = ramas[_clave(rama)];
    if (suyos is! List) return const [];
    return [for (final crudo in suyos) ?Cierre.fromJson(crudo)]
      ..sort((a, b) => a.cuando.compareTo(b.cuando));
  }

  /// Añade un cierre. **No sustituye al anterior**: se apila.
  Future<List<Cierre>> cerrar(
    String configDir,
    String carpeta, {
    String? rama,
    required ComoTermino como,
    required String narrativa,
  }) async {
    final limpia = narrativa.trim();
    // Sin narrativa no se cierra, y se contesta con lo que ya había en vez de con un
    // error: preguntar «¿cerramos?» no puede ejecutar un cierre.
    if (limpia.isEmpty) return leer(configDir, carpeta, rama: rama);

    final dir = _dir(configDir)..createSync(recursive: true);
    final archivo = File('${dir.path}/${_nombre(carpeta)}.json');

    final guardado = await _guardado(configDir, carpeta);
    final ramas = <String, Object?>{};
    if (guardado?['ramas'] is Map) {
      ramas.addAll((guardado!['ramas'] as Map).cast<String, Object?>());
    }

    final nuevo = Cierre(
      como: como,
      narrativa: limpia,
      cuando: DateTime.now().toUtc(),
    );
    final anteriores = ramas[_clave(rama)];
    ramas[_clave(rama)] = [
      if (anteriores is List) ...anteriores,
      nuevo.toJson(),
    ];

    await archivo.writeAsString(
      '${jsonEncode({'carpeta': carpeta, 'ramas': ramas})}\n',
    );
    return leer(configDir, carpeta, rama: rama);
  }

  Future<Map<String, Object?>?> _guardado(
    String configDir,
    String carpeta,
  ) async {
    final archivo = File('${_dir(configDir).path}/${_nombre(carpeta)}.json');
    if (!archivo.existsSync()) return null;
    try {
      final leido = jsonDecode(await archivo.readAsString());
      return leido is Map ? leido.cast<String, Object?>() : null;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  static String _clave(String? rama) =>
      rama == null || rama.isEmpty ? _sinRama : rama;

  /// El mismo criterio que el plan y el gate: la carpeta resuelta, en un nombre legible.
  static String _nombre(String carpeta) {
    var ruta = carpeta;
    try {
      ruta = Directory(carpeta).resolveSymbolicLinksSync();
    } on FileSystemException {
      // Puede no existir todavía; se compara la ruta tal cual.
    }
    return ruta
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }
}
