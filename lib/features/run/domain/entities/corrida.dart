import 'package:nexus/features/emulators/domain/entities/emulador.dart';

/// En qué anda una corrida.
enum EstadoDeCorrida {
  /// Compilando o instalando: el proceso vive pero la app todavía no.
  arrancando,

  /// `app.started`: ya se ve en el dispositivo y acepta recargas.
  corriendo,

  /// Se pidió parar y se está esperando.
  ///
  /// Existe para no contar como fallo un cierre limpio: el proceso va a salir
  /// con un código distinto de cero y sin este estado se reportaría como que la
  /// app se cayó.
  parando,
}

/// La app corriendo en un dispositivo.
class Corrida {
  const Corrida({
    required this.deviceId,
    required this.dispositivo,
    required this.proyecto,
    required this.configuracion,
    required this.plataforma,
    this.estado = EstadoDeCorrida.arrancando,
    this.appId,
    this.progreso,
    this.url,
    this.error,
    this.consola,
  });

  /// El `-d` con el que se lanzó. **Es la clave de todo**: una corrida por
  /// dispositivo, y por aquí se le pide recargar o parar.
  final String deviceId;

  /// Cómo se llama para una persona.
  final String dispositivo;

  final String proyecto;

  /// El nombre de la configuración del `launch.json`, para poder decir con qué
  /// entorno está corriendo. Sin esto, dos corridas iguales serían
  /// indistinguibles y la pregunta «¿esto es ci o preprod?» no tendría respuesta.
  final String configuracion;

  final PlataformaEmulador plataforma;

  final EstadoDeCorrida estado;

  /// El identificador que da `app.start`. **Sin él no se le puede pedir nada**:
  /// ni recargar ni parar llevan sentido antes de que llegue, y eso es un estado
  /// legítimo —«todavía está compilando»— y no un error.
  final String? appId;

  /// Lo que está haciendo ahora mismo, si lo dijo.
  final String? progreso;

  /// La URL del depurador, cuando la manda.
  final String? url;

  /// El puerto de la **consola de depuración de la propia app**, cuando la app
  /// dice que la abrió. Nulo es lo normal: no todas las traen, y las que la
  /// traen la apagan en la mayoría de los entornos. Ver [LaConsolaDeLaApp].
  final int? consola;

  final String? error;

  bool get puedeRecargar =>
      appId != null && estado == EstadoDeCorrida.corriendo;

  Corrida copyWith({
    EstadoDeCorrida? estado,
    String? appId,
    String? progreso,
    bool limpiaProgreso = false,
    String? url,
    String? error,
    int? consola,
  }) => Corrida(
    deviceId: deviceId,
    dispositivo: dispositivo,
    proyecto: proyecto,
    configuracion: configuracion,
    plataforma: plataforma,
    estado: estado ?? this.estado,
    appId: appId ?? this.appId,
    progreso: limpiaProgreso ? null : (progreso ?? this.progreso),
    url: url ?? this.url,
    error: error ?? this.error,
    consola: consola ?? this.consola,
  );
}

/// Qué corrida impide arrancar otra en [plataforma].
///
/// **Dos corridas de la misma plataforma comparten el directorio de build del
/// proyecto y se pisan**; cruzadas —una en Android y otra en iOS— conviven sin
/// problema. Está medido en `la-oficina`, y allí se corta antes de lanzar «para
/// no gastar minutos de compilación descubriéndolo»: el fallo llega tres minutos
/// después y no se parece a su causa.
///
/// Puro y aparte de la entidad porque es la regla, no el dato: así se prueba sin
/// arrancar nada.
Corrida? loQueBloquea(
  Iterable<Corrida> corriendo,
  PlataformaEmulador plataforma,
) {
  for (final corrida in corriendo) {
    if (corrida.plataforma == plataforma) return corrida;
  }
  return null;
}
