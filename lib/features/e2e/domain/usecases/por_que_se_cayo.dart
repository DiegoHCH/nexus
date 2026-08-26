/// Por qué se cayó una corrida, cuando se puede reconocer.
///
/// **Existe porque los fallos de dispositivo llegan sin mensaje.** El caso que lo
/// motivó, medido en un móvil real: HyperOS bloquea la instalación del driver y la
/// excepción llega con el texto vacío —`AndroidOperationFailedException: ` y nada
/// detrás—. `adb install` a mano tampoco dice nada. Así que la ventana enseñaba los
/// ocho pasos en gris y veinte líneas de traza de Kotlin, y ninguna de las dos cosas
/// dice qué hacer.
///
/// Lo que sí es reconocible es **dónde se rompió**, por la pila. De eso se saca una
/// frase con el siguiente paso dentro.
///
/// Deliberadamente corto: tres casos, los tres vistos de verdad en esta máquina. No
/// es un clasificador de errores de Maestro, es traducir los que ya nos han costado
/// una tarde. Lo que no reconoce se queda sin frase y se enseña la salida cruda,
/// que es lo que había antes: **no reconocer no puede ser peor que antes.**
enum PorQueSeCayo {
  /// El driver de Maestro no se pudo instalar en el dispositivo.
  driverNoSeInstala,

  /// El dispositivo no deja inyectar toques: lecturas sí, escrituras no.
  sinPermisoParaTocar,

  /// La app que la prueba quiere abrir no está en el dispositivo.
  appNoInstalada,
}

abstract final class PorQueSeCayoLaCorrida {
  /// Lo reconocible de una salida, o `null`.
  ///
  /// Se mira de lo más específico a lo más general: un fallo al instalar el driver
  /// pasa **antes** de cualquier paso, y el de los toques en medio de uno, así que
  /// no compiten. El de la app puede venir con código de salida 0, y esa es otra
  /// historia que ya avisa el panel antes de correr.
  static PorQueSeCayo? de(String salida) {
    // La pila lo dice: `installMaestroDriverApp` es la instalación del driver, no
    // la de la app que se prueba.
    if (salida.contains('installMaestroDriverApp') ||
        salida.contains('installMaestroApks')) {
      return PorQueSeCayo.driverNoSeInstala;
    }
    if (salida.contains('INJECT_EVENTS')) {
      return PorQueSeCayo.sinPermisoParaTocar;
    }
    if (salida.contains('is not installed')) {
      return PorQueSeCayo.appNoInstalada;
    }
    return null;
  }
}
