import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/platform/herramienta_externa.dart';
import 'package:nexus/features/emulators/domain/entities/emulador.dart';
import 'package:nexus/features/run/data/datasources/corrida_viva.dart';
import 'package:nexus/features/run/data/datasources/el_canal_del_vm_service.dart';
import 'package:nexus/features/run/domain/entities/corrida.dart';
import 'package:nexus/features/run/domain/entities/mensaje_del_daemon.dart';
import 'package:nexus/features/run/domain/usecases/decision_de_recarga.dart';
import 'package:nexus/features/run/domain/usecases/el_error_que_pinta_la_app.dart';
import 'package:nexus/features/run/domain/usecases/el_freno_de_la_app.dart';
import 'package:nexus/features/run/domain/usecases/estado_de_la_corrida.dart';
import 'package:nexus/features/run/presentation/providers/la_consola_que_se_abre.dart';

/// Lo que está corriendo, por dispositivo.
///
/// **Un mapa y no una sola corrida**, porque tener la app en dos sitios a la vez
/// es el caso que se quiere: ver el mismo cambio en Android y en iOS sin lanzar
/// dos veces. Lo que no se puede es dos de la misma plataforma — ver
/// [loQueBloquea].
class CorridasController extends Notifier<Map<String, Corrida>> {
  final _vivas = <String, CorridaViva>{};

  /// El progreso llega con ids que se solapan, así que cada corrida lleva su
  /// mapa. Fuera del estado a propósito: es contabilidad del protocolo y no algo
  /// que la pantalla tenga que mirar.
  final _progresos = <String, Map<String, ProgresoDelDaemon>>{};

  /// El oído puesto en los errores de cada app, cuando ya dijo por dónde
  /// escucharla. Uno por corrida, y se cierra con ella.
  final _oidos = <String, ElCanalDelVmService>{};

  @override
  Map<String, Corrida> build() => const {};

  /// Lanza la app. `null` si arrancó; el motivo si no.
  Future<String?> correr({
    required String proyecto,
    required String configuracion,
    required List<String> args,
    required String deviceId,
    required String dispositivo,
    required PlataformaEmulador plataforma,
  }) async {
    if (state.containsKey(deviceId)) {
      return 'Ya está corriendo en ese dispositivo';
    }

    // **Se corta aquí y no al fallar la compilación.** Dos corridas de la misma
    // plataforma comparten el directorio de build y se pisan; enterarse por el
    // error de Gradle cuesta tres minutos y no apunta a su causa.
    if (loQueBloquea(state.values, plataforma) case final otra?) {
      return 'Ya hay una corrida de ${plataforma.name} en ${otra.dispositivo}';
    }

    final flutter = await HerramientaExterna.donde(
      'flutter',
      candidatos: HerramientaExterna.candidatosDeFlutter(
        Platform.environment['HOME'] ?? '',
      ),
    );
    if (flutter == null) return 'No se encontró Flutter';

    state = {
      ...state,
      deviceId: Corrida(
        deviceId: deviceId,
        dispositivo: dispositivo,
        proyecto: proyecto,
        configuracion: configuracion,
        plataforma: plataforma,
      ),
    };

    // **Lo dice la configuración, no una lista nuestra de proyectos.** Si trae
    // el flag encendido hay consola que abrir; si no, no se hace nada y no se
    // mira ni una línea.
    final consola = ref.read(laConsolaQueSeAbreProvider)
      ..alArrancar(deviceId: deviceId, args: args);

    final viva = await CorridaViva.arrancar(
      flutter: flutter,
      proyecto: proyecto,
      deviceId: deviceId,
      args: args,
      onEvento: (evento) => _aplica(deviceId, evento),
      onRegistro: (linea) {
        ref.read(registrosProvider.notifier).anota(deviceId, linea);
        // Los errores que **sí** salen por stdout —la excepción asíncrona sin
        // dueño— también cuentan: son de la app igual que los del framework, y
        // hasta ahora se leían en gris entre las líneas de Gradle.
        _sumaErrores(deviceId, ElErrorQuePintaLaApp.cuantosErrores(linea));
        unawaited(consola.alVerLaLinea(deviceId, linea));
      },
      onFin: (motivo) => _termina(deviceId, motivo),
    );

    if (viva == null) {
      _termina(deviceId, 'No se pudo lanzar flutter run');
      return 'No se pudo lanzar flutter run';
    }
    _vivas[deviceId] = viva;
    return null;
  }

  /// Recargar. Sin [deviceId] va a **todas** las corridas, que es el sentido de
  /// tener la app en dos sitios: ver el mismo cambio en los dos.
  ///
  /// El resultado es por dispositivo porque una recarga puede fallar en uno y no
  /// en otro, y un «falló» a secas no diría dónde.
  Future<Map<String, ({bool ok, String? error})>> recargar({
    String? deviceId,
    bool completa = false,
  }) async {
    final destinos = deviceId == null
        ? _vivas.keys.toList()
        : [if (_vivas.containsKey(deviceId)) deviceId];

    final resultados = <String, ({bool ok, String? error})>{};
    for (final id in destinos) {
      // La cuenta se pone a cero **al pedir la recarga**, igual que hace el
      // framework con su `errorsSinceReload`: lo que dice el número es si lo
      // que tienes delante está roto, no cuántas veces lo estuvo. Antes de
      // esperar el resultado, que es cuando se ve el cambio en la fila.
      _cambia(id, (c) => c.copyWith(errores: 0));
      resultados[id] = await _vivas[id]!.recargar(completa: completa);
    }
    return resultados;
  }

  /// Un encargo acabó de tocar [proyecto]: decide qué hacer y lo hace.
  ///
  /// **Solo si el interruptor está puesto y hay algo corriendo de ese proyecto.**
  /// Lo que decide es [QueHacerConElCambio], que mira las rutas y las líneas del
  /// diff; el motivo se anota en el registro de la corrida porque «reinicié en
  /// vez de recargar» sin explicación parece un capricho de la herramienta.
  ///
  /// Cuando hace falta recompilar **no se recompila**: son minutos y aquí hay
  /// alguien esperando, que es el mismo criterio que ya usan los comandos
  /// bloqueados. Se dice y se deja la decisión en quien mira.
  Future<void> alTerminarUnEncargo({
    required String proyecto,
    required List<String> rutas,
    required String diff,
  }) async {
    final mias = state.values.where((c) => c.proyecto == proyecto).toList();
    if (mias.isEmpty) return;

    final decision = QueHacerConElCambio.decide(rutas: rutas, diff: diff);
    final registros = ref.read(registrosProvider.notifier);
    final porque = decision.motivo == null ? '' : ' — ${decision.motivo}';

    for (final corrida in mias) {
      switch (decision.que) {
        case QueHacer.recompilar:
          registros.anota(
            corrida.deviceId,
            'recarga automática: hay que recompilar$porque',
          );
        case QueHacer.reiniciar:
          registros.anota(
            corrida.deviceId,
            'recarga automática: reiniciando$porque',
          );
          await recargar(deviceId: corrida.deviceId, completa: true);
        case QueHacer.recargar:
          registros.anota(corrida.deviceId, 'recarga automática: recargando');
          await recargar(deviceId: corrida.deviceId);
      }
    }
  }

  /// Parar una corrida.
  Future<String?> parar(String deviceId) async {
    final viva = _vivas[deviceId];
    if (viva == null) return null;

    _cambia(deviceId, (c) => c.copyWith(estado: EstadoDeCorrida.parando));
    final r = await viva.parar();
    return r.error;
  }

  /// Apunta en la corrida que su consola está en [puerto].
  ///
  /// Lo llama [LaConsolaQueSeAbre], que es quien mira las líneas: aquí solo se
  /// guarda, porque el dato es de la corrida y el mapa es de esta clase.
  void apuntaLaConsola(String deviceId, int puerto) =>
      _cambia(deviceId, (c) => c.copyWith(consola: puerto));

  void _aplica(String deviceId, EventoDelDaemon evento) {
    final actual = state[deviceId];
    if (actual == null) return;

    final resultado = aplicaEvento(
      actual,
      _progresos[deviceId] ?? const {},
      evento,
    );
    if (resultado.termino) {
      _termina(deviceId, null);
      return;
    }
    _progresos[deviceId] = resultado.progresos;
    state = {...state, deviceId: resultado.corrida};

    // 🔴 **El sitio donde se engancha el oído.** La corrida acaba de decir por
    // dónde se le puede hablar —`app.debugPort` trae el `wsUri`— y es la única
    // vez que lo dice. Sin esto, los errores del framework no llegan a ninguna
    // parte: en modo máquina `flutter run` no los imprime, porque da por hecho
    // que quien escucha es un IDE. Ver [ElErrorQuePintaLaApp].
    final url = resultado.corrida.url;
    if (ElErrorQuePintaLaApp.sePuedeOir(url) && !_oidos.containsKey(deviceId)) {
      unawaited(_escuchaErrores(deviceId, url!));
    }
  }

  Future<void> _escuchaErrores(String deviceId, String url) async {
    // Se reserva el sitio antes de conectar: el evento puede llegar dos veces
    // —`app.debugPort` y `app.webLaunchUrl` cuentan lo mismo— y dos sockets al
    // mismo VM service enseñarían cada error por duplicado.
    final registros = ref.read(registrosProvider.notifier);
    final canal = await ElCanalDelVmService.abrir(
      url,
      alOirUnError: (error) {
        registros.anota(deviceId, error);
        // Uno por evento, no por línea: el bloque del framework son treinta
        // líneas de un solo error.
        _sumaErrores(deviceId, 1);
      },
      // El mismo socket lleva las paradas: es el mismo VM service y abrir otro
      // sería tener dos cables al mismo sitio. Ver [ElFrenoDeLaApp].
      alPararse: (parada) => unawaited(_seParo(deviceId, parada)),
      alSeguir: (_) => _cambia(deviceId, (c) => c.copyWith(limpiaParada: true)),
    );
    if (canal == null) return;
    // Si la corrida se murió mientras se conectaba, este socket ya no es de
    // nadie: se cierra en vez de quedarse abierto contra una app que no está.
    if (!state.containsKey(deviceId)) {
      unawaited(canal.cerrar());
      return;
    }
    _oidos[deviceId] = canal;
  }

  /// Pone o quita el freno de las excepciones.
  ///
  /// **Se pone en todos los isolates y no solo en el principal.** Una app de
  /// Flutter corre varios —el de la interfaz y los que arranque el código— y una
  /// excepción sin dueño en el de al lado se perdería igual que antes: ponerlo
  /// solo en el primero es prometer un freno que a veces no está.
  Future<void> frenar(String deviceId, {ModoDePausa? cuando}) async {
    final corrida = state[deviceId];
    final canal = _oidos[deviceId];
    if (corrida == null || canal == null) return;

    // Sin decir cuál, se alterna: es lo que hace el botón.
    final modo =
        cuando ??
        (corrida.freno == ModoDePausa.ninguna
            ? ModoDePausa.sinDueno
            : ModoDePausa.ninguna);

    final quienes = ElFrenoDeLaApp.losIsolates(
      await canal.pedir(ElFrenoDeLaApp.pedirLosIsolates),
    );
    if (quienes.isEmpty) return;
    for (final isolate in quienes) {
      await canal.pedir(
        (id) => ElFrenoDeLaApp.frenar(id, isolate: isolate, cuando: modo),
      );
    }
    _cambia(
      deviceId,
      (c) => c.copyWith(
        freno: modo,
        // Quitar el freno con la app parada la deja parada, y entonces el botón
        // de seguir es el único que queda. Se suelta aquí para no dejar a nadie
        // sin salida.
        limpiaParada: modo == ModoDePausa.ninguna,
      ),
    );
    if (modo == ModoDePausa.ninguna && corrida.parada != null) {
      await _seguirDeVerdad(canal, corrida.parada!.isolate);
    }
  }

  /// Que siga. Con [paso], hasta la línea siguiente en vez de hasta el próximo
  /// motivo para pararse.
  Future<void> seguir(String deviceId, {PasoDelDepurador? paso}) async {
    final parada = state[deviceId]?.parada;
    final canal = _oidos[deviceId];
    if (parada == null || canal == null) return;
    await _seguirDeVerdad(canal, parada.isolate, paso: paso);
  }

  /// 🔴 **La parada se borra con el evento `Resume`, no al pedirlo.** Borrarla
  /// aquí sería decir que la app sigue porque se lo pedimos: si el VM service no
  /// contesta —o contesta un error—, la app está parada y la fila diría que no.
  /// Quien lo cuenta es el propio depurador.
  Future<void> _seguirDeVerdad(
    ElCanalDelVmService canal,
    String isolate, {
    PasoDelDepurador? paso,
  }) => canal.pedir(
    (id) => ElFrenoDeLaApp.seguir(id, isolate: isolate, paso: paso),
  );

  /// La app se paró: se apunta dónde, y se traduce la posición a una línea.
  ///
  /// **Dos pasos porque el evento no trae la línea**: trae una posición en la
  /// tabla del script, y traducirla pide el script. Se enseña primero lo que ya
  /// se sabe —el archivo y la función— y la línea se añade cuando llega: una
  /// parada que tarda medio segundo en aparecer se lee como que no funcionó.
  Future<void> _seParo(String deviceId, LaParadaDeLaApp parada) async {
    _cambia(deviceId, (c) => c.copyWith(parada: parada));

    final canal = _oidos[deviceId];
    final script = parada.scriptId;
    if (canal == null || script == null || parada.posicion == null) return;
    final linea = ElFrenoDeLaApp.laLineaDeLaPosicion(
      await canal.pedir(
        (id) => ElFrenoDeLaApp.pedirElScript(
          id,
          isolate: parada.isolate,
          script: script,
        ),
      ),
      parada.posicion,
    );
    if (linea == null) return;
    _cambia(deviceId, (c) {
      // Si mientras se traducía la app siguió y se paró en otro sitio, esta
      // línea es de la parada de antes y colgarla sería mentir.
      if (c.parada?.posicion != parada.posicion) return c;
      return c.copyWith(parada: parada.conLaLinea(linea));
    });
  }

  void _sumaErrores(String deviceId, int cuantos) {
    if (cuantos <= 0) return;
    _cambia(deviceId, (c) => c.copyWith(errores: c.errores + cuantos));
  }

  void _cambia(String deviceId, Corrida Function(Corrida) como) {
    final actual = state[deviceId];
    if (actual == null) return;
    state = {...state, deviceId: como(actual)};
  }

  void _termina(String deviceId, String? motivo) {
    // El registro **no** se borra aquí: si algo se cayó, ahí está el motivo, y
    // tirarlo justo al caerse es quitarle la prueba a quien va a mirarla.
    _vivas.remove(deviceId);
    _progresos.remove(deviceId);
    // El oído también se va con la corrida: un socket abierto contra un VM
    // service que ya no existe es un descriptor suelto por cada app que se para.
    if (_oidos.remove(deviceId) case final oido?) unawaited(oido.cerrar());
    // El túnel se va con la corrida: sin app al otro lado no lleva a ninguna
    // parte, y uno huérfano por corrida se acumula en el daemon de `adb`.
    unawaited(ref.read(laConsolaQueSeAbreProvider).alTerminar(deviceId));
    if (motivo != null) {
      // Se deja el motivo a la vista quitando la corrida: la fila desaparece y el
      // error queda donde se lea. Guardar una corrida muerta en el mapa haría que
      // el bloqueo de plataforma siguiera contándola.
      _ultimoError = motivo;
    }
    state = {...state}..remove(deviceId);
  }

  String? _ultimoError;

  /// El último motivo por el que se cayó algo, para poder decirlo una vez.
  String? tomaElUltimoError() {
    final motivo = _ultimoError;
    _ultimoError = null;
    return motivo;
  }
}

/// Lo que ha impreso cada corrida: el compilador, Gradle, la app.
///
/// **Estado observable y no una lista dentro del controlador**, que es lo que
/// era: así no se podía enseñar, porque nadie se enteraba de que llegó una línea.
/// Aparte de [corridasProvider] a propósito — una línea de registro no cambia el
/// estado de la corrida, y meterla ahí obligaría a reconstruir la fila entera
/// por cada línea de Gradle.
class RegistrosController extends Notifier<Map<String, List<String>>> {
  /// Las últimas y no todas. Un `flutter run` de un proyecto grande escupe miles,
  /// y guardarlas todas es una fuga de memoria con forma de función útil. Lo que
  /// se lee cuando algo falla son las de abajo.
  static const tope = 200;

  @override
  Map<String, List<String>> build() => const {};

  void anota(String deviceId, String linea) {
    // Gradle imprime bloques con saltos dentro: se parten para que el panel
    // enseñe líneas y no párrafos.
    final nuevas = [
      for (final l in linea.split('\n'))
        if (l.trim().isNotEmpty) l.trimRight(),
    ];
    if (nuevas.isEmpty) return;

    final actual = state[deviceId] ?? const <String>[];
    final juntas = [...actual, ...nuevas];
    state = {
      ...state,
      deviceId: juntas.length > tope
          ? juntas.sublist(juntas.length - tope)
          : juntas,
    };
  }

  void limpia(String deviceId) => state = {...state}..remove(deviceId);
}

final registrosProvider =
    NotifierProvider<RegistrosController, Map<String, List<String>>>(
      RegistrosController.new,
    );

final corridasProvider =
    NotifierProvider<CorridasController, Map<String, Corrida>>(
      CorridasController.new,
    );
