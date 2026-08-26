import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/artifacts/presentation/providers/artifacts_providers.dart';
import 'package:nexus/features/e2e/data/datasources/e2e_data_source.dart';
import 'package:nexus/features/e2e/domain/entities/corrida_de_prueba.dart';
import 'package:nexus/features/e2e/domain/usecases/donde_viven_las_corridas.dart';
import 'package:nexus/features/e2e/domain/usecases/la_corrida_como_html.dart';
import 'package:nexus/features/e2e/domain/usecases/pasos_de_una_prueba.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

final e2eDataSourceProvider = Provider<E2eDataSource>(
  (ref) => const E2eDataSource(),
);

/// Dónde guarda Nexus las corridas.
///
/// **En la carpeta de documentos del usuario, en `test/`.** Antes iban a
/// Application Support, donde nadie las ve; ahí van al lado de lo que escribe
/// Claude y se pueden abrir y borrar sin la app.
///
/// Si todavía no hay carpeta de documentos elegida se cae a la de soporte, por lo
/// mismo que la lista de documentos empieza vacía: **escribir en el disco del
/// usuario en un sitio que él no ha elegido es exactamente lo que no se hace
/// aquí.**
final raizDePruebasProvider = FutureProvider<String>((ref) async {
  final documentos = ref.watch(artifactsFolderProvider);
  if (documentos != null && documentos.isNotEmpty) {
    return '$documentos/${DondeVivenLasCorridas.carpeta}';
  }
  return E2eDataSource.raiz();
});

/// Las pruebas de un proyecto. Familia por carpeta: un `.maestro/` es de su repo
/// y de ninguno más.
final pruebasProvider = FutureProvider.family<List<Prueba>, String>(
  (ref, proyecto) => ref.watch(e2eDataSourceProvider).pruebasDe(proyecto),
);

/// Todas las corridas: las que lanzó Nexus y las que no.
///
/// **Las dos fuentes en una sola lista, con su procedencia marcada.** Un panel
/// con dos secciones «las mías» y «las otras» le pasaría al usuario un problema
/// nuestro: a él le da igual quién lanzó, quiere ver qué pasó.
///
/// Sin `autoDispose` y refrescando al abrir, por lo aprendido con los
/// dispositivos: guardar el valor **y** volver a preguntar. Con una sola de las
/// dos cosas se elige entre mentir y parpadear.
final corridasDePruebaProvider = FutureProvider<List<CorridaDePrueba>>((
  ref,
) async {
  final ds = ref.watch(e2eDataSourceProvider);
  final raiz = await ref.watch(raizDePruebasProvider.future);

  // Las pruebas de cada carpeta emparejada, que es lo que permite atribuir las
  // corridas ajenas por nombre de flow.
  final carpetas = ref
      .watch(workspaceControllerProvider)
      .folders
      .map((f) => f.workingDirectory)
      .toSet();
  final pruebasPorProyecto = <String, List<String>>{};
  for (final carpeta in carpetas) {
    final pruebas = await ds.pruebasDe(carpeta);
    if (pruebas.isNotEmpty) {
      pruebasPorProyecto[carpeta] = [for (final p in pruebas) p.nombre];
    }
  }

  final propias = await ds.propias(raiz);
  final ajenas = await ds.ajenas(pruebasPorProyecto);

  // Lo último arriba: lo que acabas de correr es lo que vas a querer mirar.
  return [...propias, ...ajenas]
    ..sort((a, b) => b.cuando.compareTo(a.cuando));
});

/// Una prueba corriendo ahora mismo.
class PruebaEnMarcha {
  const PruebaEnMarcha({
    required this.flow,
    required this.pasos,
    this.terminados = 0,
    this.lineas = const [],
    this.viva = true,
    this.fallo = false,
    this.error,
  });

  final String flow;

  /// Los pasos del YAML, con su número y sus argumentos, para poder pintarlos
  /// como están escritos.
  final List<PasoDelFlow> pasos;

  final int terminados;

  /// La salida cruda, que es a lo que se degrada la vista cuando los pasos
  /// impresos no cuadran con el archivo.
  final List<String> lineas;

  final bool viva;
  final bool fallo;
  final String? error;

  /// El estado de cada paso, o `null` si ya no se puede emparejar.
  List<EstadoDePaso>? get estados => PasosDeUnaPrueba.estados(
    cuantosPasos: pasos.length,
    terminados: terminados,
    viva: viva,
    fallo: fallo,
  );
}

/// Lanzar una prueba y seguirla.
///
/// **Una a la vez**, y no por simplificar: dos corridas de Maestro sobre el mismo
/// dispositivo se pelean por su driver, y sobre dispositivos distintos ya está
/// bien pero nadie lo ha pedido. Cuando haga falta, esto pasa a ser un mapa como
/// el de las corridas de la app.
class PruebaEnMarchaController extends Notifier<PruebaEnMarcha?> {
  Process? _proceso;

  /// Si la ventana de esta corrida ya está abierta.
  var _ventanaAbierta = false;

  /// Con qué se lanzó, para poder anotarlo al terminar.
  ({String raiz, String perfil, String proyecto, String dispositivo, DateTime cuando})?
  _contexto;

  @override
  PruebaEnMarcha? build() {
    // **El botón de detener de la ventana llega por aquí.** La página es estática
    // y su botón un enlace `nexus://parar`; el visor lo intercepta y lo reenvía a
    // este canal. Se escucha una sola vez, al construirse el controlador.
    _visor.setMethodCallHandler((llamada) async {
      if (llamada.method != 'desdeLaPagina') return null;
      final que = (llamada.arguments as Map?)?['que'];
      if (que == 'parar') parar();
      return null;
    });
    return null;
  }

  /// El mismo canal del visor: es su ventana la que habla.
  static const _visor = MethodChannel('com.katanalabs.nexus/artifacts');

  /// Lanza [prueba] en [deviceId]. `null` si arrancó.
  Future<String?> lanzar({
    required Prueba prueba,
    required String proyecto,
    required String deviceId,
    required String perfil,
  }) async {
    if (state?.viva ?? false) return 'Ya hay una prueba corriendo';

    final raiz = await ref.read(raizDePruebasProvider.future);
    // Maestro escribe su propio ruido en `.maestro/tests` dentro de esta carpeta,
    // que empieza por punto y no estorba a lo que sí se mira.
    final salida = DondeVivenLasCorridas.de(raiz: raiz, proyecto: proyecto);

    // El YAML se lee ahora: es lo que se pinta, y leerlo después sería pintar los
    // pasos de una versión que igual ya cambió.
    final yaml = await _leer(prueba.ruta);
    _ventanaAbierta = false;
    _contexto = (
      raiz: raiz,
      perfil: perfil,
      proyecto: proyecto,
      dispositivo: deviceId,
      cuando: DateTime.now(),
    );
    state = PruebaEnMarcha(
      flow: prueba.nombre,
      pasos: PasosDeUnaPrueba.leer(yaml),
    );
    await _pinta();

    final proceso = await ref
        .read(e2eDataSourceProvider)
        .lanzar(
          flow: prueba.ruta,
          proyecto: proyecto,
          deviceId: deviceId,
          salida: salida,
        );
    if (proceso == null) {
      state = null;
      return 'No se encontró Maestro, o no se pudo lanzar';
    }
    _proceso = proceso;

    var resto = '';
    proceso.stdout.transform(utf8.decoder).listen((trozo) {
      resto += trozo;
      final corte = resto.lastIndexOf('\n');
      if (corte < 0) return;
      final nuevas = [
        for (final l in resto.substring(0, corte).split('\n'))
          if (l.trim().isNotEmpty) l.trimRight(),
      ];
      resto = resto.substring(corte + 1);
      _anota(nuevas);
    });
    // stderr también: ahí sale lo del driver cuando no se puede instalar.
    proceso.stderr
        .transform(utf8.decoder)
        .listen((t) => _anota([t.trimRight()]));

    unawaited(
      proceso.exitCode.then((codigo) {
        _proceso = null;
        final actual = state;
        if (actual == null) return;
        state = PruebaEnMarcha(
          flow: actual.flow,
          pasos: actual.pasos,
          terminados: actual.terminados,
          lineas: actual.lineas,
          viva: false,
          fallo: actual.fallo || codigo != 0,
        );
        unawaited(_pinta());
        unawaited(_dejaConstancia());
      }),
    );
    return null;
  }

  /// Cortar una prueba a medias.
  void parar() {
    _proceso?.kill();
    _proceso = null;
  }

  void _anota(List<String> nuevas) {
    final actual = state;
    if (actual == null || nuevas.isEmpty) return;

    final lineas = [...actual.lineas, ...nuevas];
    final avance = PasosDeUnaPrueba.avance(lineas);
    state = PruebaEnMarcha(
      flow: actual.flow,
      pasos: actual.pasos,
      terminados: avance.terminados,
      lineas: lineas,
      fallo: avance.fallo,
    );
    unawaited(_pinta());
  }

  /// Reescribe la página de la corrida. La ventana se recarga sola al verla
  /// cambiar, así que esto es todo lo que hace falta para que siga en vivo.
  Future<void> _pinta() async {
    final actual = state;
    if (actual == null) return;

    await ref
        .read(e2eDataSourceProvider)
        .pintaLaCorrida(
          flow: actual.flow,
          html: LaCorridaComoHtml.escribe(
            flow: actual.flow,
            pasos: actual.pasos,
            estados: actual.estados,
            lineas: actual.lineas,
            terminados: actual.terminados,
            viva: actual.viva,
            fallo: actual.fallo,
          ),
          primeraVez: !_ventanaAbierta,
          raizDeLaVentana: _contexto?.raiz ?? await ref.read(raizDePruebasProvider.future),
        );
    _ventanaAbierta = true;
  }

  /// Deja constancia de lo que pasó, y refresca el historial.
  ///
  /// Se anota lo que Nexus leyó de la salida y no lo que escriba Maestro: su
  /// carpeta del flow no siempre llega —medido— y sin esto una corrida que pasó
  /// entera desaparecía del historial.
  Future<void> _dejaConstancia() async {
    final actual = state;
    final ctx = _contexto;
    if (actual == null || ctx == null) return;

    await ref
        .read(e2eDataSourceProvider)
        .anotaLaCorrida(
          raiz: ctx.raiz,
          perfil: ctx.perfil,
          proyecto: ctx.proyecto,
          corrida: {
            'flow': actual.flow,
            'cuando': ctx.cuando.toIso8601String(),
            'pasos': actual.pasos.length,
            // **Los nombres y no solo cuántos.** Sin ellos, el informe de una
            // corrida guardada no tenía qué pintar y solo podía enseñar la salida
            // cruda: los pasos con su ✓ son justo lo que se va a mirar.
            // Con su número y su detalle: el informe pinta lo mismo que la vista
            // en vivo, y para eso necesita el mismo dato y no un resumen.
            'pasosDelFlow': [
              for (final p in actual.pasos)
                {'n': p.linea, 't': p.texto, 'd': p.detalle},
            ],
            'terminados': actual.terminados,
            'fallo': actual.fallo,
            'dispositivo': ctx.dispositivo,
            // La salida, acotada: lo que se lee cuando algo falla son las últimas.
            'lineas': actual.lineas.length > 200
                ? actual.lineas.sublist(actual.lineas.length - 200)
                : actual.lineas,
          },
        );
    ref.invalidate(corridasDePruebaProvider);
  }

  /// Volver a traer la ventana al frente, para el botón «Ver».
  Future<void> traeLaVentana() async {
    _ventanaAbierta = false;
    await _pinta();
  }

  Future<String> _leer(String ruta) async {
    try {
      return await File(ruta).readAsString();
    } on FileSystemException {
      return '';
    }
  }
}

final pruebaEnMarchaProvider =
    NotifierProvider<PruebaEnMarchaController, PruebaEnMarcha?>(
      PruebaEnMarchaController.new,
    );
