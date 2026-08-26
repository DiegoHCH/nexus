/// Lo que dice `flutter run --machine` por su salida.
///
/// Tres cosas y no una, porque hay que tratarlas distinto: un **evento** cuenta
/// algo que pasó, una **respuesta** contesta a algo que pedimos, y todo lo demás
/// es **registro** — la salida del compilador, los avisos de Gradle, lo que
/// imprima la app.
///
/// Un `sealed` y no un `enum` con campos: así el `switch` que los reparte no
/// puede olvidarse de uno, y añadir un cuarto tipo rompe la compilación en vez
/// de caerse por el `default`.
sealed class MensajeDelDaemon {
  const MensajeDelDaemon();
}

/// Algo que pasó: `app.start`, `app.started`, `app.progress`, `app.stop`…
class EventoDelDaemon extends MensajeDelDaemon {
  const EventoDelDaemon({required this.nombre, this.params = const {}});

  final String nombre;
  final Map<String, Object?> params;
}

/// La contestación a una petición nuestra, emparejada por [id].
class RespuestaDelDaemon extends MensajeDelDaemon {
  const RespuestaDelDaemon({required this.id, this.result, this.error});

  final int id;
  final Object? result;
  final Object? error;
}

/// Todo lo demás, tal cual salió.
///
/// **No se descarta**: aquí viven los errores de compilación, que son justo lo
/// que quiere leer alguien cuyo `flutter run` no arrancó. Tirar estas líneas
/// dejaría un fallo sin ninguna pista.
class RegistroDelDaemon extends MensajeDelDaemon {
  const RegistroDelDaemon(this.texto);

  final String texto;
}

/// Lo que está compilando ahora mismo, para poder decirlo.
class ProgresoDelDaemon {
  const ProgresoDelDaemon({required this.id, required this.mensaje, this.tipo});

  final String id;
  final String mensaje;
  final String? tipo;
}
