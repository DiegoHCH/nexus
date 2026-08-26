/// Cómo va una prueba paso a paso, mientras corre.
enum EstadoDePaso { hecho, enCurso, pendiente, fallado }

/// Un paso tal como está escrito en el flow.
///
/// Con **su número de línea**, que es lo que permite señalar el paso en el
/// archivo en vez de decir «el tercero»: cuando algo falla, lo que se busca es la
/// línea.
class PasoDelFlow {
  PasoDelFlow({required this.linea, required this.texto, List<String>? detalle})
    : detalle = detalle ?? <String>[];

  /// La línea del `.yaml`, empezando en 1.
  final int linea;

  /// La primera línea del paso, sin el guion: `tapOn: Add`.
  final String texto;

  /// Lo indentado que viene debajo, con su sangría. Un `tapOn:` sin esto no dice
  /// nada.
  final List<String> detalle;
}

abstract final class PasosDeUnaPrueba {
  /// Qué app declara el flow, de su cabecera.
  ///
  /// **Hace falta para poder avisar antes de correr.** Maestro no instala nada: si
  /// la app no está en el dispositivo, falla en el primer `launchApp` con
  /// «Package … is not installed» **y sale con código 0**, así que ni el código de
  /// salida lo delata. Comprobado contra el binario.
  ///
  /// Va antes del `---`, como el resto de la cabecera.
  static String? appIdDe(String yaml) {
    for (final linea in yaml.split('\n')) {
      if (linea.trim() == '---') return null;
      final m = RegExp(r'^appId:\s*(.+)$').firstMatch(linea.trim());
      if (m != null) return m.group(1)!.trim().replaceAll(RegExp('^[\'"]|[\'"]\$'), '');
    }
    return null;
  }

  /// Los pasos que declara un flow, leídos de su YAML.
  ///
  /// **Se cuentan las líneas de primer nivel que empiezan por `- ` después del
  /// `---`**, que es lo que Maestro ejecuta como pasos. Antes del separador va la
  /// cabecera —`appId`, `env`— y no es ejecutable.
  ///
  /// No se interpreta el YAML de verdad a propósito: lo único que hace falta es
  /// **cuántos, en qué orden y qué dicen**, y para eso las líneas bastan. Meter un
  /// analizador de YAML aquí sería traer una dependencia para contar guiones.
  ///
  /// **Cada paso se lleva sus líneas de continuación**, y eso no es un adorno: un
  /// `tapOn:` a secas no dice nada —el `id:` que viene debajo es todo el
  /// contenido—. Sin ellas la lista se leía como una columna de verbos sueltos.
  static List<PasoDelFlow> leer(String yaml) {
    final pasos = <PasoDelFlow>[];
    var empezado = false;
    var numero = 0;

    for (final cruda in yaml.split('\n')) {
      numero++;
      final linea = cruda.trimRight();
      if (!empezado) {
        if (linea.trim() == '---') empezado = true;
        continue;
      }
      if (linea.trimLeft().startsWith('#')) continue;

      // Primer nivel: el guion en la columna cero. Un `- ` indentado es un
      // argumento de un paso, no otro paso.
      if (linea.startsWith('- ')) {
        pasos.add(
          PasoDelFlow(linea: numero, texto: linea.substring(2).trim()),
        );
        continue;
      }
      // Lo indentado pertenece al paso de arriba. Se guarda tal cual —con su
      // sangría— porque así se lee igual que en el archivo.
      if (linea.isNotEmpty && pasos.isNotEmpty && linea.startsWith(' ')) {
        pasos.last.detalle.add(linea.trimRight());
      }
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
