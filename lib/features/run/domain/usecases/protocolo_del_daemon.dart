import 'dart:convert';

import 'package:nexus/features/run/domain/entities/mensaje_del_daemon.dart';

/// El idioma de `flutter run --machine`.
///
/// **Se eligió este canal y no `flutter run` a secas**, y la diferencia no es de
/// gusto: por aquí una recarga **contesta si funcionó**. Con el comando normal se
/// escribe una `r` en su stdin y se espera a ver si aparece algo en la salida,
/// que es adivinar. Es además el mismo canal que usa VS Code, así que es un
/// contrato y no un texto para personas.
///
/// Todo aquí es puro: entra texto, sale un mensaje. Los procesos los lanza el
/// data source, y así este idioma se puede probar con las líneas de verdad sin
/// arrancar nada.
abstract final class ProtocoloDelDaemon {
  /// Una línea de su salida.
  ///
  /// **Cada mensaje viene envuelto en un array de un solo elemento** —`[{…}]`—,
  /// que es una rareza del formato y no un descuido: así se distingue de un
  /// JSON cualquiera que imprima la app por su cuenta. Lo que no encaje en ese
  /// molde es registro, y se conserva.
  static MensajeDelDaemon leerLinea(String linea) {
    final texto = linea.trim();
    if (texto.isEmpty) return const RegistroDelDaemon('');
    if (!(texto.startsWith('[{') && texto.endsWith('}]'))) {
      return RegistroDelDaemon(linea);
    }

    final Object? leido;
    try {
      leido = jsonDecode(texto);
    } on FormatException {
      return RegistroDelDaemon(linea);
    }
    if (leido is! List || leido.isEmpty) return RegistroDelDaemon(linea);

    final mensaje = leido.first;
    if (mensaje is! Map) return RegistroDelDaemon(linea);

    if (mensaje['event'] case final String nombre) {
      return EventoDelDaemon(
        nombre: nombre,
        params: switch (mensaje['params']) {
          final Map<Object?, Object?> params => params.cast<String, Object?>(),
          _ => const {},
        },
      );
    }

    // `case final int id` y no `case final id?`: el segundo también aceptaría una
    // cadena o un booleano en ese sitio, y un id que no es número no se puede
    // emparejar con nada. Un id de 0 sí entra, que es lo que importa.
    if (mensaje['id'] case final int id) {
      return RespuestaDelDaemon(
        id: id,
        result: mensaje['result'],
        error: mensaje['error'],
      );
    }

    return RegistroDelDaemon(linea);
  }

  /// Una petición, ya con su salto de línea: una por línea, como espera el otro
  /// lado.
  static String peticion(int id, String metodo, Map<String, Object?> params) =>
      '${jsonEncode([
        {'id': id, 'method': metodo, 'params': params},
      ])}\n';

  /// Recargar. **Recarga y reinicio son el mismo método con una bandera
  /// distinta**, y por eso no hay dos funciones: separarlos invitaría a que una
  /// se quedara sin el `pause` o sin el `reason` el día que alguien toque una.
  static String peticionDeRecarga(
    int id,
    String appId, {
    required bool completa,
  }) => peticion(id, 'app.restart', {
    'appId': appId,
    'fullRestart': completa,
    'pause': false,
    'reason': 'manual',
  });

  /// Parar. **Por el daemon y no matando el proceso**: así la app se cierra sola
  /// y el otro lado avisa con `app.stop` en vez de dejar un hueco.
  static String peticionDeParada(int id, String appId) =>
      peticion(id, 'app.stop', {'appId': appId});

  /// Qué salió de una respuesta.
  ///
  /// Tres formas distintas y todas reales, que es el motivo de que esto exista:
  ///
  /// - `error` puesto: falló, y su texto es lo accionable.
  /// - un `result` con `code`: cero es que fue bien; cualquier otro trae
  ///   `message`, que es lo que hay que enseñar.
  /// - **`app.stop` contesta `true` pelado**, sin objeto ni código. Tratarlo con
  ///   la regla del `code` lo daría por fallido.
  static ({bool ok, String? error}) resultadoDe(Object? result, Object? error) {
    if (error != null) return (ok: false, error: '$error');

    if (result is Map && result.containsKey('code')) {
      if (result['code'] == 0) return (ok: true, error: null);
      final mensaje = result['message'];
      return (
        ok: false,
        error: mensaje is String && mensaje.isNotEmpty
            ? mensaje
            : 'código ${result['code']}',
      );
    }

    return (ok: true, error: null);
  }

  /// El progreso, que **no es un valor sino un conjunto abierto**.
  ///
  /// `app.progress` llega con ids que se solapan —compilar y firmar a la vez— y
  /// cada uno se cierra por su cuenta con `finished`. Guardar solo el último
  /// mensaje dejaría la barra diciendo «firmando» después de que la firma acabara
  /// y la compilación siguiera. Así que se lleva un mapa y se enseña el último
  /// que siga abierto.
  static Map<String, ProgresoDelDaemon> aplicaProgreso(
    Map<String, ProgresoDelDaemon> actual,
    Map<String, Object?> params,
  ) {
    final id = '${params['id'] ?? ''}';
    if (id.isEmpty) return actual;

    final siguiente = Map<String, ProgresoDelDaemon>.of(actual);
    if (params['finished'] == true) {
      siguiente.remove(id);
    } else {
      siguiente[id] = ProgresoDelDaemon(
        id: id,
        mensaje: '${params['message'] ?? ''}',
        tipo: params['progressId'] as String?,
      );
    }
    return siguiente;
  }

  /// El que se enseña: el último que siga abierto, o nada.
  static ProgresoDelDaemon? progresoVisible(
    Map<String, ProgresoDelDaemon> mapa,
  ) => mapa.isEmpty ? null : mapa.values.last;
}
