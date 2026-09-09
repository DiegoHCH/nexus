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
  /// [elFocoSigue] dice si quien pidió esto **está mirando esta pantalla**.
  ///
  /// 🔴 **Lo pone quien manda el encargo, y no es un detalle.** Desde el Mac el
  /// foco moviéndose es la señal de que el trabajo se fue a otra parte. Desde el
  /// teléfono no: el móvil navega a una conversación concreta y no sigue al
  /// foco, así que moverlo **haría saltar la pantalla de quien esté delante del
  /// Mac sin haberlo pedido**, y encima dejaría al teléfono mirando una pestaña
  /// donde no pasa nada. Con `false` el foco se queda quieto y quien lo pidió
  /// recibe una frase diciendo a dónde fue.
  Future<LoQueQuedaPorHacer> despachar(
    String frase, {
    required String? carpetaDeAqui,
    required String loQueSeVe,
    required bool allowWrites,
    required List<String> attachments,
    bool elFocoSigue = true,
  });

  /// Lleva un encargo a **una carpeta que ya se sabe cuál es**, sin mirar la
  /// frase.
  ///
  /// 🔴 **Existe porque hay quien ya sabe la carpeta y no tiene una frase que
  /// parsear.** El primero es el error de la app: la corrida sabe en qué
  /// proyecto pasó, y pedirle que redacte «en front-mobile-b2c, arregla esto»
  /// para que el enrutado vuelva a deducir la carpeta sería escribir una
  /// adivinanza para acertarla nosotros mismos.
  ///
  /// Va en el puerto y no como una función suelta en la pantalla que lo pide
  /// por lo de siempre: llevar un encargo a una conversación —buscarla, abrirla
  /// si no está, mover el foco, respetar el tope de escritura— es una sola cosa
  /// y ya vive aquí. Copiarla sería tener dos sitios que se separan.
  ///
  /// [loQueSeVe] es lo que se pinta en el chat, que casi nunca es el encargo
  /// entero: un error con su traza son treinta líneas y en la conversación
  /// sobra con una.
  Future<LoQueQuedaPorHacer> aEstaCarpeta(
    String carpeta, {
    required String tarea,
    required String loQueSeVe,
    bool allowWrites = true,
  });
}
