import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/workspace/data/datasources/cierre_de_la_corrida_data_source.dart';
import 'package:nexus/features/workspace/data/datasources/gate_del_repo_data_source.dart';
import 'package:nexus/features/workspace/data/datasources/git_data_source.dart';
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

/// Una corrida en la lista, con la carpeta de la que salió y si quedó huérfana.
typedef CorridaEnLaLista = ({String carpeta, LaCorrida corrida, bool huerfana});

/// Todas las corridas anotadas en una cuenta.
///
/// **Se juntan las tres marcas y no solo los cierres**: una corrida abierta no tiene
/// cierre, y esa es justo la que uno busca al abrir una lista. Empezar por los cierres
/// habría dado una lista de cosas terminadas, que es un archivo histórico y no una mesa
/// de trabajo.
///
/// Huérfana es la que se quedó sin su rama —o sin su carpeta—: al borrar una rama, su
/// plan, su gate y su cierre se quedan anotados en la cuenta para siempre. Se marcan en
/// vez de esconderlas, porque una corrida cerrada de una rama ya mezclada es exactamente
/// lo normal y sigue valiendo para mirar cuánto costó.
final todasLasCorridasProvider =
    FutureProvider.family<List<CorridaEnLaLista>, String>((
      ref,
      configDir,
    ) async {
      final planes = ref.watch(planFirmadoDataSourceProvider);
      final gates = ref.watch(gateDelRepoDataSourceProvider);
      final cierres = ref.watch(cierresDataSourceProvider);

      final claves = <({String carpeta, String? rama})>{
        ...await planes.carpetasYRamas(configDir),
        ...await gates.carpetasYRamas(configDir),
        ...await cierres.carpetasYRamas(configDir),
      };

      const git = GitDataSource();
      final lista = <CorridaEnLaLista>[];
      for (final clave in claves) {
        final plan = await planes.leer(
          configDir,
          clave.carpeta,
          rama: clave.rama,
        );
        final gate = await gates.leer(
          configDir,
          clave.carpeta,
          rama: clave.rama,
        );
        final susCierres = await cierres.leer(
          configDir,
          clave.carpeta,
          rama: clave.rama,
        );

        lista.add((
          carpeta: clave.carpeta,
          corrida: LaCorrida(
            rama: clave.rama,
            plan: plan?.plan,
            firmado: plan?.firmado,
            gateCorrio: gate.resultado.corrio ? gate.cuando : null,
            gateVerde: switch (gate.resultado) {
              ResultadoDelGate.verde => true,
              ResultadoDelGate.rojo => false,
              _ => null,
            },
            cierres: susCierres,
          ),
          huerfana:
              !Directory(clave.carpeta).existsSync() ||
              (clave.rama != null &&
                  !await git.ramaExiste(clave.carpeta, clave.rama!)),
        ));
      }

      // Las abiertas primero y dentro por lo más reciente: una lista ordenada por fecha a
      // secas entierra lo que está vivo debajo de lo que se cerró ayer.
      lista.sort((a, b) {
        if (a.corrida.abierta != b.corrida.abierta) {
          return a.corrida.abierta ? -1 : 1;
        }
        final unaFecha = a.corrida.ultimaSenal;
        final otraFecha = b.corrida.ultimaSenal;
        if (unaFecha == null || otraFecha == null) return 0;
        return otraFecha.compareTo(unaFecha);
      });
      return lista;
    });

/// Borra una corrida entera: su firma, su gate y sus cierres.
///
/// **Es irreversible y no se ofrece salvo para las huérfanas.** Borrar la corrida de una
/// rama viva sería perder la medición de un trabajo en curso sin ningún motivo; lo que se
/// limpia es lo que ya no tiene a quién pertenecer.
class LimpiarCorridas extends Notifier<void> {
  @override
  void build() {}

  Future<void> borrar(String configDir, String carpeta, String? rama) async {
    await ref
        .read(planFirmadoDataSourceProvider)
        .borrar(configDir, carpeta, rama);
    await ref
        .read(gateDelRepoDataSourceProvider)
        .borrar(configDir, carpeta, rama);
    await ref.read(cierresDataSourceProvider).borrar(configDir, carpeta, rama);
    ref.invalidate(todasLasCorridasProvider(configDir));
  }
}

final limpiarCorridasProvider = NotifierProvider<LimpiarCorridas, void>(
  LimpiarCorridas.new,
);
