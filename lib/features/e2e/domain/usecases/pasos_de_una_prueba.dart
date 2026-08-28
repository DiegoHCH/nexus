/// Cómo va una prueba paso a paso, mientras corre.
/// Cómo acabó un paso. `omitido` es su propio estado y no una variante de
/// `fallado`: un `runFlow` con `when:` que no aplica —la rama de iOS corriendo en
/// Android— sale `SKIPPED`, y **no tenerlo aquí teñía de Error una pasada con los
/// trece pasos completos**. Medido el 2026-08-27.
enum EstadoDePaso { hecho, enCurso, pendiente, fallado, omitido }

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

/// Un paso listo para pintar: qué dice, cómo va, y su detalle si lo tiene.
///
/// **Sirve para los dos orígenes**: los ejecutados vienen de la salida de Maestro
/// en prosa y sin detalle, los pendientes del YAML tal como están escritos. Una
/// sola forma porque quien los pinta no tiene por qué saber de dónde salió cada
/// uno.
class PasoParaPintar {
  const PasoParaPintar({
    required this.texto,
    required this.estado,
    this.detalle = const [],
    this.linea,
  });

  final String texto;
  final EstadoDePaso estado;
  final List<String> detalle;

  /// La línea del `.yaml`, **cuando se sabe**. Los pendientes vienen del archivo y
  /// la traen; los ejecutados vienen de la prosa de Maestro, que no dice de qué
  /// línea salió cada uno. `null` es eso: no se sabe, y no se inventa.
  final int? linea;
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
      if (m != null) {
        return m.group(1)!.trim().replaceAll(RegExp('^[\'"]|[\'"]\$'), '');
      }
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
        pasos.add(PasoDelFlow(linea: numero, texto: linea.substring(2).trim()));
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
  /// Se conserva para leer los **registros viejos**, que guardaban líneas y una
  /// cuenta. Lo que corre ahora sale de [deLaSalida], que además sabe cuál está en
  /// curso.
  ///
  /// Aquí decía que «una línea de estado solo aparece cuando el paso termina». Es
  /// falso, y se midió: Maestro anuncia el paso **al empezarlo** y le pega el
  /// resultado después, en la misma línea. Ver [deLaSalida].
  static ({int terminados, bool fallo}) avance(Iterable<String> lineas) {
    var terminados = 0;
    var fallo = false;
    for (final linea in lineas) {
      final t = linea.trim();
      if (t.endsWith('COMPLETED')) terminados++;
      // Un paso omitido terminó: no haberlo contado dejaba la barra corta para
      // siempre en cualquier flow con una rama por plataforma.
      if (t.endsWith('SKIPPED')) terminados++;
      if (t.endsWith('FAILED') || t.endsWith('ERROR')) {
        terminados++;
        fallo = true;
      }
    }
    return (terminados: terminados, fallo: fallo);
  }

  /// Los pasos que Maestro dice haber ejecutado, leídos de su salida.
  ///
  /// **La salida trae el plan real y en prosa**, que es más de lo que dice el
  /// archivo. Medido con marcas de tiempo, un `--no-ansi` escribe así:
  ///
  /// ```
  /// 29.76s  'Launch app "com.ejemplo"...'
  /// 44.94s  ' COMPLETED\nAssert that id: btn is visible...'
  /// 58.80s  ' COMPLETED\n'
  /// ```
  ///
  /// Dos cosas que decidieron este diseño:
  ///
  /// **El anuncio del paso llega sin salto de línea**, quince segundos antes de su
  /// resultado. Ahí está el paso en curso, con su nombre. Un lector que espere un
  /// `\n` se lo guarda en el buffer hasta que el paso acaba, y entonces no hay
  /// forma de enseñar cuál corre — que es exactamente lo que pasaba.
  ///
  /// **El resultado y el anuncio del siguiente vienen pegados** en el mismo trozo,
  /// así que no se puede procesar trozo a trozo: se acumula el texto entero y se
  /// vuelve a leer. Es idempotente, y con esto no hay estado incremental que
  /// desincronizar.
  ///
  /// Emparejar por texto con el YAML es imposible —«Assert that id: btn is
  /// visible» no se parece a `extendedWaitUntil:`— y por eso antes se emparejaba
  /// por posición y se degradaba a `null` cuando no cuadraba. Leyendo la salida no
  /// hay nada que emparejar: `runFlow` y los bucles emiten más líneas y se pintan
  /// más pasos.
  static List<PasoParaPintar> deLaSalida(String salida) {
    final pasos = <PasoParaPintar>[];

    for (final cruda in salida.split('\n')) {
      final linea = cruda.trim();
      if (linea.isEmpty || _noEsUnPaso(linea)) continue;

      final (texto, estado, detalle) = switch (linea) {
        _ when linea.endsWith('COMPLETED') => (
          _sinSufijo(linea, 'COMPLETED'),
          EstadoDePaso.hecho,
          const <String>[],
        ),
        _ when linea.endsWith('FAILED') => (
          _sinSufijo(linea, 'FAILED'),
          EstadoDePaso.fallado,
          const <String>[],
        ),
        _ when linea.endsWith('ERROR') => (
          _sinSufijo(linea, 'ERROR'),
          EstadoDePaso.fallado,
          const <String>[],
        ),
        // **`SKIPPED` no es un fallo.** Un `runFlow` con `when:` que no aplica
        // —la rama de iOS corriendo en Android— sale así. Sin este caso caía en
        // `_reventado` de más abajo, que asume que la línea trae una excepción
        // pegada, y la pasada entera se marcaba Error con todo completo.
        _ when linea.endsWith('SKIPPED') => (
          _sinSufijo(linea, 'SKIPPED'),
          EstadoDePaso.omitido,
          const <String>[],
        ),
        // Sin resultado todavía: es el anuncio, el paso que corre ahora.
        _ when linea.endsWith('...') => (
          _sinPuntos(linea),
          EstadoDePaso.enCurso,
          const <String>[],
        ),
        // **Un paso que revienta no recibe ninguna de las tres.** Maestro le pega
        // la excepción al anuncio, en la misma línea y sin salto:
        //
        // ```
        // Tap on id: btn...maestro.android.DeviceCallFailedException: 'tap' failed
        // ```
        //
        // Esto se descartaba por no acabar en `COMPLETED`, `FAILED` ni `...`, así
        // que **el paso que había fallado se quedaba sin marca** y los siguientes
        // se caían al texto del archivo. Se vio en un móvil real: la etiqueta decía
        // «Error» y la lista no señalaba dónde.
        //
        // Lo que va detrás de los puntos es el motivo, y se enseña con el paso: es
        // lo único que se busca cuando algo se rompe.
        _ when linea.contains('...') => _reventado(linea),
        _ => (null, EstadoDePaso.pendiente, const <String>[]),
      };
      if (texto == null || texto.isEmpty) continue;

      // **El cierre de un paso anunciado no es otro paso.** Un `runFlow` se imprime
      // en tres tramos: el anuncio, los pasos de dentro indentados, y **otra vez el
      // mismo `runFlow`** con su resultado:
      //
      // ```
      // Run flow when id: input.pin is visible...
      //   Tap on id: btn.pin_keypad_1... COMPLETED
      // Run flow when id: input.pin is visible... COMPLETED
      // ```
      //
      // Tomando cada línea como un paso, el anuncio se quedaba **girando para
      // siempre** —nunca recibe estado en su propia línea— y su cierre aparecía como
      // una fila más. Con dos flujos anidados se veían tres indicadores a la vez y la
      // ventana se leía como colgada teniendo la pasada acabada. Se vio así.
      //
      // Se busca solo entre los que están en curso, y por eso dos pasos idénticos
      // seguidos no se confunden: un paso que ya acabó no vuelve a casar.
      final anunciado = pasos.lastIndexWhere(
        (p) => p.estado == EstadoDePaso.enCurso && p.texto == texto,
      );
      if (anunciado >= 0 && estado != EstadoDePaso.enCurso) {
        pasos[anunciado] = PasoParaPintar(
          texto: texto,
          estado: estado,
          detalle: detalle,
        );
        continue;
      }

      pasos.add(PasoParaPintar(texto: texto, estado: estado, detalle: detalle));
    }
    return pasos;
  }

  /// Lo que Maestro escribe que no es un paso.
  ///
  /// Una lista y no una regla, porque los nombres de paso son abiertos —«Launch
  /// app», «Assert that», «Tap on», «Run flow»…— y no hay forma de reconocerlos por
  /// su forma. Ojo con `Waiting for flows to complete...`: **acaba en tres puntos
  /// igual que el anuncio de un paso**, así que sin esta lista se pintaría como uno.
  static bool _noEsUnPaso(String linea) =>
      linea.startsWith('Running on') ||
      linea.startsWith('>') ||
      linea.startsWith('Waiting for') ||
      linea.startsWith('[Passed]') ||
      linea.startsWith('[Failed]') ||
      RegExp(r'^\d+/\d+ Flow').hasMatch(linea);

  /// Un paso cortado por una excepción: el nombre, y el motivo como detalle.
  ///
  /// Se corta por el **primer** `...`. Un nombre de paso con tres puntos dentro
  /// saldría recortado, y eso es aceptable: se seguiría diciendo que ese paso
  /// falló y por qué, que es lo que hace falta. Callarse el fallo, no.
  static (String?, EstadoDePaso, List<String>) _reventado(String linea) {
    final corte = linea.indexOf('...');
    final texto = linea.substring(0, corte).trimRight();
    final motivo = linea.substring(corte + 3).trim();
    return (
      texto,
      EstadoDePaso.fallado,
      motivo.isEmpty ? const <String>[] : [motivo],
    );
  }

  static String _sinSufijo(String linea, String sufijo) =>
      _sinPuntos(linea.substring(0, linea.length - sufijo.length).trimRight());

  static String _sinPuntos(String linea) => linea.endsWith('...')
      ? linea.substring(0, linea.length - 3).trimRight()
      : linea;

  /// Lo que se pinta: lo que ya pasó, y lo que el archivo dice que falta.
  ///
  /// **Las dos fuentes, cada una para lo que sabe.** La salida sabe la verdad de lo
  /// ejecutado pero no el futuro; el archivo sabe lo que falta pero no lo que de
  /// verdad se ejecutó. Enseñar solo la salida quitaba la lista de lo que viene
  /// —que es la mitad de para qué se mira— y enseñar solo el archivo es lo que
  /// obligaba a mentir o a rendirse.
  ///
  /// Cuando lo ejecutado pasa de lo que dice el archivo —un `runFlow`, un bucle— no
  /// queda nada pendiente que añadir y la lista es toda de la salida. Sin caso
  /// especial y sin degradarse.
  static List<PasoParaPintar> paraPintar({
    required String salida,
    required List<PasoDelFlow> delFlow,
  }) {
    final corridos = deLaSalida(salida);
    return [
      ...corridos,
      for (var i = corridos.length; i < delFlow.length; i++)
        PasoParaPintar(
          texto: delFlow[i].texto,
          estado: EstadoDePaso.pendiente,
          detalle: delFlow[i].detalle,
          linea: delFlow[i].linea,
        ),
    ];
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
