import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/workspace/data/datasources/cierre_de_la_corrida_data_source.dart';
import 'package:nexus/features/workspace/data/datasources/gate_del_repo_data_source.dart';
import 'package:nexus/features/workspace/domain/usecases/la_corrida.dart';
import 'package:nexus/features/workspace/presentation/providers/gate_del_repo_providers.dart';
import 'package:nexus/features/workspace/presentation/providers/plan_firmado_providers.dart';

final cierresDataSourceProvider = Provider<CierreDeLaCorridaDataSource>(
  (ref) => const CierreDeLaCorridaDataSource(),
);

final cierresProvider = FutureProvider.family<List<Cierre>, DondeMirar>(
  (ref, donde) => ref
      .watch(cierresDataSourceProvider)
      .leer(donde.configDir, donde.carpeta, rama: donde.rama),
);

/// La corrida de esta rama, armada con lo que ya escribieron los otros tres.
///
/// **Síncrono y derivado**, no un `AsyncNotifier` con estado propio: aquí no hay nada que
/// cargar que no esté cargado ya. Guardar una copia sería un cuarto sitio del que dudar
/// cuando el plan diga una cosa y esto otra.
final laCorridaProvider = Provider.family<LaCorrida, DondeMirar>((ref, donde) {
  final plan = ref.watch(planFirmadoProvider(donde)).value;
  final gate = ref.watch(gateDelRepoProvider(donde)).value;
  final cierres = ref.watch(cierresProvider(donde)).value ?? const <Cierre>[];

  return LaCorrida(
    rama: donde.rama,
    plan: plan?.plan,
    firmado: plan?.firmado,
    gateCorrio: gate != null && gate.resultado.corrio ? gate.cuando : null,
    // Nulo no es falso: «no corrió» y «salió mal» son dos cosas distintas y el resumen
    // las dice distinto.
    gateVerde: switch (gate?.resultado) {
      ResultadoDelGate.verde => true,
      ResultadoDelGate.rojo => false,
      _ => null,
    },
    cierres: cierres,
  );
});

/// Cerrar, cerrar sin producción y cancelar. Las tres apilan un cierre y ninguna publica.
class CerrarLaCorrida extends Notifier<void> {
  CerrarLaCorrida(this.donde);

  final DondeMirar donde;

  @override
  void build() {}

  Future<void> cerrar(ComoTermino como, String narrativa) async {
    // La narrativa obligatoria se hace cumplir en el origen de datos, no aquí: así vale
    // igual venga de donde venga. Esto solo evita el viaje al disco.
    if (narrativa.trim().isEmpty) return;
    await ref
        .read(cierresDataSourceProvider)
        .cerrar(
          donde.configDir,
          donde.carpeta,
          rama: donde.rama,
          como: como,
          narrativa: narrativa,
        );
    ref.invalidate(cierresProvider(donde));
  }
}

final cerrarLaCorridaProvider =
    NotifierProvider.family<CerrarLaCorrida, void, DondeMirar>(
      CerrarLaCorrida.new,
    );
