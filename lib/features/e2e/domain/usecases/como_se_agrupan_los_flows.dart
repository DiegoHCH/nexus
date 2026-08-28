/// De qué clase es un grupo de la lista. El título lo pone la interfaz: aquí solo
/// se decide qué va con qué.
enum ClaseDeGrupo {
  /// Las que se lanzan. Van primero porque son a lo que viene todo el mundo.
  pruebas,

  /// Una subcarpeta con nombre propio, como `migration/android-prod`.
  carpeta,

  /// Las que otros flows incluyen con `runFlow`. **No se lanzan sueltas**, y
  /// mezclarlas con las demás es la mitad del ruido de la lista.
  piezas,
}

class GrupoDeFlows {
  const GrupoDeFlows({
    required this.clase,
    required this.carpeta,
    required this.rutas,
    required this.total,
  });

  final ClaseDeGrupo clase;

  /// Para [ClaseDeGrupo.carpeta], su nombre. Vacío en las otras.
  final String carpeta;

  /// Las que pasan el filtro, en orden.
  final List<String> rutas;

  /// Cuántas hay en total, filtre o no. Es lo que permite decir «2 de 38» en vez
  /// de «2», que no dice si el filtro se comió algo.
  final int total;
}

/// Cómo se reparte la lista de flows del repo.
///
/// **Existe porque una tira plana deja de servir.** Medido sobre
/// `global66/automated-test`: 57 flows, y el repo va a crecer. De esos, 38 son los
/// que se lanzan, 12 son de `migration/` —otro asunto— y 7 no son pruebas sino
/// piezas que otros incluyen. Tres cosas distintas en una sola lista.
///
/// 🔴 **Las piezas se detectan por uso y no por carpeta.** Podría bastar con
/// «lo que está en `commons/` o `auth/`», y sería una regla que se rompe el día
/// que alguien crea otra carpeta de bloques. Que un flow lo incluya otro es el
/// hecho; la carpeta es solo dónde acabó.
abstract final class ComoSeAgrupanLosFlows {
  /// La raíz de los flows dentro del repo, que no es un grupo sino el prefijo de
  /// todos.
  static const _raiz = 'flows/';

  static List<GrupoDeFlows> repartir({
    required List<String> rutas,
    required Set<String> piezas,
    String filtro = '',
  }) {
    final buscado = filtro.trim().toLowerCase();
    bool pasa(String r) => buscado.isEmpty || r.toLowerCase().contains(buscado);

    final pruebas = <String>[], pruebasTodas = <String>[];
    final porCarpeta = <String, List<String>>{};
    final porCarpetaTodas = <String, List<String>>{};
    final delAsunto = <String>[], delAsuntoTodas = <String>[];

    for (final ruta in rutas) {
      if (piezas.contains(ruta)) {
        delAsuntoTodas.add(ruta);
        if (pasa(ruta)) delAsunto.add(ruta);
        continue;
      }
      final carpeta = _carpetaDe(ruta);
      if (carpeta.isEmpty) {
        pruebasTodas.add(ruta);
        if (pasa(ruta)) pruebas.add(ruta);
        continue;
      }
      (porCarpetaTodas[carpeta] ??= []).add(ruta);
      if (pasa(ruta)) (porCarpeta[carpeta] ??= []).add(ruta);
    }

    return [
      GrupoDeFlows(
        clase: ClaseDeGrupo.pruebas,
        carpeta: '',
        rutas: pruebas,
        total: pruebasTodas.length,
      ),
      // Las carpetas en orden alfabético: no hay una jerarquía real entre
      // `migration/android-prod` y `migration/ios-prod`, así que se ordenan por
      // lo único que no es una opinión.
      for (final nombre in porCarpetaTodas.keys.toList()..sort())
        GrupoDeFlows(
          clase: ClaseDeGrupo.carpeta,
          carpeta: nombre,
          rutas: porCarpeta[nombre] ?? const [],
          total: porCarpetaTodas[nombre]!.length,
        ),
      // Las piezas al final, siempre: son lo que menos se busca.
      GrupoDeFlows(
        clase: ClaseDeGrupo.piezas,
        carpeta: '',
        rutas: delAsunto,
        total: delAsuntoTodas.length,
      ),
    ].where((g) => g.total > 0).toList();
  }

  /// La subcarpeta de un flow dentro de `flows/`, o vacío si cuelga de la raíz.
  static String _carpetaDe(String ruta) {
    final sin = ruta.startsWith(_raiz) ? ruta.substring(_raiz.length) : ruta;
    final corte = sin.lastIndexOf('/');
    return corte < 0 ? '' : sin.substring(0, corte);
  }

  /// Las rutas que **otros** flows incluyen con `runFlow`, ya resueltas contra la
  /// raíz del repo. Es lo que separa una pieza de una prueba.
  static Set<String> piezasDe({
    required Map<String, List<String>> referenciasPorFlow,
  }) {
    final piezas = <String>{};
    for (final entrada in referenciasPorFlow.entries) {
      final carpeta = _carpetaDeRuta(entrada.key);
      for (final referida in entrada.value) {
        final resuelta = _resolver(carpeta, referida);
        // Un flow que se incluye a sí mismo no se convierte en pieza por eso.
        if (resuelta != entrada.key) piezas.add(resuelta);
      }
    }
    return piezas;
  }

  static String _carpetaDeRuta(String ruta) {
    final corte = ruta.lastIndexOf('/');
    return corte < 0 ? '' : ruta.substring(0, corte);
  }

  static String _resolver(String carpeta, String relativa) {
    final pila = <String>[];
    for (final parte in [...carpeta.split('/'), ...relativa.split('/')]) {
      if (parte.isEmpty || parte == '.') continue;
      if (parte == '..') {
        if (pila.isNotEmpty) pila.removeLast();
        continue;
      }
      pila.add(parte);
    }
    return pila.join('/');
  }
}
