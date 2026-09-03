/// Lo que queda por hacer después de mirar a qué carpeta iba el encargo.
sealed class LoQueQuedaPorHacer {
  const LoQueQuedaPorHacer();
}

/// No iba a otra parte: atiéndelo tú, con este texto.
///
/// El texto puede no ser el original: si la carpeta nombrada era la de aquí, la
/// mención se quita —repetirla dentro de un encargo que ya corre ahí es ruido en
/// el prompt, y el prompt se paga—.
final class AtiendeloTu extends LoQueQuedaPorHacer {
  const AtiendeloTu(this.tarea);
  final String tarea;
}

/// Ya se fue a otra conversación. Aquí no queda trabajo.
final class YaSeFue extends LoQueQuedaPorHacer {
  const YaSeFue(this.carpeta);

  /// Cómo se llama la carpeta a la que se fue, para poder decirlo.
  final String carpeta;
}

/// No se hizo nada y hay que decir esto.
final class HayQueDecir extends LoQueQuedaPorHacer {
  const HayQueDecir(this.texto);
  final String texto;
}

/// Quién decide a qué carpeta va un encargo, y lo lleva.
///
/// 🔴 **Existe porque el enrutado vivía dentro de `submit`, y la voz no pasa por
/// `submit`.** El compositor y el teléfono entran por ahí; la conversación
/// hablada llama al puente de Claude directamente. Con el enrutado metido en el
/// primero, «en el front mobile, arregla el login» funcionaba escribiendo y no
/// hablando — que es de donde salió la idea.
///
/// Es un puerto de dominio y no una función suelta por eso mismo: lo necesitan
/// dos capas, y la de voz no puede leer proveedores.
abstract interface class ElDespachoDeCarpeta {
  /// Mira si la frase nombra una carpeta y, si hace falta, lleva el encargo
  /// allí. [carpetaDeAqui] es la de quien pregunta.
  Future<LoQueQuedaPorHacer> despachar(
    String frase, {
    required String? carpetaDeAqui,
    required String loQueSeVe,
    required bool allowWrites,
    required List<String> attachments,
  });
}
