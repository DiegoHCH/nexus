import 'package:flutter/foundation.dart';

/// Una línea de `.nexus-reglas`.
///
/// Hay dos formas y hacen cosas distintas: sin flecha es una regla que Nexus carga
/// **siempre**, antes de cada encargo; con flecha es una regla de capa que solo viaja
/// cuando se toca algo que encaja con el patrón.
@immutable
class ReglaDeclarada {
  const ReglaDeclarada({required this.ruta, this.patron});

  /// Qué archivos la activan, o `null` si va siempre.
  final String? patron;

  /// Dónde vive la regla, tal como se escribió: absoluta, con `~`, o relativa al repo.
  final String ruta;

  bool get siempre => patron == null;
}

/// Cómo se lee `.nexus-reglas` **en Dart**, con la misma semántica que el gancho.
///
/// Existe porque la app lo leía a medias: cargaba toda línea que no fuera un comentario
/// como si fuera una ruta, así que un proyecto con reglas por capa metía
/// `**/domain/** -> …/dominio.md` en cada encargo como una regla inexistente, con su aviso
/// de «Nexus no encontró esta regla». La forma con flecha la añadió el gancho y este lado
/// nunca se enteró.
///
/// **El emparejado imita a `fnmatch` de Python**, que es lo que usa el gancho, y no a las
/// reglas de `.gitignore`. La diferencia importa: en `fnmatch` un `*` **atraviesa las
/// barras**, así que `**/domain/**` y `*/domain/*` encajan con lo mismo. Copiar la
/// semántica de git aquí habría hecho que la app y el gancho eligieran reglas distintas
/// para el mismo archivo, sin que nada fallara.
abstract final class ReglasDeclaradas {
  static const archivo = '.nexus-reglas';

  static List<ReglaDeclarada> leer(String contenido) {
    final reglas = <ReglaDeclarada>[];
    for (final linea in contenido.split('\n')) {
      final crudo = linea.trim();
      if (crudo.isEmpty || crudo.startsWith('#')) continue;

      final flecha = crudo.indexOf('->');
      if (flecha < 0) {
        reglas.add(ReglaDeclarada(ruta: crudo));
        continue;
      }
      final patron = crudo.substring(0, flecha).trim();
      final ruta = crudo.substring(flecha + 2).trim();
      // Media línea no es una regla: sin patrón no se sabe cuándo aplica y sin ruta no
      // hay nada que cargar. Se salta en vez de inventarse la mitad que falta.
      if (patron.isEmpty || ruta.isEmpty) continue;
      reglas.add(ReglaDeclarada(patron: patron, ruta: ruta));
    }
    return reglas;
  }

  /// Las reglas de capa que aplican a esos archivos, sin repetir.
  ///
  /// Se prueba contra la ruta **relativa al repo**, que es como se escriben los patrones:
  /// quien escribe `**/domain/**` no sabe dónde está clonado el proyecto.
  static List<String> paraArchivos(
    List<ReglaDeclarada> reglas,
    List<String> archivos,
  ) {
    final elegidas = <String>[];
    for (final regla in reglas) {
      final patron = regla.patron;
      if (patron == null) continue;
      if (archivos.any((archivo) => encaja(patron, archivo))) {
        if (!elegidas.contains(regla.ruta)) elegidas.add(regla.ruta);
      }
    }
    return elegidas;
  }

  /// Qué archivos de la lista activan esa regla. Para poder decir **por qué** viaja.
  static List<String> archivosDe(String patron, List<String> archivos) =>
      archivos.where((archivo) => encaja(patron, archivo)).toList();

  /// `fnmatch` de Python, traducido.
  ///
  /// `*` cualquier cosa —barras incluidas—, `?` un carácter, `[abc]` un conjunto y
  /// `[!abc]` su negado. Todo lo demás es literal, y se compara la cadena entera.
  static bool encaja(String patron, String ruta) =>
      _comoRegex(patron).hasMatch(ruta);

  static final _cache = <String, RegExp>{};

  static RegExp _comoRegex(String patron) =>
      _cache[patron] ??= RegExp('^${_traducir(patron)}\$', dotAll: true);

  static String _traducir(String patron) {
    final salida = StringBuffer();
    var i = 0;
    while (i < patron.length) {
      final c = patron[i];
      i++;
      switch (c) {
        case '*':
          salida.write('.*');
        case '?':
          salida.write('.');
        case '[':
          // Un conjunto sin cerrar es un corchete literal, igual que en `fnmatch`.
          final cierre = patron.indexOf(']', i);
          if (cierre < 0) {
            salida.write(r'\[');
            break;
          }
          var dentro = patron.substring(i, cierre);
          i = cierre + 1;
          dentro = dentro.replaceAll(r'\', r'\\');
          if (dentro.startsWith('!')) {
            dentro = '^${dentro.substring(1)}';
          }
          salida.write('[$dentro]');
        default:
          salida.write(RegExp.escape(c));
      }
    }
    return salida.toString();
  }
}
