import 'package:flutter/foundation.dart';

/// Por qué se rechaza una conexión.
///
/// Con nombre y no un booleano porque el registro append-only de la decisión 2.5
/// tiene que poder distinguirlas: «token equivocado» y «demasiados intentos» son
/// dos historias distintas, y solo una de las dos parece un ataque.
enum Rechazo {
  /// No traía token.
  sinToken,

  /// Lo traía y no era.
  tokenIncorrecto,

  /// Demasiados intentos desde la misma IP.
  demasiadosIntentos,

  /// El `Host` no era el nuestro.
  hostAjeno,

  /// Traía `Origin`, así que viene de un navegador.
  desdeUnNavegador,
}

/// Quién puede abrir el canal.
///
/// Reúne las decisiones 2.1 a 2.3 del contrato en un sitio, y **fuera del
/// socket**: así se puede probar cada rechazo sin levantar un servidor, que es lo
/// único que hace que estas reglas se comprueben de verdad.
class Gatekeeper {
  Gatekeeper({
    required this.token,
    required this.hostEsperado,
    this.intentosPorVentana = 10,
    this.ventana = const Duration(minutes: 1),
    DateTime Function()? reloj,
  }) : _reloj = reloj ?? DateTime.now;

  /// El que se compara. Se genera en el Mac y se rota desde Ajustes.
  final String token;

  /// La autoridad que este servidor espera ver en `Host`: su dirección de
  /// Tailscale con el puerto.
  final String hostEsperado;

  final int intentosPorVentana;
  final Duration ventana;
  final DateTime Function() _reloj;

  final _intentos = <String, List<DateTime>>{};

  /// Decide si se acepta el upgrade. `null` es aceptar.
  ///
  /// El orden importa y no es arbitrario: **primero lo que no depende del token**.
  /// Comprobar el token de una petición que ya va a rechazarse por `Origin` gasta
  /// una comparación y, sobre todo, cuenta un intento contra una IP que no estaba
  /// intentando adivinar nada.
  Rechazo? revisar({
    required String ip,
    required String? host,
    required String? origin,
    required String? tokenRecibido,
  }) {
    // La regla de `Origin`, que es más simple de lo que parece: **nuestro cliente
    // nunca lo manda.** Un WebSocket de Dart no pone `Origin`; los navegadores lo
    // ponen siempre y no pueden evitarlo. Así que su mera presencia identifica un
    // navegador, y eso es lo que cierra el DNS rebinding — la única de las siete
    // que sigue haciendo falta aunque el transporte sea perfecto.
    if (origin != null && origin.isNotEmpty) return Rechazo.desdeUnNavegador;

    // Y `Host`: aunque el ataque venga de un navegador del propio Mac, ahí llegaría
    // con el `Host` que el atacante resolvió, no con el nuestro.
    if (host != hostEsperado) return Rechazo.hostAjeno;

    if (_pasado(ip)) return Rechazo.demasiadosIntentos;

    if (tokenRecibido == null || tokenRecibido.isEmpty) {
      _anotar(ip);
      return Rechazo.sinToken;
    }
    if (!coincide(tokenRecibido, token)) {
      _anotar(ip);
      return Rechazo.tokenIncorrecto;
    }
    return null;
  }

  /// Compara sin que el **tiempo** diga cuánto acertaste.
  ///
  /// Con `==`, Dart corta en el primer byte distinto: un token que empieza bien
  /// tarda más en fallar que uno que empieza mal, y con suficientes intentos eso se
  /// mide y se adivina byte a byte. Aquí se recorre siempre lo mismo y se acumula
  /// la diferencia.
  ///
  /// La longitud sí se filtra, y es aceptable: la del token la fija esta app, es la
  /// misma para todos y no es secreta. Lo que no puede filtrarse es el contenido.
  @visibleForTesting
  static bool coincide(String a, String b) {
    final ua = a.codeUnits;
    final ub = b.codeUnits;
    var diferencia = ua.length ^ ub.length;
    final hasta = ua.length > ub.length ? ua.length : ub.length;
    for (var i = 0; i < hasta; i++) {
      diferencia |= (i < ua.length ? ua[i] : 0) ^ (i < ub.length ? ub[i] : 0);
    }
    return diferencia == 0;
  }

  bool _pasado(String ip) {
    _limpiar();
    return (_intentos[ip]?.length ?? 0) >= intentosPorVentana;
  }

  void _anotar(String ip) => (_intentos[ip] ??= []).add(_reloj());

  /// Solo cuentan los intentos **fallidos**: un cliente legítimo que se reconecta
  /// veinte veces por mala cobertura no puede quedarse fuera. Los aciertos no
  /// llaman a `_anotar`.
  void _limpiar() {
    final ahora = _reloj();
    _intentos.removeWhere((_, cuando) {
      cuando.removeWhere((t) => ahora.difference(t) > ventana);
      return cuando.isEmpty;
    });
  }

  @visibleForTesting
  int fallosDe(String ip) {
    _limpiar();
    return _intentos[ip]?.length ?? 0;
  }
}
