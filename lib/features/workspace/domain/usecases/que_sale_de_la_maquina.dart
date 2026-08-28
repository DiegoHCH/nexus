import 'package:nexus/features/history/domain/repositories/conversation_archive.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';

/// Por dónde puede salir algo de este Mac, y si está saliendo ahora.
///
/// **Cada una de estas decisiones ya estaba bien tomada por separado** —la
/// modalidad de la carpeta, la lista de `escrituraDeFuera`, la frase de
/// escritura, el destino de archivo— y ninguna se toca aquí. Lo que faltaba es
/// un sitio donde se vean **juntas**: tres o cuatro decisiones correctas que
/// nadie puede comprobar a la vez no son una promesa, son cuatro promesas
/// sueltas.
///
/// Esto es la regla, sin interfaz. Recibe estado y devuelve estado: así se puede
/// probar que dice la verdad, que es lo único que le da valor a una pantalla
/// como esta. Una que se equivoque es peor que no tenerla — se lee como un
/// permiso.
enum Salida {
  /// **Anthropic, y va la primera.**
  ///
  /// El informe que pidió esta pantalla listaba tres puertas y se dejó la que
  /// está siempre abierta. La guía en frío sí la nombra: «Claude Code manda a
  /// Anthropic lo que lee de tu carpeta, porque es así como trabaja». Una lista
  /// que empieza por Gemini se lee como completa, y entonces esconde justo lo
  /// que más viaja.
  anthropic,

  /// El servicio de voz de Google. Micrófono **y** lo que Claude leyó, porque
  /// una respuesta de herramienta narrada lleva dentro lo segundo.
  gemini,

  /// Conversaciones enteras, por su API.
  notion,

  /// El canal del teléfono, dentro de la tailnet.
  canal,
}

/// Si algo puede salir por ahí, y si está saliendo.
enum ComoEsta {
  /// Nada sale por aquí ahora mismo, y no puede salir sin cambiar un ajuste.
  cerrada,

  /// Puede salir. No está saliendo en este instante, pero no hace falta tocar
  /// nada para que empiece — un encargo, un turno hablado, un archivado.
  disponible,

  /// Está saliendo **ahora**.
  abierta,
}

/// Una puerta con su estado y, si viene a cuento, el dato que la identifica: la
/// cuenta con la que se trabaja, la dirección del canal. No lleva textos: los
/// pone quien pinta, que es quien sabe en qué idioma.
typedef PuertaDeSalida = ({Salida cual, ComoEsta como, String? dato});

abstract final class QueSaleDeLaMaquina {
  /// Las cuatro puertas para la carpeta enfocada.
  ///
  /// Siempre las cuatro, también las cerradas: una lista que solo enseña lo
  /// abierto no responde «¿y Notion?», que es justo la pregunta que trae a
  /// alguien aquí.
  static List<PuertaDeSalida> para({
    required PairedFolder? carpeta,
    required bool hayLlaveDeGemini,
    required bool vozAbierta,
    required ArchiveDestination destinoDeArchivo,
    required bool destinoListo,
    required bool canalEncendido,
    required bool hayAlguienConectado,
    String? direccionDelCanal,
  }) => [
    (
      cual: Salida.anthropic,
      // Sin carpeta emparejada no hay nada que mandar; con una, va en **cada**
      // encargo. No es «disponible»: es cómo funciona el producto, y decirlo de
      // otra forma sería suavizarlo.
      como: carpeta == null ? ComoEsta.cerrada : ComoEsta.abierta,
      dato: carpeta?.claudeProfile,
    ),
    (
      cual: Salida.gemini,
      como: _gemini(
        carpeta: carpeta,
        hayLlave: hayLlaveDeGemini,
        vozAbierta: vozAbierta,
      ),
      dato: null,
    ),
    (
      cual: Salida.notion,
      // Archivar pasa al terminar cada turno, así que estando configurado esto
      // no es «podría»: es que va a pasar en cuanto digas algo.
      como: destinoDeArchivo == ArchiveDestination.notion && destinoListo
          ? ComoEsta.abierta
          : ComoEsta.cerrada,
      dato: null,
    ),
    (
      cual: Salida.canal,
      como: !canalEncendido
          ? ComoEsta.cerrada
          : hayAlguienConectado
          ? ComoEsta.abierta
          : ComoEsta.disponible,
      dato: canalEncendido ? direccionDelCanal : null,
    ),
  ];

  /// La de voz es la única con tres caminos, y el orden importa.
  ///
  /// **Sin llave, cerrada aunque la carpeta permita voz**: no hay con qué
  /// abrirla, y decir «disponible» sería prometer algo que al pulsar falla.
  ///
  /// **En una carpeta de solo texto, cerrada aunque haya llave.** Y no solo el
  /// micrófono: en `textOnly` el servicio de voz no participa, porque restringir
  /// solo la entrada dejaría la fuga abierta por el otro lado — lo que Claude
  /// leyó viaja hacia Google dentro de la respuesta narrada.
  static ComoEsta _gemini({
    required PairedFolder? carpeta,
    required bool hayLlave,
    required bool vozAbierta,
  }) {
    if (carpeta == null || !carpeta.modality.allowsVoice) {
      return ComoEsta.cerrada;
    }
    if (!hayLlave) return ComoEsta.cerrada;
    return vozAbierta ? ComoEsta.abierta : ComoEsta.disponible;
  }
}
