/// De dónde se saca una skill y cómo se llama.
abstract final class SkillSource {
  /// El repositorio oficial. No se guarda su contenido en una lista escrita a
  /// mano **a propósito**: La Oficina mantiene once entradas y el repo tiene
  /// hoy dieciocho, así que su catálogo ya se quedó atrás — y las
  /// descripciones, copiadas, envejecen igual. Se escanea y se enseña lo que
  /// hay, con la descripción que escribió su autor.
  static const officialRepo = 'anthropics/skills';

  /// `usuario/repo`, venga como venga: pegado del navegador, con `.git`, con
  /// barra al final. Pegar la URL de la barra de direcciones es lo que uno hace
  /// de verdad, y rechazarla por no ser «usuario/repo» sería pedantería.
  static String? normalizeRepo(String raw) {
    final match = RegExp(
      r'^(?:https?://)?(?:www\.)?(?:github\.com/)?([\w.-]+/[\w.-]+?)(?:\.git)?/?$',
    ).firstMatch(raw.trim());
    return match?.group(1);
  }

  /// El identificador de una skill es el nombre de su carpeta, así que tiene
  /// que valer como nombre de carpeta y nada más: esto se usa para construir
  /// rutas y para borrar recursivamente.
  static bool validId(String id) =>
      RegExp(r'^[a-z0-9][a-z0-9-]{0,63}$').hasMatch(id);

  /// Lo escrito por una persona → un identificador. «Revisar Stocks» →
  /// `revisar-stocks`.
  static String? idFrom(String name) {
    final id = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_]+'), '-')
        .replaceAll(RegExp(r'[^a-z0-9-]'), '')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return validId(id) ? id : null;
  }

  /// La descripción del frontmatter, sin parser de YAML.
  ///
  /// Solo hace falta un campo, así que meter una dependencia de YAML entera
  /// sería pagar mucho por poco — pero hay que cubrir **dos** formas, no una:
  /// de las dieciocho del repo oficial, `claude-api` describe con un bloque
  /// (`description: |-` y el texto indentado debajo). Con solo la forma de una
  /// línea, su descripción salía literalmente como «|-».
  static String descriptionOf(String skillMd) {
    final match = RegExp(
      r'^description:[ \t]*(.*)$',
      multiLine: true,
    ).firstMatch(skillMd);
    if (match == null) return '';

    final head = match.group(1)!.trim();
    if (!RegExp(r'^[|>][-+]?$').hasMatch(head)) return _unquote(head);

    // Un bloque: las líneas indentadas que siguen, hasta la primera que no lo
    // esté. Se juntan en una sola porque esto se enseña en dos líneas de una
    // fila, no como documento.
    final block = <String>[];
    for (final line in skillMd.substring(match.end).split('\n')) {
      if (line.trim().isEmpty) continue;
      if (!line.startsWith(' ') && !line.startsWith('\t')) break;
      block.add(line.trim());
    }
    return block.join(' ');
  }

  static String _unquote(String value) =>
      value.replaceAll(RegExp("^[\"']|[\"']\$"), '');

  /// El esqueleto de una skill propia.
  ///
  /// La descripción lleva ese texto tan explícito porque es el error de bulto
  /// al escribir la primera: se describe **qué hace** y el agente nunca la
  /// activa, porque lo que lee para decidir es **cuándo** usarla.
  static String skeleton(String id, String description) =>
      '---\n'
      'name: $id\n'
      'description: ${description.trim().isEmpty ? 'Describe aquí CUÁNDO debe usarse esta skill — es lo único que el agente lee para decidir si la activa' : description.trim()}\n'
      '---\n'
      '\n'
      '# $id\n'
      '\n'
      'Instrucciones para el agente cuando esta skill se active. Escríbelas\n'
      'para quien no tenga contexto: pasos, no intenciones.\n'
      '\n'
      '1. …\n'
      '2. …\n'
      '\n'
      '<!-- Puedes añadir más archivos a esta carpeta —plantillas, ejemplos,\n'
      '     scripts— y referenciarlos desde aquí. -->\n';
}
