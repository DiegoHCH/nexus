/// Las credenciales de un proyecto, para pasárselas a una prueba.
///
/// **Existe porque Maestro solo las acepta por `-e`.** Se midió: con la variable
/// puesta en el entorno del proceso, un `assertTrue: ${SECRETO == "zanahoria"}`
/// **falla**; con `-e SECRETO=zanahoria` pasa. No hay una vía por entorno, así que
/// los valores acaban en el `argv` del proceso y son visibles con `ps`.
///
/// Eso se asume, con dos matices y una consecuencia:
///
/// - **No ensancha el círculo de confianza.** Quien puede leer el `argv` de tus
///   procesos puede leer también el archivo de donde salen. Lo que sí hace es
///   dejarlos en sitios que nadie mira —listados de procesos, informes de fallo—
///   y por eso se pasan **solo las claves que el flow usa** y no el archivo entero.
/// - **No se filtran por la salida.** Medido: Maestro imprime `Input text
///   ${SECRETO}... COMPLETED`, el marcador y no el valor. Importa porque el
///   registro de una corrida guarda la salida entera en disco.
///
/// Y la consecuencia: **un valor no se escribe nunca en ningún sitio nuestro.** Ni
/// en un mensaje de error, ni en el registro, ni en la página. Los nombres de las
/// claves sí, que es lo que hace falta para decir qué falta.
abstract final class LasVariablesDelProyecto {
  /// Cómo se llama el archivo. En la raíz del proyecto, y fuera de git.
  static const archivo = '.env.local';

  /// Lee un `.env` sencillo: `CLAVE=valor`, una por línea.
  ///
  /// **Sin interpolación, sin `export`, sin comillas anidadas.** Un `.env` de
  /// verdad tiene una gramática entera y aquí no hace falta: esto son credenciales
  /// para una prueba, no un intérprete. Lo que no se entiende se ignora en vez de
  /// adivinarse.
  static Map<String, String> leer(String contenido) {
    final variables = <String, String>{};

    for (final cruda in contenido.split('\n')) {
      final linea = cruda.trim();
      if (linea.isEmpty || linea.startsWith('#')) continue;

      final corte = linea.indexOf('=');
      if (corte <= 0) continue;

      final clave = linea.substring(0, corte).trim();
      if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(clave)) continue;

      var valor = linea.substring(corte + 1).trim();
      // Las comillas envolventes se quitan; una comilla suelta se deja, que es
      // parte del valor.
      if (valor.length >= 2 &&
          ((valor.startsWith('"') && valor.endsWith('"')) ||
              (valor.startsWith("'") && valor.endsWith("'")))) {
        valor = valor.substring(1, valor.length - 1);
      }
      variables[clave] = valor;
    }
    return variables;
  }

  /// Las variables que el flow nombra, en su forma simple: `${CLAVE}`.
  ///
  /// Solo la forma simple a propósito. Maestro admite expresiones enteras
  /// —`${SECRETO == "zanahoria"}`— y sacar de ahí qué es un nombre y qué una
  /// cadena pide un analizador. Para lo que sirve esto —avisar de una variable que
  /// falta— vale con lo inequívoco: de una expresión no se avisa, porque no se
  /// sabe.
  static Set<String> queNombra(String yaml) => {
    for (final m in RegExp(r'\$\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*\}').allMatches(yaml))
      m.group(1)!,
  };

  /// Las que hay que pasarle a esta prueba: **solo las que aparecen en su texto**.
  ///
  /// Pasar el archivo entero metería en el `argv` credenciales que esta prueba no
  /// usa. Se busca la clave en el texto crudo y no solo como `${CLAVE}`, para que
  /// una expresión también las reciba.
  static Map<String, String> paraElFlow({
    required String yaml,
    required Map<String, String> variables,
  }) => {
    for (final entrada in variables.entries)
      if (yaml.contains(entrada.key)) entrada.key: entrada.value,
  };

  /// Las que el flow nombra y no están, para poder decirlo antes de correr.
  ///
  /// Sin esto, una variable que falta se convierte en un fallo desconcertante
  /// dentro de Maestro: escribe el literal `${G66_EMAIL}` en el campo del correo y
  /// la prueba muere tres pasos después, en un sitio que no tiene nada que ver.
  ///
  /// Las de Maestro no cuentan: `MAESTRO_*` y `output` las pone él.
  /// Recibe **solo los nombres** de lo que hay, no los valores: quien avisa no
  /// tiene por qué tocar una credencial.
  static List<String> faltan({
    required String yaml,
    required Set<String> tiene,
  }) =>
      [
        for (final clave in queNombra(yaml))
          if (!tiene.contains(clave) &&
              !clave.startsWith('MAESTRO_') &&
              clave != 'output')
            clave,
      ]..sort();
}
