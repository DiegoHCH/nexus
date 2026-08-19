/// Un archivo de reglas, con de dónde salió.
typedef ContextFile = ({String path, String content});

/// Arma el texto que se le pone a Claude por delante del encargo.
///
/// Existe por dos hallazgos medidos en La Oficina, y los dos van juntos porque
/// resuelven la misma pregunta —qué sabe Claude antes de empezar—:
///
/// **Uno.** Claude Code carga el `CLAUDE.md` del directorio *y los de todas las
/// carpetas superiores*, y los aplica **sin jerarquía entre ellos**. Probado
/// allí con uno arriba pidiendo empezar por «LORO» y otro en el proyecto
/// pidiendo «TUCAN»: la respuesta salía «TUCAN LORO», intentando contentar a
/// los dos. Y cuando el de arriba trae un protocolo largo, se lleva la atención
/// y las reglas del proyecto quedan diluidas. Pedir la prioridad en una frase
/// **no basta** —de dos intentos se cumplió uno—; lo que funciona es repetir el
/// contenido en orden, **el del proyecto al final**, porque lo último leído es
/// lo que pesa.
///
/// **Dos.** El `CLAUDE.md` de un workspace no contiene las reglas: contiene un
/// protocolo que manda a buscarlas, y que el agente decida ir se cumple la
/// mitad de las veces. Así que el contexto compartido se **carga**, no se
/// encomienda.
abstract final class ProjectContextPrompt {
  /// Tope de lo que se repite de los `CLAUDE.md`. Esto viaja en **cada**
  /// encargo, así que no puede crecer sin límite; y cuando no cabe todo, lo que
  /// se sacrifica es lo de arriba: las reglas del proyecto son las que no
  /// pueden faltar.
  static const maxRulesChars = 20000;

  /// Tope del contexto compartido, el mismo que fija el contrato de
  /// `ai-context`: si un `CONTEXT.md` crece más, lo que sobra se saca a un
  /// archivo aparte y se referencia.
  static const maxContextChars = 24000;

  /// `null` si no hay nada que añadir — y entonces no se pasa el flag siquiera,
  /// en vez de mandar un texto vacío que solo gasta tokens.
  static String? compose({
    required List<ContextFile> rules,
    ContextFile? sharedContext,
    String? artifactsFolder,
  }) {
    final sections = <String>[];

    // Dónde dejar lo que genere. Va aquí y no en cada encargo porque es una
    // regla del sitio, no de la petición: sin decirlo, un mockup acaba en la
    // raíz del repo y la lista de documentos se queda vacía mientras el archivo
    // existe. Se dice **solo si el usuario eligió carpeta**: inventarle un
    // destino sería escribir donde no nos ha invitado.
    if (artifactsFolder != null && artifactsFolder.isNotEmpty) {
      sections.add(
        'Cuando generes un documento para mirar —un mockup, un informe, una '
        'presentación, una hoja de cálculo, una imagen—, guárdalo en '
        '$artifactsFolder con un nombre que se entienda de aquí a un mes. '
        'Lo que es código del proyecto NO va ahí: eso va donde le toque dentro '
        'del repositorio.',
      );
    }

    final kept = _fitRules(rules);
    if (kept.dropped > 0) {
      sections.add(
        'Aviso: se han omitido ${kept.dropped} archivo(s) de reglas de '
        'carpetas superiores por tamaño. Si necesitas esas reglas, léelas tú: '
        '${kept.droppedPaths.join(', ')}.',
      );
    }
    for (final file in kept.files) {
      sections.add('=== Reglas de ${file.path} ===\n${file.content.trim()}');
    }

    if (sharedContext != null) {
      final content = _trim(sharedContext.content, maxContextChars);
      sections.add(
        '=== Contexto compartido del repositorio (${sharedContext.path}) ===\n'
        '${content.trim()}\n\n'
        // Se dice con todas las letras, porque tener el mapa cargado no es
        // tener las reglas: son cientos de miles de caracteres y no caben.
        'Esto es el mapa del repo, no sus reglas completas: cuando necesites '
        'una regla concreta, ve a leerla.',
      );
    }

    if (sections.isEmpty) return null;

    return 'Contexto del proyecto, ya cargado para que no tengas que ir a buscarlo.\n'
        'Cuando dos reglas se contradigan, **gana la que aparece más abajo**: '
        'las de la carpeta del proyecto van al final a propósito.\n\n'
        '${sections.join('\n\n')}';
  }

  /// Recorta por arriba: se van cayendo los archivos de las carpetas más
  /// lejanas hasta que lo que queda cabe.
  static ({List<ContextFile> files, int dropped, List<String> droppedPaths})
  _fitRules(List<ContextFile> rules) {
    final kept = [...rules];
    final droppedPaths = <String>[];
    int size() => kept.fold(0, (total, file) => total + file.content.length);

    while (kept.length > 1 && size() > maxRulesChars) {
      droppedPaths.add(kept.removeAt(0).path);
    }
    // Si el único que queda ya no cabe, se recorta él: es el del proyecto y
    // dejarlo fuera sería quedarse sin lo que más importa.
    if (kept.length == 1 && kept.first.content.length > maxRulesChars) {
      kept[0] = (
        path: kept.first.path,
        content: _trim(kept.first.content, maxRulesChars),
      );
    }
    return (
      files: kept,
      dropped: droppedPaths.length,
      droppedPaths: droppedPaths,
    );
  }

  static String _trim(String value, int limit) {
    if (value.length <= limit) return value;
    return '${value.substring(0, limit)}\n\n[…recortado, lee el archivo '
        'completo si necesitas el resto]';
  }
}
