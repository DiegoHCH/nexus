/// Reconoce cuándo lo que se escribió es «genérame esta imagen».
///
/// Va por **prefijo y no por lo que parezca la frase**, al revés que el parte:
/// allí se compara la frase entera contra una lista cerrada porque «daily» es
/// una palabra que aparece en encargos de verdad. Aquí no hace falta esa
/// prudencia —nadie escribe `/imagen` por accidente— y sí hace falta lo
/// contrario: que el texto de después sea libre, porque **es la descripción**.
///
/// 🔴 Y por eso el prefijo exige un espacio detrás. Sin él, `/imagenes` sería
/// una petición de imagen con la descripción «es», que es peor que no
/// reconocerlo: se gastaría dinero en generar cualquier cosa.
abstract final class LoQueSePideDibujar {
  static const prefijos = {'/imagen', '/img'};

  /// La descripción, o `null` si esto no era una petición de imagen.
  static String? deLaFrase(String frase) {
    final limpia = frase.trim();
    for (final prefijo in prefijos) {
      if (!limpia.toLowerCase().startsWith('$prefijo ')) continue;
      final descripcion = limpia.substring(prefijo.length).trim();
      if (descripcion.isNotEmpty) return descripcion;
    }
    return null;
  }

  /// Un nombre de archivo que se reconozca en la carpeta dentro de un mes.
  ///
  /// De la propia descripción, porque `imagen-4.png` no dice nada: lo que uno
  /// recuerda es lo que pidió. Con la fecha delante para que ordenen solos y
  /// para que pedir dos veces lo mismo no sobrescriba la primera.
  static String nombrePara(String descripcion, DateTime cuando) {
    final marca =
        '${cuando.year}${_dos(cuando.month)}${_dos(cuando.day)}'
        '-${_dos(cuando.hour)}${_dos(cuando.minute)}${_dos(cuando.second)}';
    final palabras = descripcion
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9áéíóúñü ]'), '')
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(5)
        .join('-');
    return palabras.isEmpty ? '$marca.png' : '$marca-$palabras.png';
  }

  static String _dos(int n) => n.toString().padLeft(2, '0');
}
