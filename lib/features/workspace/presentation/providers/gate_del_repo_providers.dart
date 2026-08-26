import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/workspace/data/datasources/gate_del_repo_data_source.dart';
import 'package:nexus/features/workspace/data/datasources/git_data_source.dart';
import 'package:nexus/features/workspace/presentation/providers/plan_firmado_providers.dart';

final gateDelRepoDataSourceProvider = Provider<GateDelRepoDataSource>(
  (ref) => const GateDelRepoDataSource(),
);

/// El árbol de esa carpeta ahora mismo, para saber si un verde sigue cubriéndolo.
///
/// Se pide aparte y no dentro del gate porque cambia por su cuenta: el modelo escribe
/// archivos mientras la corrida está guardada, y esto es lo que hace que el verde deje de
/// valer sin que nadie tenga que acordarse de invalidarlo.
final huellaDelArbolProvider = FutureProvider.family<String?, String>(
  (ref, carpeta) => const GitDataSource().huellaDelArbol(carpeta),
);

/// El gate de una carpeta en una rama, y el botón para correrlo.
class GateDelRepoController extends AsyncNotifier<GateDelRepo> {
  GateDelRepoController(this.donde);

  final DondeMirar donde;

  @override
  Future<GateDelRepo> build() => ref
      .read(gateDelRepoDataSourceProvider)
      .leer(donde.configDir, donde.carpeta, rama: donde.rama);

  /// Corre el gate declarado y guarda cómo salió.
  ///
  /// El estado pasa por `corriendo` en memoria: es lo único que distingue «tarda» de «no
  /// pasó nada», y un gate tarda minutos. No se guarda en disco a propósito — si la app
  /// se cierra a mitad, al volver está como estaba y no como si algo siguiera corriendo.
  ///
  /// **La huella se toma antes de correr, no después.** Al terminar, el árbol puede haber
  /// cambiado —el gate mismo genera archivos, o el modelo siguió trabajando— y guardar la
  /// de después diría que el verde cubre cosas que nunca se probaron.
  Future<void> correr() async {
    final gate = state.value;
    if (gate == null || gate.comando == null) return;
    if (gate.resultado == ResultadoDelGate.corriendo) return;

    state = AsyncData(gate.copyWith(resultado: ResultadoDelGate.corriendo));
    final huella = await ref.read(huellaDelArbolProvider(donde.carpeta).future);
    final resultado = await ref
        .read(gateDelRepoDataSourceProvider)
        .correr(donde.configDir, gate, huella: huella);
    // La huella se relee porque correr el gate puede haber tocado el árbol: sin esto, un
    // gate que genera código se quedaría enseñando «cambió después» nada más terminar.
    ref.invalidate(huellaDelArbolProvider(donde.carpeta));
    state = AsyncData(resultado);
  }

  /// Registra que el gate lo corrió una persona, con la salida que pegó.
  ///
  /// La huella se toma **ahora**, como al correrlo: lo que se está declarando es que este
  /// árbol pasa, y atarlo a otro dejaría la afirmación cubriendo cambios que nadie vio.
  Future<void> declarar(String salida) async {
    final gate = state.value;
    if (gate == null || gate.comando == null) return;
    final huella = await ref.read(huellaDelArbolProvider(donde.carpeta).future);
    state = AsyncData(
      await ref
          .read(gateDelRepoDataSourceProvider)
          .declarar(donde.configDir, gate, salida: salida, huella: huella),
    );
  }

  /// Deja escrito por qué se publica sin volver a correr el gate.
  ///
  /// La huella se toma **ahora**, no la de la corrida: lo que se está justificando es
  /// publicar *este* árbol, y atarlo a otro dejaría el permiso valiendo para cambios que
  /// nadie ha visto todavía.
  Future<void> publicarIgual(String motivo) async {
    final gate = state.value;
    if (gate == null) return;
    final huella = await ref.read(huellaDelArbolProvider(donde.carpeta).future);
    state = AsyncData(
      await ref
          .read(gateDelRepoDataSourceProvider)
          .publicarIgual(donde.configDir, gate, motivo: motivo, huella: huella),
    );
  }
}

final gateDelRepoProvider =
    AsyncNotifierProvider.family<
      GateDelRepoController,
      GateDelRepo,
      DondeMirar
    >(GateDelRepoController.new);
