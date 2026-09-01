import 'package:flutter/foundation.dart';

/// La variante regional con la que se pide que hable la voz.
///
/// ## Por qué esto y no «una voz latina»
///
/// 🔴 **Las voces de Gemini no tienen acento ni género.** La doc las describe
/// solo por cualidad vocal —brillante, firme, cálida— y sobre el idioma es
/// explícita: «the Live API supports multiple languages, with models
/// automatically detecting and selecting the appropriate language for output.
/// Explicitly setting a language code is not supported for native audio output
/// models». La misma voz habla el idioma y el acento que le toque.
///
/// Lo que sí soporta, también de la doc: «you can control style, tone,
/// **accent**, and pace using natural language prompts». Así que el acento se
/// pide con palabras, y por eso esto acaba en la instrucción del sistema y no
/// en un campo del protocolo — donde no existe.
@immutable
class ElAcento {
  const ElAcento(this.variante);

  /// Sin elegir: se dice el idioma a secas y el modelo decide.
  const ElAcento.sinElegir() : variante = null;

  /// Cómo se nombra la variante, tal como se le dice al modelo: «de Colombia»,
  /// «latinoamericano». `null` es «no lo he dicho», que no es lo mismo que
  /// pedir el neutro: pedirlo es una instrucción y callarse no.
  final String? variante;

  /// Las que se ofrecen en Ajustes.
  ///
  /// No es una lista cerrada por gusto: son las que se pueden nombrar sin
  /// ambigüedad en una frase corta. Nombrar el país funciona mejor que nombrar
  /// el acento —«de México» antes que «mexicano»— porque lo segundo se lee
  /// como una etiqueta y lo primero como un sitio.
  static const opciones = <ElAcento>[
    ElAcento.sinElegir(),
    ElAcento('latinoamericano'),
    ElAcento('de Colombia'),
    ElAcento('de México'),
    ElAcento('de Argentina'),
    ElAcento('de Chile'),
    ElAcento('de España'),
  ];

  /// El idioma con su variante, listo para la instrucción del sistema.
  ///
  /// Se compone aquí y no en quien la escribe para que «español» y «español
  /// latinoamericano» salgan del mismo sitio: son la misma frase con y sin
  /// coletilla, y separarlas invita a que una se actualice y la otra no.
  String conElIdioma(String idioma) =>
      variante == null ? idioma : '$idioma $variante';

  /// Lo que se guarda. Cadena vacía nunca: se borra la clave.
  String? get guardado => variante;

  static ElAcento porNombre(String? guardado) =>
      guardado == null || guardado.isEmpty
      ? const ElAcento.sinElegir()
      : opciones.firstWhere(
          (a) => a.variante == guardado,
          // Una variante guardada que ya no está en la lista se respeta en vez
          // de caer al neutro: la eligió alguien y sigue siendo una frase
          // válida para el modelo.
          orElse: () => ElAcento(guardado),
        );

  @override
  bool operator ==(Object other) =>
      other is ElAcento && other.variante == variante;

  @override
  int get hashCode => variante.hashCode;
}
