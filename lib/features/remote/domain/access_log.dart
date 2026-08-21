/// Qué pidió el móvil, con qué permiso y cuándo — la decisión 2.5 del contrato.
///
/// **Existía como `debugPrint` y eso no es un registro.** Se descubrió intentando
/// diagnosticar un teléfono que se quedaba en «reconectando»: en compilación release,
/// `debugPrint` no llega al log del sistema —medido: cero líneas en tres horas con el
/// canal encendido— así que el único sitio que sabía **por qué** se rechazaba una
/// conexión era ilegible justo cuando hacía falta.
///
/// Y hace falta porque el portero contesta **un solo 403 para todos los rechazos**, a
/// propósito: distinguirlos le diría a quien lo intenta qué comprobación pasó. El
/// motivo va aquí, que es donde lo puede leer el dueño del Mac — el único que
/// necesita depurarlo.
///
/// Append-only, porque un registro que se puede editar no sirve para lo que sirve un
/// registro.
abstract class AccessLog {
  /// Escribe una línea. No lanza nunca: un fallo al registrar no puede tumbar el
  /// canal, y menos el registro de un rechazo.
  Future<void> anotar(AccessEntry entrada);

  /// Lo último, para poder enseñarlo. El más reciente primero, que es el orden en
  /// que se lee cuando algo acaba de fallar.
  Future<List<String>> ultimas({int cuantas = 200});

  /// Dónde vive, para poder abrirlo.
  Future<String?> get ruta;
}

/// Una línea del registro.
///
/// Es un tipo y no una cadena para que **el redactado no dependa de acordarse**: quien
/// anota pasa los campos, y el formato —y lo que se omite— se decide en un solo sitio.
/// Con cadenas libres, la primera interpolación descuidada mete un secreto en el
/// registro y nadie lo ve hasta que es tarde.
class AccessEntry {
  const AccessEntry({
    required this.cuando,
    required this.que,
    this.ip,
    this.motivo,
    this.detalle,
  });

  final DateTime cuando;

  /// Qué pasó: `escuchando`, `conectado`, `rechazado`, `pidio`, `desconectado`…
  final String que;

  /// Quién. La dirección de Tailscale, que en una tailnet identifica el aparato.
  final String? ip;

  /// Por qué, cuando es un rechazo. Es el dato que el 403 no da.
  final String? motivo;

  /// Contexto adicional — el método pedido, la versión que saludó.
  final String? detalle;

  /// La línea, en un formato que se lee y se puede grepear.
  ///
  /// **Nunca lleva el token ni la frase de escritura**, y eso no es cuidado al
  /// escribir: es que aquí no hay ningún campo donde puedan entrar. Los parámetros de
  /// una petición no se registran —solo el nombre del método— justo porque por ahí
  /// pasa la frase.
  String get linea => [
    cuando.toIso8601String(),
    que,
    if (ip != null) 'ip=$ip',
    if (motivo != null) 'motivo=$motivo',
    if (detalle != null) 'detalle=$detalle',
  ].join(' · ');
}
