/// El nombre del modelo tal y como se lee: `claude-opus-4-8` → «Opus 4.8».
///
/// Se compone a partir del identificador en vez de traducirlo con una tabla, y
/// esa es la decisión: en el disco hay modelos que la app ya **no ofrece** —de
/// versiones anteriores del CLI— y siguen siendo parte de lo gastado. Con una
/// tabla, ese gasto aparecería con una etiqueta en blanco o, peor, con el
/// nombre del modelo equivocado.
String modelLabel(String raw) {
  final parts = raw
      .replaceFirst('claude-', '')
      .replaceAll(RegExp(r'\[.*\]'), '')
      .split('-');
  if (parts.isEmpty || parts.first.isEmpty) return raw;

  final name = parts.first;
  // Solo los tramos numéricos cortos son versión. El largo del final es la
  // fecha de publicación —`claude-haiku-4-5-20251001`— y colarla en el nombre
  // daba «Haiku 4.5.20251001», que fue justo lo que encontró la prueba.
  final version = parts
      .skip(1)
      .where((part) => part.length <= 2 && int.tryParse(part) != null)
      .join('.');

  final pretty = name[0].toUpperCase() + name.substring(1);
  return version.isEmpty ? pretty : '$pretty $version';
}
