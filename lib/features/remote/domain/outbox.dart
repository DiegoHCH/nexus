import 'package:flutter/foundation.dart';

/// Los encargos escritos sin cobertura, esperando su turno.
///
/// **Es la pieza que hace útil el teléfono en el metro**, y solo es segura por lo que
/// se decidió en el escritorio: el `clientMsgId` se crea **con el encargo, no con el
/// envío**, así que reenviarlo no puede ejecutarlo dos veces. Sin el deduplicador del
/// Mac —pieza 3 de la 4.1— un outbox sería una máquina de escribir dos veces en tus
/// archivos.
///
/// Y por eso guarda **solo lo que muta**. Una consulta perdida no se encola: se vuelve
/// a pedir cuando haya red, con id nuevo. Encolar lecturas llenaría la cola de
/// preguntas cuya respuesta ya no le interesa a nadie —el medidor de hace veinte
/// minutos— y las mandaría todas de golpe al reconectar.
@immutable
class PendingErrand {
  const PendingErrand({
    required this.clientMsgId,
    required this.conversationId,
    required this.text,
    required this.escritoEn,
    this.intentos = 0,
  });

  factory PendingErrand.fromJson(Map<String, Object?> j) => PendingErrand(
    clientMsgId: j['id']! as String,
    conversationId: j['conversation']! as String,
    text: j['text']! as String,
    escritoEn: DateTime.parse(j['at']! as String),
    intentos: (j['tries'] as int?) ?? 0,
  );

  /// **El mismo en cada intento.** Es lo único que separa «reintentar» de «ejecutar
  /// dos veces», y por eso se genera al escribir el encargo y se guarda con él.
  final String clientMsgId;

  final String conversationId;
  final String text;

  /// Cuándo se escribió, no cuándo se manda.
  ///
  /// Se guarda porque un encargo tiene contexto: «arregla el test que acabo de
  /// romper» escrito hace tres horas ya no significa lo mismo. La pantalla lo enseña,
  /// y de aquí sale la caducidad.
  final DateTime escritoEn;

  /// Cuántas veces se intentó. No es estadística: de aquí sale el darse por vencido.
  final int intentos;

  PendingErrand conUnIntentoMas() => PendingErrand(
    clientMsgId: clientMsgId,
    conversationId: conversationId,
    text: text,
    escritoEn: escritoEn,
    intentos: intentos + 1,
  );

  Map<String, Object?> toJson() => {
    'id': clientMsgId,
    'conversation': conversationId,
    'text': text,
    'at': escritoEn.toIso8601String(),
    'tries': intentos,
  };
}

/// Por qué un encargo salió de la cola sin llegar a ejecutarse.
enum DiscardReason {
  /// Demasiado viejo. Un encargo escrito hace horas se refiere a un estado del repo
  /// que ya no existe, y mandarlo entonces es peor que no mandarlo.
  caducado,

  /// El Mac lo rechazó por algo que **no** se arregla reintentando: la conversación
  /// ya no está, o el texto no se entiende. Reintentar eso es un bucle.
  rechazado,

  /// Se agotaron los intentos.
  demasiadosIntentos,
}

/// La cola, con su política.
///
/// Es dominio puro: no sabe de sockets ni de almacenamiento. Quien la usa le dice qué
/// pasó con cada envío y ella dice qué queda por hacer.
class Outbox {
  Outbox({
    this.maximo = 20,
    this.caducidad = const Duration(hours: 2),
    this.intentosMaximos = 5,
    DateTime Function()? reloj,
    List<PendingErrand> inicial = const [],
  }) : _reloj = reloj ?? DateTime.now,
       _cola = [...inicial];

  /// Cuántos encargos se guardan.
  ///
  /// Con tope, y bajo: una cola larga escrita sin cobertura son veinte encargos que
  /// se lanzan **de golpe** al reconectar, sobre un repo que ninguno de ellos vio.
  /// El tope es lo que convierte «se me acumuló» en «no cabe más, manda lo que hay».
  final int maximo;

  /// Cuándo un encargo deja de tener sentido.
  ///
  /// Dos horas, y la razón es el contenido y no la memoria: un encargo habla del
  /// repo tal como estaba al escribirlo. «Sigue con lo de antes» tres horas después
  /// se ejecuta sobre otra cosa.
  final Duration caducidad;

  final int intentosMaximos;
  final DateTime Function() _reloj;
  final List<PendingErrand> _cola;

  List<PendingErrand> get pendientes => List.unmodifiable(_cola);
  int get cuantos => _cola.length;
  bool get vacio => _cola.isEmpty;
  bool get lleno => _cola.length >= maximo;

  /// Encola un encargo. Devuelve `null` si no cabe.
  ///
  /// **El id lo trae quien llama**, y eso es a propósito: se crea con el encargo, en
  /// la pantalla, y así el mismo id sobrevive a reintentos, a cerrar la app y a
  /// reinstalarla mientras la cola esté guardada.
  PendingErrand? encolar({
    required String clientMsgId,
    required String conversationId,
    required String text,
  }) {
    if (lleno) return null;
    final encargo = PendingErrand(
      clientMsgId: clientMsgId,
      conversationId: conversationId,
      text: text,
      escritoEn: _reloj(),
    );
    _cola.add(encargo);
    return encargo;
  }

  /// El siguiente a mandar, o `null`.
  ///
  /// **De uno en uno y en orden**, no todos a la vez. Dos encargos de la misma
  /// conversación lanzados en paralelo se pisan el contexto —es la misma razón por la
  /// que el escritorio los pone en cola— y en orden inverso además harían lo
  /// contrario de lo que se pidió.
  PendingErrand? get siguiente => _cola.isEmpty ? null : _cola.first;

  /// Llegó. Fuera de la cola.
  void confirmar(String clientMsgId) =>
      _cola.removeWhere((e) => e.clientMsgId == clientMsgId);

  /// No llegó, pero se puede volver a intentar.
  ///
  /// Devuelve el motivo si se descarta. Se apunta el intento **antes** de decidir:
  /// si se contara después, un fallo permanente daría vueltas para siempre.
  DiscardReason? falloReintentable(String clientMsgId) {
    final i = _cola.indexWhere((e) => e.clientMsgId == clientMsgId);
    if (i < 0) return null;

    final conUnoMas = _cola[i].conUnIntentoMas();
    if (conUnoMas.intentos >= intentosMaximos) {
      _cola.removeAt(i);
      return DiscardReason.demasiadosIntentos;
    }
    _cola[i] = conUnoMas;
    return null;
  }

  /// El Mac dijo que no por algo que no se arregla insistiendo.
  DiscardReason falloDefinitivo(String clientMsgId) {
    _cola.removeWhere((e) => e.clientMsgId == clientMsgId);
    return DiscardReason.rechazado;
  }

  /// Tira lo que ya no tiene sentido mandar. Devuelve lo tirado, para poder decirlo.
  ///
  /// **Se cuenta desde que se escribió y no desde el último intento**: al revés, un
  /// encargo que reintenta cada minuto nunca caducaría, que es justo el que más
  /// falta le hace.
  List<PendingErrand> caducar() {
    final ahora = _reloj();
    final fuera = [
      for (final e in _cola)
        if (ahora.difference(e.escritoEn) > caducidad) e,
    ];
    _cola.removeWhere(fuera.contains);
    return fuera;
  }

  List<Map<String, Object?>> toJson() => [for (final e in _cola) e.toJson()];

  static List<PendingErrand> leer(List<Object?> crudo) => [
    for (final item in crudo)
      if (item is Map<String, Object?>) PendingErrand.fromJson(item),
  ];
}

/// Donde vive la cola entre arranques.
abstract class OutboxStore {
  Future<List<PendingErrand>> read();
  Future<void> write(List<PendingErrand> encargos);
}

/// Lo último que se leyó del Mac, para poder leerlo sin red.
///
/// **Solo lectura y nada de escritura**: la caché sirve para mirar cómo iba lo que
/// dejaste corriendo, que es el uso principal del teléfono. Guardar acciones
/// pendientes es el outbox y tiene reglas propias — mezclarlos daría una caché que
/// escribe.
abstract class MirrorCache {
  Future<Map<String, Object?>?> read();
  Future<void> write(Map<String, Object?> foto);
  Future<void> clear();
}
