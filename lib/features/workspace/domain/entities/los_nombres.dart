import 'package:flutter/foundation.dart';

/// Cómo se llama quien contesta, y cómo te llamas tú.
///
/// **La app sigue llamándose Nexus.** Eso está compilado dentro —el Dock, el
/// título de la ventana, el identificador de los canales nativos y del
/// llavero— y cambiarlo no es un ajuste sino otra app. Lo que se elige aquí es
/// **quién te contesta**, que es distinto: Nexus es la herramienta y el nombre
/// de aquí es el de la voz que sale de ella.
///
/// La separación además hace falta en cuanto la instala alguien más: cada uno le
/// pone el nombre que quiera sin que nadie tenga que discutir cómo se llama el
/// producto.
///
/// ## Y no hay palabra de activación
///
/// 🔴 Ponerle un nombre **no hace que despierte al decirlo**. La voz se abre con
/// `⌥Espacio`, y una palabra de activación pediría el micrófono escuchando
/// siempre — que es otra función y otra decisión. Lo que sí ocurre es que
/// escribirle «Patricia, revisa esto» se entiende como que le hablas a ella,
/// porque el nombre viaja en el prompt y Claude lee el texto.
@immutable
class LosNombres {
  const LosNombres({this.agente, this.tuyo});

  /// Cómo se llama quien contesta, o `null` para dejar el de la app.
  final String? agente;

  /// Cómo quieres que te llame, o `null` para que no te llame de ninguna forma.
  ///
  /// Vacío no es «llámame vacío»: es que no lo has dicho. Por eso se guarda
  /// `null` y no una cadena en blanco — quien lee tiene que poder distinguir
  /// «no quiero» de «se me olvidó».
  final String? tuyo;

  /// Global y no por carpeta, al revés que casi todo en esta app.
  ///
  /// La cuenta, el modelo y los permisos van por carpeta porque **cambian con el
  /// trabajo**. Tu nombre no cambia según el repo, y el de quien te contesta
  /// tampoco: tener que decirlo cinco veces —una por carpeta— sería trabajo sin
  /// nada a cambio.
  bool get hayAlgo => agente != null || tuyo != null;

  /// El nombre a enseñar sobre sus respuestas. [porDefecto] es el de la app.
  String etiqueta(String porDefecto) {
    final elegido = agente;
    return elegido == null || elegido.isEmpty
        ? porDefecto
        : elegido.toUpperCase();
  }

  LosNombres copyWith({Object? agente = nada, Object? tuyo = nada}) =>
      LosNombres(
        agente: agente == nada ? this.agente : agente as String?,
        tuyo: tuyo == nada ? this.tuyo : tuyo as String?,
      );

  /// El centinela de «no lo toques», distinto de «bórralo».
  static const nada = Object();

  /// Lo que se le añade al prompt del sistema, o `null` si no hay nada que
  /// decir.
  ///
  /// **Se le habla a Claude de lo que tiene que hacer, no de lo que es.** No se
  /// le pide un personaje ni un tono: solo el nombre con el que dirigirse a
  /// quien pregunta y el suyo, que es información y no disfraz. Un prompt que
  /// pide actuar cambia también cómo razona, y eso no es lo que se compró aquí.
  String? paraElPrompt() {
    final lineas = <String>[
      if (tuyo case final nombre? when nombre.isNotEmpty)
        'La persona con la que hablas se llama $nombre. Llámala por su nombre '
            'cuando sea natural hacerlo, sin forzarlo en cada frase.',
      if (agente case final nombre? when nombre.isNotEmpty)
        'En esta app te llamas $nombre. Si te habla por ese nombre, es a ti. No '
            'lo repitas al empezar cada respuesta.',
    ];
    return lineas.isEmpty ? null : lineas.join('\n');
  }

  /// El nombre con el que empezar un aviso hablado, con su coma, o vacío.
  ///
  /// Vacío y no `null` para que quien compone la frase la concatene sin
  /// preguntar: un aviso es una sola línea y no merece un `if` en quien lo dice.
  String get vocativo {
    final nombre = tuyo;
    return nombre == null || nombre.isEmpty ? '' : '$nombre, ';
  }
}
