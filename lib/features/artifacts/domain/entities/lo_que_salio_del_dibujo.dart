/// Lo que salió de pedir una imagen.
///
/// 🔴 **Era `({String? ruta, String? id, String? problema})` con dos códigos
/// sueltos dentro.** El generador escribía `'sin-llave'` y `'sin-carpeta'`, y el
/// controlador los comparaba con esas mismas cadenas escritas otra vez, en otro
/// archivo, sin nada que atara las dos puntas. Una errata en cualquiera de los
/// dos lados no falla: cae en la rama de «no se pudo» y **le enseña el código
/// al usuario** — «no se pudo dibujar: sin-llave».
///
/// Y los tres estados que no son un fallo del modelo se arreglan de maneras
/// distintas —poner la llave, elegir carpeta, volver a intentarlo—, así que
/// contarlos como uno manda a la gente al sitio equivocado.
sealed class LoQueSalioDelDibujo {
  const LoQueSalioDelDibujo();
}

/// Salió, y quedó guardada.
final class LaImagenSalio extends LoQueSalioDelDibujo {
  const LaImagenSalio({required this.ruta, this.id});

  final String ruta;

  /// El identificador de aquella interacción, que es lo que permite `/edita`:
  /// a la API se le manda esto en vez del PNG entero.
  final String? id;
}

/// No hay llave de imágenes para esta cuenta.
///
/// **De esta cuenta, y no de cualquiera**: el gasto sale de un bolsillo
/// concreto, y tomar prestada la de otra porque «alguna hay» es justo lo que se
/// evita.
final class FaltaLaLlaveDeImagenes extends LoQueSalioDelDibujo {
  const FaltaLaLlaveDeImagenes();
}

/// No hay carpeta de documentos donde dejarla.
final class FaltaLaCarpetaDeDocumentos extends LoQueSalioDelDibujo {
  const FaltaLaCarpetaDeDocumentos();
}

/// Se intentó y no salió: el motivo es del modelo o del disco.
final class NoSePudoDibujar extends LoQueSalioDelDibujo {
  const NoSePudoDibujar(this.motivo);

  /// Lo que dijo quien falló. Se enseña tal cual porque es accionable —«vuelve
  /// a intentarlo más tarde» es una instrucción— y esconderlo detrás de «no se
  /// pudo» obliga a adivinar.
  final String? motivo;
}
