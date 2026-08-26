import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/platform/claude_environment.dart';
import 'package:nexus/features/workspace/data/datasources/plan_firmado_data_source.dart';

final planFirmadoDataSourceProvider = Provider<PlanFirmadoDataSource>(
  (ref) => const PlanFirmadoDataSource(),
);

/// La carpeta, la cuenta y la rama con las que se mira su plan.
///
/// La cuenta va aquí porque el plan vive **en la cuenta**: la misma carpeta abierta con
/// dos cuentas distintas tiene dos planes, y eso es correcto — el gate es de quien lo
/// enciende, no del proyecto.
///
/// Y la rama porque la firma es de la tarea, no del proyecto. `null` es una carpeta sin
/// repositorio, que también es un caso real: la carpeta suelta de documentos.
typedef DondeMirar = ({String carpeta, String configDir, String? rama});

/// El plan de una carpeta, o `null` si esa carpeta no tiene marca.
///
/// **Se relee, no se guarda en memoria y ya.** El plan caduca con el reloj y lo puede
/// cambiar otra ventana o el propio hook: un valor cacheado enseñaría «firmado» sobre un
/// permiso que ya expiró, y esa es justo la mentira que este gate existe para no contar.
class PlanFirmadoController extends AsyncNotifier<PlanFirmado?> {
  PlanFirmadoController(this.donde);

  final DondeMirar donde;

  @override
  Future<PlanFirmado?> build() => ref
      .read(planFirmadoDataSourceProvider)
      .leer(donde.configDir, donde.carpeta, rama: donde.rama);

  /// Enciende o apaga la exigencia de plan para esta carpeta.
  ///
  /// Apagarla **no borra el plan escrito**: si mañana se vuelve a encender, lo que había
  /// sigue ahí con su fecha — y si ya caducó, el gate lo dirá. Borrarlo al apagar haría
  /// que apagar y encender pareciera firmar.
  Future<void> exigir(bool valor) async {
    final actual = state.value;
    await _guardar(
      (actual ??
              PlanFirmado(
                carpeta: donde.carpeta,
                rama: donde.rama,
                exige: valor,
              ))
          .copyWith(exige: valor),
    );
  }

  /// Firma un plan. La fecha la pone esto, no quien escribe: una firma con fecha ajena no
  /// es una firma.
  Future<void> firmar(String plan) async {
    final limpio = plan.trim();
    if (limpio.isEmpty) return;
    await _guardar(
      (state.value ??
              PlanFirmado(
                carpeta: donde.carpeta,
                rama: donde.rama,
                exige: true,
              ))
          .copyWith(exige: true, plan: limpio, firmado: DateTime.now().toUtc()),
    );
  }

  Future<void> _guardar(PlanFirmado plan) async {
    await ref
        .read(planFirmadoDataSourceProvider)
        .guardar(donde.configDir, plan);
    state = AsyncData(plan);
  }
}

final planFirmadoProvider =
    AsyncNotifierProvider.family<
      PlanFirmadoController,
      PlanFirmado?,
      DondeMirar
    >(PlanFirmadoController.new);

/// Dónde mirar el plan de una carpeta, resolviendo la cuenta **igual que la resuelve el
/// proceso** que va a lanzar el encargo.
///
/// Se reutiliza `ClaudeEnvironment` en vez de leer `claudeProfile` y ya: el hook lee
/// `CLAUDE_CONFIG_DIR`, y sin perfil elegido eso no es vacío sino la cuenta de fábrica.
/// Calcularlo aparte aquí es cómo la pantalla acabaría diciendo «sin plan» sobre una
/// carpeta que el hook ve firmada.
DondeMirar dondeMirar({
  required String carpeta,
  String? perfil,
  String? rama,
}) => (
  carpeta: carpeta,
  configDir: ClaudeEnvironment.forProfile(perfil)['CLAUDE_CONFIG_DIR'] ?? '',
  rama: rama,
);
