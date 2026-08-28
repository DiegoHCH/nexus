/// Todo el YAML que participa en una pasada: el flow y lo que arrastra con
/// `runFlow`.
///
/// 🔴 **Existe por un fallo medido, no por completitud.** Las credenciales se le
/// pasan a Maestro filtradas por lo que el flow nombra —`LasVariablesDelProyecto
/// .paraElFlow`— y ese filtro miraba **solo el archivo del flow**. En
/// `global66/automated-test` la cadena real de `04-account-detail-flow.yaml` es:
///
/// ```
/// 04-account-detail-flow.yaml   → nombra APP_ID
///   └─ commons/setup-authed.yaml
///        └─ ../auth/00-login.yaml   → nombra EMAIL y PASSWORD
/// ```
///
/// Con el filtro mirando solo el primero, a Maestro le llegaba `APP_ID` y nada
/// más: el login tecleaba el literal `${EMAIL}` y la prueba moría tres pasos
/// después, en un sitio que no tiene nada que ver. Es el fallo desconcertante
/// contra el que ya avisa `faltan()`, entrando por la puerta de al lado.
///
/// **No es un problema del repo remoto**: cualquier flow con subflows lo tenía.
abstract final class ElArbolDeUnFlow {
  /// Cuántos niveles se siguen. Un flow que se incluye a sí mismo por dos caminos
  /// distintos ya está cubierto por los visitados; esto es el cinturón para una
  /// cadena absurdamente honda, que costaría memoria sin aportar nada.
  static const _fondo = 12;

  /// El texto del flow y el de todo lo que incluye, concatenado.
  ///
  /// [leer] recibe una ruta absoluta y devuelve el contenido, o `null` si no está.
  /// **Un archivo que falta se salta en silencio**: puede ser una ruta con una
  /// variable dentro, y romper el lanzamiento por no poder leer un subflow sería
  /// peor que pasar una credencial de más.
  static String texto({
    required String ruta,
    required String? Function(String ruta) leer,
  }) {
    final visto = <String>{};
    final trozos = <String>[];
    _juntar(
      ruta: ruta,
      leer: leer,
      visto: visto,
      trozos: trozos,
      queda: _fondo,
    );
    return trozos.join('\n');
  }

  /// Igual que [texto], pero leyendo sin bloquear.
  ///
  /// 🔴 **Para la lista del repo, que resuelve 57 árboles de golpe.** Medido: son
  /// 300 lecturas de archivo al desplegarla. En su versión síncrona todas caen en
  /// el hilo de la interfaz y en el mismo fotograma; aquí no. La síncrona se
  /// queda para lanzar una prueba, que es un árbol y una vez.
  static Future<String> textoAsync({
    required String ruta,
    required Future<String?> Function(String ruta) leer,
  }) async {
    final visto = <String>{};
    final trozos = <String>[];
    await _juntarAsync(
      ruta: ruta,
      leer: leer,
      visto: visto,
      trozos: trozos,
      queda: _fondo,
    );
    return trozos.join('\n');
  }

  static Future<void> _juntarAsync({
    required String ruta,
    required Future<String?> Function(String ruta) leer,
    required Set<String> visto,
    required List<String> trozos,
    required int queda,
  }) async {
    if (queda <= 0 || !visto.add(ruta)) return;
    final contenido = await leer(ruta);
    if (contenido == null) return;
    trozos.add(contenido);

    final carpeta = _carpetaDe(ruta);
    for (final referida in referencias(contenido)) {
      await _juntarAsync(
        ruta: _resolver(carpeta, referida),
        leer: leer,
        visto: visto,
        trozos: trozos,
        queda: queda - 1,
      );
    }
  }

  static void _juntar({
    required String ruta,
    required String? Function(String ruta) leer,
    required Set<String> visto,
    required List<String> trozos,
    required int queda,
  }) {
    if (queda <= 0 || !visto.add(ruta)) return;
    final contenido = leer(ruta);
    if (contenido == null) return;
    trozos.add(contenido);

    final carpeta = _carpetaDe(ruta);
    for (final referida in referencias(contenido)) {
      _juntar(
        ruta: _resolver(carpeta, referida),
        leer: leer,
        visto: visto,
        trozos: trozos,
        queda: queda - 1,
      );
    }
  }

  /// Las rutas que un flow incluye con `runFlow`, tal cual las escribe.
  ///
  /// Dos formas, y una que **no** cuenta:
  ///
  /// - `- runFlow: commons/setup-authed.yaml` — la corriente.
  /// - `runFlow:` con `file: x.yaml` debajo — la que lleva `env:`.
  /// - `runFlow:` con `commands:` debajo son pasos escritos ahí mismo: no hay
  ///   archivo que leer y tratarlo como ruta produciría una lectura fantasma.
  static List<String> referencias(String contenido) {
    final rutas = <String>[];
    for (final cruda in contenido.split('\n')) {
      final linea = cruda.trim();
      if (linea.startsWith('#')) continue;

      final directa = RegExp(r'^-?\s*runFlow:\s*(.+)$').firstMatch(linea);
      if (directa != null) {
        final valor = _limpio(directa.group(1)!);
        if (_pareceArchivo(valor)) rutas.add(valor);
        continue;
      }
      // La forma con bloque: `file:` es hijo de un `runFlow:` de más arriba. No se
      // comprueba el padre a propósito — un `file:` suelto en un flow de Maestro
      // no significa otra cosa, y rastrear la indentación para confirmarlo sería
      // un parser de YAML entero por un caso que no existe.
      final conFile = RegExp(r'^file:\s*(.+)$').firstMatch(linea);
      if (conFile != null) {
        final valor = _limpio(conFile.group(1)!);
        if (_pareceArchivo(valor)) rutas.add(valor);
      }
    }
    return rutas;
  }

  static bool _pareceArchivo(String valor) =>
      valor.isNotEmpty &&
      (valor.endsWith('.yaml') || valor.endsWith('.yml')) &&
      // Una ruta con una variable dentro no se puede resolver ahora: la decide
      // Maestro al correr.
      !valor.contains(r'$');

  static String _limpio(String crudo) {
    var valor = crudo.trim();
    final comentario = valor.indexOf(' #');
    if (comentario > 0) valor = valor.substring(0, comentario).trim();
    // La forma en línea `{file: x.yaml, env: {...}}` deja llaves alrededor.
    valor = valor.replaceAll(RegExp(r'^\{|\}$'), '').trim();
    final enLinea = RegExp(r'file:\s*([^,}]+)').firstMatch(valor);
    if (enLinea != null) valor = enLinea.group(1)!.trim();
    if (valor.length >= 2) {
      final a = valor[0], b = valor[valor.length - 1];
      if ((a == '"' && b == '"') || (a == "'" && b == "'")) {
        valor = valor.substring(1, valor.length - 1);
      }
    }
    return valor.trim();
  }

  static String _carpetaDe(String ruta) {
    final corte = ruta.lastIndexOf('/');
    if (corte < 0) return '';
    // Un archivo en la raíz tiene carpeta `/`, no cadena vacía: devolver vacío
    // hacía que su hermano se resolviera como relativo y no se encontrara.
    return corte == 0 ? '/' : ruta.substring(0, corte);
  }

  /// Resuelve una ruta relativa contra la carpeta del flow que la incluye,
  /// colapsando los `..`. Es lo que hace Maestro, y por eso `../auth/00-login.yaml`
  /// desde `flows/commons/` es `flows/auth/00-login.yaml`.
  static String _resolver(String carpeta, String relativa) {
    if (relativa.startsWith('/')) return relativa;

    final partes = <String>[...carpeta.split('/'), ...relativa.split('/')];
    final pila = <String>[];
    for (final parte in partes) {
      if (parte.isEmpty || parte == '.') continue;
      if (parte == '..') {
        if (pila.isNotEmpty) pila.removeLast();
        continue;
      }
      pila.add(parte);
    }
    return '${carpeta.startsWith('/') ? '/' : ''}${pila.join('/')}';
  }
}
