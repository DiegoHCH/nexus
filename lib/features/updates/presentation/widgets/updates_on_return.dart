import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/updates/presentation/providers/updates_providers.dart';

/// Vuelve a preguntar al volver a la ventana, con el tope de quince minutos.
///
/// Envuelve en vez de vivir en una pantalla concreta: así vale igual en Reposo,
/// en la configuración inicial y en la comprobación de arranque, que son sitios
/// donde también se puede pasar un rato.
class UpdatesOnReturn extends ConsumerStatefulWidget {
  const UpdatesOnReturn({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdatesOnReturn> createState() => _UpdatesOnReturnState();
}

class _UpdatesOnReturnState extends ConsumerState<UpdatesOnReturn> {
  late final AppLifecycleListener _escucha;

  @override
  void initState() {
    super.initState();
    _escucha = AppLifecycleListener(
      onResume: () =>
          ref.read(updatesControllerProvider.notifier).alRegresar(),
    );
  }

  @override
  void dispose() {
    _escucha.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
