import 'package:flutter/foundation.dart';

/// Una de las voces que el servicio sabe poner.
@immutable
class NexusVoice {
  const NexusVoice(this.name, this.character);

  /// El identificador que espera la API. No se traduce ni se toca.
  final String name;

  /// Cómo suena, en una palabra. Se traduce porque es para leerlo, no para
  /// mandarlo.
  final String character;

  /// La que se usa mientras nadie elija otra.
  ///
  /// Elegir una explícitamente **es** el arreglo: sin `speechConfig` el
  /// servicio pone la que quiere, y la voz cambiaba de una sesión a otra.
  static const fallback = NexusVoice('Charon', 'informativa');

  /// Las 30 del servicio, en el orden en que las documenta Google.
  static const all = [
    NexusVoice('Zephyr', 'brillante'),
    NexusVoice('Puck', 'animada'),
    NexusVoice('Charon', 'informativa'),
    NexusVoice('Kore', 'firme'),
    NexusVoice('Fenrir', 'excitable'),
    NexusVoice('Leda', 'juvenil'),
    NexusVoice('Orus', 'firme'),
    NexusVoice('Aoede', 'ligera'),
    NexusVoice('Callirrhoe', 'tranquila'),
    NexusVoice('Autonoe', 'brillante'),
    NexusVoice('Enceladus', 'susurrada'),
    NexusVoice('Iapetus', 'clara'),
    NexusVoice('Umbriel', 'tranquila'),
    NexusVoice('Algieba', 'suave'),
    NexusVoice('Despina', 'suave'),
    NexusVoice('Erinome', 'clara'),
    NexusVoice('Algenib', 'áspera'),
    NexusVoice('Rasalgethi', 'informativa'),
    NexusVoice('Laomedeia', 'animada'),
    NexusVoice('Achernar', 'delicada'),
    NexusVoice('Alnilam', 'firme'),
    NexusVoice('Schedar', 'templada'),
    NexusVoice('Gacrux', 'madura'),
    NexusVoice('Pulcherrima', 'directa'),
    NexusVoice('Achird', 'cercana'),
    NexusVoice('Zubenelgenubi', 'informal'),
    NexusVoice('Vindemiatrix', 'amable'),
    NexusVoice('Sadachbia', 'viva'),
    NexusVoice('Sadaltager', 'docta'),
    NexusVoice('Sulafat', 'cálida'),
  ];

  static NexusVoice byName(String? name) {
    for (final voice in all) {
      if (voice.name == name) return voice;
    }
    return fallback;
  }
}
