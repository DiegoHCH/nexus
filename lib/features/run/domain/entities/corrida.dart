import 'package:nexus/features/emulators/domain/entities/emulador.dart';
import 'package:nexus/features/run/domain/usecases/el_error_que_pinta_la_app.dart';
import 'package:nexus/features/run/domain/usecases/el_freno_de_la_app.dart';

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
    this.errores = 0,
    this.seRecarga = true,
    this.freno = ModoDePausa.ninguna,
    this.parada,
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

  /// Cuántos errores ha dado **la app** desde la última recarga.
  ///
  /// 🔴 **Está en el estado porque tiene que verse sin abrir nada.** El reporte
  /// que trajo todo esto no fue «falta una línea en el registro», fue «el error
  /// **no saltó**»: el registro es una ventana que se abre a mano, y un error que
  /// solo está ahí es un error que nadie mira. Con esto la fila de la corrida
  /// puede decirlo sola.
  ///
  /// **Desde la última recarga**, y no en total, por lo mismo que hace el
  /// framework con su `errorsSinceReload`: lo que importa es si lo que tienes
  /// delante está roto, no cuántas veces se rompió antes de arreglarlo.
  final int errores;

  /// Si esta corrida acepta recargas, **dicho por el daemon**.
  ///
  /// 🔴 **Lo dice `app.start` en `supportsRestart` y no se miraba.** En una
  /// corrida de `profile` no hay recarga ni reinicio —es de debug— así que la
  /// botonera ofrecía dos botones que no podían funcionar: pulsarlos deja un
  /// «Todavía está compilando» o un error del daemon, y aprender que un botón
  /// no sirve cuesta más que no tenerlo. Salió al hacer «prod + profile + el
  /// panel de depuración», que es una corrida de profile de verdad.
  ///
  /// Nace en `true` porque es lo que contesta el daemon en el caso normal —una
  /// corrida de debug— y porque hasta que llega `app.start` no hay nada que
  /// recargar de todas formas.
  final bool seRecarga;

  /// Si esta corrida se para cuando la app se rompe, y con qué criterio.
  ///
  /// **Nace en [ModoDePausa.ninguna] a propósito.** Pararse solo es lo que hace
  /// un depurador conectado, y aquí no lo hay hasta que alguien lo pide: una app
  /// que se congela sin haberlo pedido se lee como que se colgó.
  final ModoDePausa freno;

  /// Donde está parada ahora mismo, si lo está. Ver [LaParadaDeLaApp].
  final LaParadaDeLaApp? parada;

  /// Se le puede pedir el freno: hay VM service al que hablarle y la app está
  /// arriba. Antes de `app.started` no hay isolates a los que ponerle nada.
  bool get sePuedeFrenar =>
      ElErrorQuePintaLaApp.sePuedeOir(url) &&
      estado == EstadoDeCorrida.corriendo;

  bool get puedeRecargar =>
      seRecarga && appId != null && estado == EstadoDeCorrida.corriendo;

  Corrida copyWith({
    EstadoDeCorrida? estado,
    String? appId,
    String? progreso,
    bool limpiaProgreso = false,
    String? url,
    String? error,
    int? consola,
    int? errores,
    bool? seRecarga,
    ModoDePausa? freno,
    LaParadaDeLaApp? parada,
    bool limpiaParada = false,
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
    errores: errores ?? this.errores,
    seRecarga: seRecarga ?? this.seRecarga,
    freno: freno ?? this.freno,
    // Igual que el progreso: **borrarla es un caso**, y sin una bandera propia
    // no se distingue de «déjala como está». Una parada que no se borra al
    // reanudar deja la fila diciendo «parada en gate.dart:78» con la app
    // corriendo, que es peor que no decir nada.
    parada: limpiaParada ? null : (parada ?? this.parada),
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
