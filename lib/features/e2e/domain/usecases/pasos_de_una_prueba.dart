/// Cómo va una prueba paso a paso, mientras corre.
enum EstadoDePaso { hecho, enCurso, pendiente, fallado }

abstract final class PasosDeUnaPrueba {
  /// Los pasos que declara un flow, leídos de su YAML.
  ///
  /// **Se cuentan las líneas de primer nivel que empiezan por `- ` después del
  /// `---`**, que es lo que Maestro ejecuta como pasos. Antes del separador va la
  /// cabecera —`appId`, `env`— y no es ejecutable.
  ///
  /// No se interpreta el YAML de verdad a propósito: lo único que hace falta es
  /// **cuántos y en qué orden**, y para eso las líneas bastan. Meter un analizador
  /// de YAML aquí sería traer una dependencia para contar guiones.
  static List<String> leer(String yaml) {
    final pasos = <String>[];
    var empezado = false;

    for (final cruda in yaml.split('\n')) {
      final linea = cruda.trimRight();
      if (!empezado) {
        if (linea.trim() == '---') empezado = true;
        continue;
      }
      // Los comentarios no son pasos, y los flows de este repo llevan muchos.
      if (linea.trimLeft().startsWith('#')) continue;
      // Primer nivel: el guion en la columna cero. Un `- ` indentado es un
      // argumento de un paso, no otro paso.
      if (linea.startsWith('- ')) pasos.add(linea.substring(2).trim());
    }
    return pasos;
  }

  /// Cuántos pasos ha terminado Maestro, contando líneas de su salida.
  ///
  /// **Una línea de estado solo aparece cuando el paso termina**, así que esto es
  /// la cuenta de los acabados. De ahí sale gratis cuál está en curso: el
  /// siguiente.
  ///
  /// La salida real, con `--no-ansi`:
  /// ```
  /// Running on Medium_Phone_API_36.1
  ///  > Flow welcome_to_login
  /// Launch app "com.ejemplo"... COMPLETED
  /// Assert that id: btn is visible... COMPLETED
  /// ```
  static ({int terminados, bool fallo}) avance(Iterable<String> lineas) {
    var terminados = 0;
    var fallo = false;
    for (final linea in lineas) {
      final t = linea.trim();
      if (t.endsWith('COMPLETED')) terminados++;
      if (t.endsWith('FAILED') || t.endsWith('ERROR')) {
        terminados++;
        fallo = true;
      }
    }
    return (terminados: terminados, fallo: fallo);
  }

  /// El estado de cada paso, emparejando **por posición**.
  ///
  /// La línea que imprime Maestro es una redacción humana del comando —«Assert
  /// that id: btn is visible»— y no el YAML, así que emparejar por texto es
  /// imposible. Lo que sí garantiza es el orden.
  ///
  /// Cuando los pasos impresos **superan** los del archivo, la lista deja de
  /// significar nada: eso pasa con `runFlow` y con los bucles, donde lo ejecutado
  /// no son las líneas del archivo. Ahí se devuelve `null` y quien pinta enseña la
  /// salida en plano — degradarse y no mentir.
  static List<EstadoDePaso>? estados({
    required int cuantosPasos,
    required int terminados,
    required bool viva,
    required bool fallo,
  }) {
    if (terminados > cuantosPasos) return null;

    return [
      for (var i = 0; i < cuantosPasos; i++)
        if (i < terminados - (fallo ? 1 : 0))
          EstadoDePaso.hecho
        else if (fallo && i == terminados - 1)
          EstadoDePaso.fallado
        else if (i == terminados && viva)
          EstadoDePaso.enCurso
        else
          EstadoDePaso.pendiente,
    ];
  }
}
