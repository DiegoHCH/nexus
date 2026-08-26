import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/e2e/data/datasources/e2e_data_source.dart';
import 'package:nexus/features/e2e/domain/entities/corrida_de_prueba.dart';
import 'package:nexus/features/e2e/domain/usecases/donde_viven_las_corridas.dart';
import 'package:nexus/features/e2e/domain/usecases/pasos_de_una_prueba.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

final e2eDataSourceProvider = Provider<E2eDataSource>(
  (ref) => const E2eDataSource(),
);

/// Dónde guarda Nexus lo suyo. Se pregunta una vez.
final raizDePruebasProvider = FutureProvider<String>(
  (ref) => E2eDataSource.raiz(),
);

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

  /// Los pasos del YAML, para poder pintarlos con su estado.
  final List<String> pasos;

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

  @override
  PruebaEnMarcha? build() => null;

  /// Lanza [prueba] en [deviceId]. `null` si arrancó.
  Future<String?> lanzar({
    required Prueba prueba,
    required String proyecto,
    required String deviceId,
    required String perfil,
  }) async {
    if (state?.viva ?? false) return 'Ya hay una prueba corriendo';

    final raiz = await ref.read(raizDePruebasProvider.future);
    final salida = DondeVivenLasCorridas.paraLanzar(
      raiz: raiz,
      perfil: perfil,
      proyecto: proyecto,
    );

    // El YAML se lee ahora: es lo que se pinta, y leerlo después sería pintar los
    // pasos de una versión que igual ya cambió.
    final yaml = await _leer(prueba.ruta);
    state = PruebaEnMarcha(
      flow: prueba.nombre,
      pasos: PasosDeUnaPrueba.leer(yaml),
    );

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
        // Y la lista de corridas ya tiene una más.
        ref.invalidate(corridasDePruebaProvider);
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
