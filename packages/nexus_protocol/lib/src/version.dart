import 'package:meta/meta.dart';

/// La versión del protocolo, que **no** es la versión de ninguna de las dos apps.
///
/// Existe porque escritorio y móvil se actualizan por su cuenta: el escritorio se
/// actualiza solo desde la 0.0.2 y el teléfono irá por la tienda. Sus versiones van
/// a divergir siempre, así que el canal necesita su propio número.
///
/// Un entero y no `x.y.z`: aquí no hay nada que comunicar salvo «esto es más nuevo
/// que aquello». Un semver invitaría a discutir si un cambio es menor o mayor, y
/// esa discusión no cambia lo único que se hace con el número — compararlo.
extension type const ProtocolVersion(int value) {
  bool operator <(ProtocolVersion other) => value < other.value;
  bool operator >(ProtocolVersion other) => value > other.value;
  bool operator <=(ProtocolVersion other) => value <= other.value;
  bool operator >=(ProtocolVersion other) => value >= other.value;
}

/// La versión que habla este paquete.
///
/// Se sube cuando un cambio rompe a quien no lo conozca. Añadir un evento nuevo
/// **no** lo rompe —los desconocidos se ignoran, ver `UnknownFrame`— así que
/// tampoco sube el número.
const ProtocolVersion protocolCurrent = ProtocolVersion(1);

/// La más antigua con la que este extremo se entiende.
///
/// Igual a la actual mientras no haya nada que mantener: la primera versión no
/// tiene pasado. En cuanto exista la 2, esto dirá hasta dónde se sigue hablando.
const ProtocolVersion protocolMinimum = ProtocolVersion(1);

/// Lo que un extremo anuncia de sí mismo en el saludo.
@immutable
class ProtocolRange {
  const ProtocolRange({required this.min, required this.current});

  factory ProtocolRange.fromJson(Map<String, Object?> json) => ProtocolRange(
    min: ProtocolVersion(json['min']! as int),
    current: ProtocolVersion(json['current']! as int),
  );

  /// La de este paquete, para no repetir las constantes en cada sitio.
  static const mine = ProtocolRange(
    min: protocolMinimum,
    current: protocolCurrent,
  );

  final ProtocolVersion min;
  final ProtocolVersion current;

  Map<String, Object?> toJson() => {'min': min.value, 'current': current.value};

  @override
  bool operator ==(Object other) =>
      other is ProtocolRange && other.min == min && other.current == current;

  @override
  int get hashCode => Object.hash(min, current);

  @override
  String toString() => 'ProtocolRange(${min.value}..${current.value})';
}

/// En qué acaba la negociación.
enum Negotiation {
  /// Se entienden.
  ok,

  /// El cliente es demasiado viejo para este servidor: le toca actualizarse.
  clientMustUpdate,

  /// **Y el caso simétrico, que es el que se olvida:** el servidor es demasiado
  /// viejo para este cliente.
  ///
  /// Pasa de verdad y no es teórico: el teléfono se actualiza por la tienda, que
  /// puede empujar una versión nueva sin preguntar, mientras el Mac lleva semanas
  /// sin abrirse. Si solo se comprobara un sentido, ahí el móvil diría «no
  /// responde» sobre un Mac que responde perfectamente en otro idioma.
  serverMustUpdate,
}

/// Compara lo que dicen los dos extremos.
///
/// Los dos sentidos, y con el mensaje al lado de quien tiene que actuar: decirle
/// «actualiza» a quien no puede hacer nada al respecto es el peor error posible en
/// una pantalla de error.
Negotiation negotiate({
  required ProtocolRange client,
  required ProtocolRange server,
}) {
  if (client.current < server.min) return Negotiation.clientMustUpdate;
  if (server.current < client.min) return Negotiation.serverMustUpdate;
  return Negotiation.ok;
}

/// La versión con la que se hablará: la más nueva que los dos entienden.
///
/// Solo tiene sentido cuando [negotiate] dice `ok`.
ProtocolVersion agreed({
  required ProtocolRange client,
  required ProtocolRange server,
}) => client.current <= server.current ? client.current : server.current;
