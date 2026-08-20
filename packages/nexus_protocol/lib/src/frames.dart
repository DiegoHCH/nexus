import 'dart:convert';

import 'package:meta/meta.dart';

import 'methods.dart';
import 'version.dart';

/// Un mensaje del canal.
///
/// Tres formas, como dice el documento: petición/respuesta, eventos empujados y
/// snapshot. No una sola tubería por la que pase todo — eso obliga a cada extremo
/// a adivinar qué acaba de recibir.
///
/// JSON en texto y no un formato binario: el volumen es bajo **después de agrupar
/// los deltas** —ficha `lo4`— y los dos extremos son Dart, así que lo que se gana
/// con protobuf es poco y lo que se pierde, poder leer una traza con los ojos.
@immutable
sealed class Frame {
  const Frame();

  /// El discriminador va en `t`, y es corto porque viaja en **cada** mensaje.
  static const claveTipo = 't';

  Map<String, Object?> toJson();

  String encode() => jsonEncode(toJson());

  /// Lee un mensaje, y **nunca lanza por no conocerlo**.
  ///
  /// Esa es la regla que hace posible que los dos extremos se actualicen por su
  /// cuenta: lo que no se reconoce vuelve como [UnknownFrame] y quien lo recibe lo
  /// ignora. Si esto lanzara, añadir un evento nuevo al servidor rompería a todos
  /// los teléfonos que no se hubieran actualizado todavía — y entonces cada añadido
  /// sería un cambio de versión.
  ///
  /// Lo que sí lanza es el JSON que no es JSON, o el que no trae `t`: eso no es un
  /// mensaje del futuro, es un mensaje roto.
  static Frame decode(String texto) {
    final crudo = jsonDecode(texto);
    if (crudo is! Map<String, Object?>) {
      throw FormatException('un mensaje tiene que ser un objeto', texto);
    }
    final tipo = crudo[claveTipo];
    if (tipo is! String) {
      throw FormatException('falta «$claveTipo» o no es texto', texto);
    }
    return switch (tipo) {
      'hello' => Hello.fromJson(crudo),
      'welcome' => Welcome.fromJson(crudo),
      'upgrade' => UpgradeRequired.fromJson(crudo),
      'call' => Call.fromJson(crudo),
      'ack' => Ack.fromJson(crudo),
      'result' => Result.fromJson(crudo),
      'failure' => Failure.fromJson(crudo),
      'event' => Event.fromJson(crudo),
      'snapshot' => Snapshot.fromJson(crudo),
      'resume' => Resume.fromJson(crudo),
      _ => UnknownFrame(type: tipo, raw: crudo),
    };
  }
}

/// Quién habla. Hace falta para el registro append-only de la decisión 2.5: «lo
/// pidió el móvil» y «lo pidió el escritorio» no son la misma línea.
enum Peer { desktop, mobile }

// ─────────────────────────── el saludo ───────────────────────────

/// Primer mensaje del cliente.
///
/// **El token no va aquí**: viaja en una cabecera del upgrade, por la decisión 2.1.
/// Un token dentro del primer mensaje acabaría en cualquier traza que registre el
/// primer mensaje, que es justo lo que se quería evitar.
final class Hello extends Frame {
  const Hello({required this.protocol, required this.peer, required this.appVersion});

  factory Hello.fromJson(Map<String, Object?> j) => Hello(
    protocol: ProtocolRange.fromJson(j['protocol']! as Map<String, Object?>),
    peer: Peer.values.byName(j['peer']! as String),
    appVersion: j['app'] as String? ?? '',
  );

  final ProtocolRange protocol;
  final Peer peer;

  /// La versión de la app, que es distinta de la del protocolo y solo sirve para
  /// el registro y para poder decir «actualiza» nombrando algo reconocible.
  final String appVersion;

  @override
  Map<String, Object?> toJson() => {
    Frame.claveTipo: 'hello',
    'protocol': protocol.toJson(),
    'peer': peer.name,
    'app': appVersion,
  };
}

/// El servidor acepta y dice por dónde va la numeración de eventos.
final class Welcome extends Frame {
  const Welcome({required this.protocol, required this.seq});

  factory Welcome.fromJson(Map<String, Object?> j) => Welcome(
    protocol: ProtocolRange.fromJson(j['protocol']! as Map<String, Object?>),
    seq: j['seq']! as int,
  );

  final ProtocolRange protocol;

  /// El último evento emitido. Con esto el cliente sabe si va al día o le faltan
  /// cosas, **sin pedir el snapshot entero**.
  final int seq;

  @override
  Map<String, Object?> toJson() => {
    Frame.claveTipo: 'welcome',
    'protocol': protocol.toJson(),
    'seq': seq,
  };
}

/// No se entienden, y se dice **a quién le toca actualizarse**.
final class UpgradeRequired extends Frame {
  const UpgradeRequired({required this.protocol, required this.who});

  factory UpgradeRequired.fromJson(Map<String, Object?> j) => UpgradeRequired(
    protocol: ProtocolRange.fromJson(j['protocol']! as Map<String, Object?>),
    who: Peer.values.byName(j['who']! as String),
  );

  final ProtocolRange protocol;

  /// Quién tiene que actualizarse. Va explícito porque los dos sentidos son
  /// posibles —la tienda puede empujar el móvil mientras el Mac lleva semanas sin
  /// abrirse— y decirle «actualiza» a quien no puede hacer nada es el peor error
  /// que puede tener una pantalla de error.
  final Peer who;

  @override
  Map<String, Object?> toJson() => {
    Frame.claveTipo: 'upgrade',
    'protocol': protocol.toJson(),
    'who': who.name,
  };
}

// ─────────────────────── petición y respuesta ───────────────────────

/// Una petición del cliente.
final class Call extends Frame {
  const Call({required this.id, required this.method, this.params = const {}});

  factory Call.fromJson(Map<String, Object?> j) => Call(
    id: j['id']! as String,
    method: j['m']! as String,
    params: (j['p'] as Map<String, Object?>?) ?? const {},
  );

  /// El `clientMsgId` de la ficha `lo3`: **lo genera el cliente**, y es lo que
  /// permite al servidor reconocer un reenvío.
  ///
  /// Sin esto, un WebSocket que cae después de que el escritorio recibió el encargo
  /// pero antes de confirmarlo hace que el móvil lo reenvíe y `claude -p` corra dos
  /// veces — con `acceptEdits`, escribiendo dos veces en los archivos.
  final String id;

  /// El nombre del método. Texto y no [RemoteMethod] porque **el servidor puede
  /// recibir uno que no conoce**, de un cliente más nuevo, y eso tiene que poder
  /// contestarse con un error y no reventar al decodificar.
  final String method;

  final Map<String, Object?> params;

  /// El método, si es de los que existen aquí.
  RemoteMethod? get known => RemoteMethod.tryParse(method);

  @override
  Map<String, Object?> toJson() => {
    Frame.claveTipo: 'call',
    'id': id,
    'm': method,
    if (params.isNotEmpty) 'p': params,
  };
}

/// «Lo tengo», y es lo que cierra el agujero del reenvío.
///
/// Va aparte de [Result] a propósito: un encargo tarda minutos, así que confirmar
/// la recepción y devolver el resultado no pueden ser el mismo mensaje. Si lo
/// fueran, el cliente no sabría si reenviar durante todo ese rato.
final class Ack extends Frame {
  const Ack({required this.id, this.duplicate = false});

  factory Ack.fromJson(Map<String, Object?> j) =>
      Ack(id: j['id']! as String, duplicate: j['dup'] as bool? ?? false);

  final String id;

  /// Si ya se había recibido. El cliente no tiene que hacer nada distinto —su
  /// petición está atendida— pero el registro sí quiere saberlo.
  final bool duplicate;

  @override
  Map<String, Object?> toJson() => {
    Frame.claveTipo: 'ack',
    'id': id,
    if (duplicate) 'dup': true,
  };
}

final class Result extends Frame {
  const Result({required this.id, this.data = const {}});

  factory Result.fromJson(Map<String, Object?> j) => Result(
    id: j['id']! as String,
    data: (j['d'] as Map<String, Object?>?) ?? const {},
  );

  final String id;
  final Map<String, Object?> data;

  @override
  Map<String, Object?> toJson() => {
    Frame.claveTipo: 'result',
    'id': id,
    if (data.isNotEmpty) 'd': data,
  };
}

/// Algo salió mal. [id] es nulo cuando el fallo no es de ninguna petición —el
/// saludo, por ejemplo—.
final class Failure extends Frame {
  const Failure({required this.code, required this.message, this.id});

  factory Failure.fromJson(Map<String, Object?> j) => Failure(
    code: j['code']! as String,
    message: j['msg'] as String? ?? '',
    id: j['id'] as String?,
  );

  final String code;
  final String message;
  final String? id;

  @override
  Map<String, Object?> toJson() => {
    Frame.claveTipo: 'failure',
    'code': code,
    if (message.isNotEmpty) 'msg': message,
    if (id != null) 'id': id,
  };
}

// ──────────────────── eventos, snapshot y resync ────────────────────

/// Algo que pasó, numerado.
///
/// El `seq` es monotónico y **no se reinicia** mientras el servidor vive: es lo que
/// hace que reconectar sea «mándame desde el 412» en vez de «mándame todo», que en
/// 4G es la diferencia entre barato y caro.
final class Event extends Frame {
  const Event({required this.seq, required this.kind, this.data = const {}});

  factory Event.fromJson(Map<String, Object?> j) => Event(
    seq: j['seq']! as int,
    kind: j['k']! as String,
    data: (j['d'] as Map<String, Object?>?) ?? const {},
  );

  final int seq;

  /// Texto y no un enum, por lo mismo que en [Call.method]: un cliente viejo tiene
  /// que poder **ignorar** un evento que no conoce. Con un enum, decodificarlo
  /// lanzaría, y añadir un evento al servidor sería romper a todo el que no se
  /// hubiera actualizado.
  final String kind;

  final Map<String, Object?> data;

  @override
  Map<String, Object?> toJson() => {
    Frame.claveTipo: 'event',
    'seq': seq,
    'k': kind,
    if (data.isNotEmpty) 'd': data,
  };
}

/// «Mándame desde aquí».
final class Resume extends Frame {
  const Resume({required this.lastSeq});

  factory Resume.fromJson(Map<String, Object?> j) =>
      Resume(lastSeq: j['last']! as int);

  final int lastSeq;

  @override
  Map<String, Object?> toJson() => {Frame.claveTipo: 'resume', 'last': lastSeq};
}

/// El estado entero. **Camino de excepción**, no el normal: se manda cuando el
/// cliente pide desde un `seq` que ya no está en el búfer.
final class Snapshot extends Frame {
  const Snapshot({required this.seq, required this.data});

  factory Snapshot.fromJson(Map<String, Object?> j) => Snapshot(
    seq: j['seq']! as int,
    data: (j['d'] as Map<String, Object?>?) ?? const {},
  );

  final int seq;
  final Map<String, Object?> data;

  @override
  Map<String, Object?> toJson() => {
    Frame.claveTipo: 'snapshot',
    'seq': seq,
    'd': data,
  };
}

/// Un mensaje de una versión que este extremo no conoce.
///
/// No es un error: es lo que hace que el canal aguante que los dos lados se
/// actualicen por su cuenta. Quien lo recibe lo ignora — y conserva el crudo, para
/// poder registrarlo y saber qué se está perdiendo.
final class UnknownFrame extends Frame {
  const UnknownFrame({required this.type, required this.raw});

  final String type;
  final Map<String, Object?> raw;

  @override
  Map<String, Object?> toJson() => raw;
}
