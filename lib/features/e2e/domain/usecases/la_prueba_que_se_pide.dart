/// Qué prueba quiso decir alguien que habló.
///
/// Nace de comprobar la cuña de la demo contra el código: hablar el suite
/// funcionaba, pero por un camino de tres eslabones —el modelo elige la
/// herramienta de Claude, Claude elige la del MCP de Maestro, el MCP tiene que
/// estar vivo— y cualquiera de los tres puede romperse delante de público. Esto
/// es el primer trozo del camino corto: **de la voz al lanzador de Nexus, sin
/// intermediarios**.
///
/// La parte difícil no es lanzar, es entender. Un flow se llama `login.yaml` y
/// nadie dice «login punto yaml»: dice «corre el login», «lanza la prueba de
/// login» o «el flow del login». Y cuando lo que dijo vale para tres flows, la
/// respuesta correcta **no es elegir uno**: es preguntar. Adivinar mal aquí no
/// da un error, da una prueba distinta corriendo delante de todos.
library;

/// Lo que se decidió con lo que se oyó.
sealed class QuePruebaEs {
  const QuePruebaEs();
}

/// Se sabe cuál. Es la única respuesta que lanza algo.
final class LaPruebaEs extends QuePruebaEs {
  const LaPruebaEs(this.flow);

  final String flow;
}

/// Encaja en varias, así que se pregunta en vez de elegir.
final class VariasSeParecen extends QuePruebaEs {
  const VariasSeParecen(this.flows);

  final List<String> flows;
}

/// No encaja en ninguna. Lleva las que hay para poder decirlas.
final class NingunaSeParece extends QuePruebaEs {
  const NingunaSeParece(this.hay);

  final List<String> hay;
}

abstract final class LaPruebaQueSePide {
  /// Palabras que se dicen alrededor del nombre y que no son el nombre.
  ///
  /// Se quitan de los dos lados —de lo que se pidió y del nombre del flow—
  /// porque también hay flows que se llaman `test_login` o `prueba-checkout`, y
  /// entonces «corre el login» tiene que encontrarlos igual.
  static const _relleno = {
    'corre',
    'correr',
    'lanza',
    'lanzar',
    'ejecuta',
    'ejecutar',
    'la',
    'el',
    'los',
    'las',
    'de',
    'del',
    'prueba',
    'pruebas',
    'flow',
    'flows',
    'test',
    'tests',
    'suite',
    'yaml',
    'run',
  };

  /// Lo que queda de una frase cuando se le quita la forma de decirla.
  ///
  /// Sin tildes porque el reconocimiento de voz las pone y los nombres de
  /// archivo no las llevan, y separando por lo que separa un nombre de archivo
  /// —guiones, guiones bajos, puntos— para que `login_ok` y «login ok» sean lo
  /// mismo.
  static String nucleo(String texto) {
    const con = 'áàäâãéèëêíìïîóòöôõúùüûñç';
    const sin = 'aaaaaeeeeiiiiooooouuuunc';

    final limpio = StringBuffer();
    for (final letra in texto.toLowerCase().split('')) {
      final i = con.indexOf(letra);
      limpio.write(i == -1 ? letra : sin[i]);
    }

    final palabras = limpio
        .toString()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .split(' ')
        .where((p) => p.isNotEmpty && !_relleno.contains(p));

    return palabras.join(' ');
  }

  /// Cuál de [disponibles] se pidió.
  ///
  /// Tres vueltas, y el orden es la regla: primero lo idéntico, luego lo que
  /// contiene, y solo si eso deja una sola candidata se lanza. Empezar por
  /// «contiene» haría que pedir `login` con un `login` y un `login-fallido`
  /// delante eligiera uno de los dos por orden alfabético, que es adivinar.
  static QuePruebaEs cual(String pedido, List<String> disponibles) {
    final busca = nucleo(pedido);
    if (busca.isEmpty || disponibles.isEmpty) {
      return NingunaSeParece(disponibles);
    }

    final exactas = [
      for (final flow in disponibles)
        if (nucleo(flow) == busca) flow,
    ];
    if (exactas.length == 1) return LaPruebaEs(exactas.single);
    if (exactas.length > 1) return VariasSeParecen(exactas);

    final parecidas = [
      for (final flow in disponibles)
        if (nucleo(flow).contains(busca) || busca.contains(nucleo(flow))) flow,
    ];
    return switch (parecidas.length) {
      0 => NingunaSeParece(disponibles),
      1 => LaPruebaEs(parecidas.single),
      _ => VariasSeParecen(parecidas),
    };
  }
}
