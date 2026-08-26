import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/workspace/data/datasources/cierre_de_la_corrida_data_source.dart';
import 'package:nexus/features/workspace/data/datasources/gate_del_repo_data_source.dart';
import 'package:nexus/features/assistant/presentation/providers/assistant_controller.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/workspace/data/datasources/git_data_source.dart';
import 'package:nexus/features/workspace/data/datasources/revision_data_source.dart';
import 'package:nexus/features/workspace/domain/usecases/el_encargo_de_revisar.dart';
import 'package:nexus/features/workspace/domain/usecases/reglas_declaradas.dart';
import 'package:nexus/features/workspace/domain/usecases/la_corrida.dart';
import 'package:nexus/features/workspace/presentation/providers/gate_del_repo_providers.dart';
import 'package:nexus/features/workspace/presentation/providers/plan_firmado_providers.dart';

final revisionDataSourceProvider = Provider<RevisionDataSource>(
  (ref) => const RevisionDataSource(),
);

final revisionProvider = FutureProvider.family<Revision?, DondeMirar>(
  (ref, donde) => ref
      .watch(revisionDataSourceProvider)
      .leer(donde.configDir, donde.carpeta, rama: donde.rama),
);

/// Los archivos que la rama lleva tocados. Es lo que se revisa y, de paso, lo que se
/// enseña mientras se construye: «llevas tocados cuatro» dice más que un cronómetro.
final archivosTocadosProvider = FutureProvider.family<List<String>, String>(
  (ref, carpeta) => const GitDataSource().archivosTocados(carpeta),
);

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
    gateDeclarado: gate != null && !gate.quien.medido,
    revisionPedida: ref.watch(revisionProvider(donde)).value?.cuando,
    cierres: cierres,
  );
});

/// Pide la revisión del diff contra las reglas de la capa de cada archivo.
///
/// **Se manda como un encargo más y sin permiso de escritura.** No hay un canal especial
/// para esto y no debería haberlo: lo que se pide es una lectura, y una lectura que puede
/// escribir es otra cosa. El resultado aparece en la conversación, que es donde se
/// discute — guardar los hallazgos en una marca los convertiría en un veredicto.
class PedirLaRevision extends Notifier<bool> {
  PedirLaRevision(this.donde);

  final DondeMirar donde;

  /// `false` cuando no hubo nada que pedir. La pantalla lo dice en vez de fingir que
  /// mandó algo.
  @override
  bool build() => true;

  Future<void> pedir() async {
    final archivos = await ref.read(
      archivosTocadosProvider(donde.carpeta).future,
    );
    final lista = File('${donde.carpeta}/${ReglasDeclaradas.archivo}');
    final reglas = lista.existsSync()
        ? ReglasDeclaradas.leer(await lista.readAsString())
        : const <ReglaDeclarada>[];

    final texto = ElEncargoDeRevisar.texto(
      archivos: archivos,
      reglas: reglas,
      rama: donde.rama,
    );
    final conversacion = ref.read(conversationsProvider).focused;
    if (texto == null || conversacion == null) {
      state = false;
      return;
    }

    state = true;
    await ref
        .read(assistantControllerProvider(conversacion.id).notifier)
        .submit(texto, allowWrites: false);

    // Se anota que **se pidió**, no que se hizo: cuándo termina y qué encuentra es de la
    // conversación. Lo único que esta marca tiene que poder contestar es si lo revisado
    // sigue siendo el código que hay.
    await ref
        .read(revisionDataSourceProvider)
        .anotar(
          donde.configDir,
          donde.carpeta,
          rama: donde.rama,
          huella: await ref.read(huellaDelArbolProvider(donde.carpeta).future),
          archivos: archivos.length,
        );
    ref.invalidate(revisionProvider(donde));
  }
}

final pedirLaRevisionProvider =
    NotifierProvider.family<PedirLaRevision, bool, DondeMirar>(
      PedirLaRevision.new,
    );

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
      final revisiones = ref.watch(revisionDataSourceProvider);

      final claves = <({String carpeta, String? rama})>{
        ...await planes.carpetasYRamas(configDir),
        ...await gates.carpetasYRamas(configDir),
        ...await cierres.carpetasYRamas(configDir),
        ...await revisiones.carpetasYRamas(configDir),
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
        final suRevision = await revisiones.leer(
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
            gateDeclarado: !gate.quien.medido,
            revisionPedida: suRevision?.cuando,
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
/// **Es irreversible**, y por eso una rama viva pide confirmar y una huérfana no: borrar
/// la medición de un trabajo en curso por un clic de más es la única forma de que esta
/// pantalla haga daño.
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
    await ref.read(revisionDataSourceProvider).borrar(configDir, carpeta, rama);
    ref.invalidate(todasLasCorridasProvider(configDir));
  }
}

final limpiarCorridasProvider = NotifierProvider<LimpiarCorridas, void>(
  LimpiarCorridas.new,
);
