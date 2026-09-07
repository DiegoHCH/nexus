/// Qué se lee debajo del orbe mientras la puerta saluda.
///
/// 🔴 **El saludo se pinta antes de sonar, y eso hay que mantenerlo:** la sesión
/// tarda entre medio segundo y siete en estar lista, y una pantalla muda en el
/// arranque se lee como una app que no arrancó. El problema era el relevo: al
/// llegar el primer trozo de la transcripción se **borraba** el adelanto y la
/// frase se volvía a escribir desde cero. Visto y reportado tal cual: «está el
/// texto escrito abajo y después se quita, y ahí sí empieza a hablar y a
/// aparecer el texto».
///
/// Aquí no se borra nada: se decide **cuál de los dos textos se lee**, y el
/// criterio es si el modelo está diciendo lo que le pedimos o se ha ido por otro
/// lado.
///
/// - **Mientras lo que ha dicho quepa dentro del adelanto**, se sigue leyendo el
///   adelanto: es la misma frase, solo que él va por la mitad. Sin esto, la
///   pantalla escribe letra a letra algo que ya estaba escrito entero.
/// - **En cuanto lo dicho pasa del adelanto** —el saludo acaba con la lista de
///   carpetas, que la pone él— se lee lo dicho, que ya es más.
/// - **Y si se va por otro sitio** —«no hay ninguna carpeta que se llame así»—
///   manda lo dicho, siempre. El adelanto es una promesa de lo que va a decir,
///   no una versión oficial que tape lo que dijo.
abstract final class ElAdelantoDeLaPuerta {
  static String loQueSeVe({required String adelanto, required String dicho}) {
    final loDicho = dicho.trim();
    if (loDicho.isEmpty) return adelanto;
    if (adelanto.trim().isEmpty) return loDicho;

    final a = _comparable(adelanto);
    final d = _comparable(loDicho);
    // Va por la mitad de la misma frase: se deja lo que ya estaba.
    if (a.startsWith(d)) return adelanto;
    // La misma frase y más: lo suyo gana, que trae la lista de carpetas.
    if (d.startsWith(a)) return loDicho;
    // Otra cosa: lo que se oye es lo que se lee.
    return loDicho;
  }

  /// Sin signos, sin acentos, sin mayúsculas y sin espacios de más.
  ///
  /// La transcripción del servicio puntúa a su aire —«Buenos días, Argonauta.»
  /// contra «Buenos días, Argonauta,»— y a veces se come los acentos: con
  /// cualquiera de las dos cosas dentro, la misma frase parecía otra y volvía el
  /// borrón que esto viene a quitar.
  static String _comparable(String texto) {
    var limpio = texto
        .toLowerCase()
        .replaceAll(RegExp(r'[¿?¡!.,;:«»"]+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    for (final (con, sin) in _losAcentos) {
      limpio = limpio.replaceAll(con, sin);
    }
    return limpio;
  }

  static const _losAcentos = [
    ('á', 'a'),
    ('é', 'e'),
    ('í', 'i'),
    ('ó', 'o'),
    ('ú', 'u'),
    ('ü', 'u'),
    ('ñ', 'n'),
  ];
}
