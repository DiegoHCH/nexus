import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/updates/domain/entities/update_stage.dart';
import 'package:nexus/features/updates/presentation/providers/updates_providers.dart';
import 'package:nexus/features/updates/presentation/widgets/update_modal.dart';

/// Vuelve a preguntar al volver a la ventana, y saca la modal cuando hay algo.
///
/// Envuelve en vez de vivir en una pantalla concreta: así vale igual en Reposo,
/// en la configuración inicial y en la comprobación de arranque, que son sitios
/// donde también se puede pasar un rato.
///
/// Va **dentro** del `MaterialApp` y no fuera, y eso no es casual: `showDialog`
/// necesita un Navigator por encima. Colgado del árbol de arriba, la modal no
/// tendría dónde abrirse.
class UpdatesGate extends ConsumerStatefulWidget {
  const UpdatesGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdatesGate> createState() => _UpdatesGateState();
}

class _UpdatesGateState extends ConsumerState<UpdatesGate> {
  late final AppLifecycleListener _escucha;

  /// Para no abrir dos modales si llegan dos avisos seguidos —puede pasar si una
  /// comprobación de fondo y una manual se cruzan—.
  bool _abierta = false;

  @override
  void initState() {
    super.initState();
    _escucha = AppLifecycleListener(
      onResume: () => ref.read(updatesControllerProvider.notifier).alRegresar(),
    );
  }

  @override
  void dispose() {
    _escucha.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Solo `UpdateFound` abre la modal por su cuenta. Las demás fases son
    // consecuencia de haber pulsado algo, y para entonces ya está abierta; una
    // descarga no debería poder sacar un cartel que nadie pidió.
    ref.listen(updatesControllerProvider.select((s) => s.stage), (_, fase) {
      if (fase is UpdateIdle) {
        _abierta = false;
        return;
      }
      if (fase is! UpdateFound || _abierta) return;
      _abierta = true;
      UpdateModal.open(context).whenComplete(() => _abierta = false);
    });

    return widget.child;
  }
}
