/// Traduce lo que el usuario escribe a lo que el CLI entiende por denegar.
///
/// Existe porque las dos formas no se parecen: uno escribe `build_runner` y el
/// CLI espera `Bash(*build_runner*)`. Pedirle al usuario que aprenda esa
/// sintaxis para prohibir un comando sería cobrarle un peaje por protegerse.
abstract final class BlockedCommands {
  /// Los patrones para `--disallowedTools`.
  ///
  /// El comodín va **a los dos lados** —comprobado contra el binario— porque el
  /// comando real casi nunca empieza por el fragmento que uno recuerda:
  /// `dart run build_runner build` se bloquea escribiendo `build_runner`.
  static List<String> patterns(List<String> entries) => [
    for (final raw in entries)
      if (_clean(raw) case final entry? when entry.isNotEmpty)
        // Una herramienta entera —`WebFetch`, un `mcp__…`— se pasa tal cual:
        // ahí lo que sobra es el conector, no un comando.
        if (entry.contains('(') || !entry.contains(' ') && _isTool(entry))
          entry
        else
          'Bash(*$entry*)',
  ];

  /// Lo que se le dice a Claude para que no se quede callado al chocar.
  ///
  /// Bloquear a secas hace que tropiece a media tarea y se calle; sabiéndolo de
  /// antemano, hace todo lo demás y **termina diciendo el comando exacto** que
  /// tienes que lanzar tú.
  static String? notice(List<String> entries) {
    final limpio = [
      for (final raw in entries)
        if (_clean(raw) case final entry? when entry.isNotEmpty) entry,
    ];
    if (limpio.isEmpty) return null;
    return 'No puedes ejecutar estos comandos en esta carpeta, porque tardan '
        'minutos y aquí hay alguien esperando: ${limpio.join(', ')}. '
        'No intentes rodearlos ni buscar equivalentes. Haz todo lo demás y '
        'termina diciendo, en una línea, el comando exacto que tiene que '
        'lanzar el usuario.';
  }

  /// Se admiten comentarios con `#` para poder dejar escrito por qué se
  /// bloqueó algo, que es lo que uno no recuerda tres meses después.
  static String? _clean(String raw) {
    final withoutComment = raw.split('#').first.trim();
    return withoutComment.isEmpty ? null : withoutComment;
  }

  static bool _isTool(String entry) =>
      entry.startsWith('mcp__') ||
      const {'WebFetch', 'WebSearch', 'Task', 'Agent'}.contains(entry);
}
