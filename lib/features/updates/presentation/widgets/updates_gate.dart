import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/updates/presentation/providers/updates_providers.dart';
import 'package:nexus/features/updates/presentation/widgets/update_toast.dart';

/// Vuelve a preguntar al volver a la ventana, y cuelga el aviso donde se vea.
///
/// Envuelve en vez de vivir en una pantalla concreta: así vale igual en Reposo,
/// en la configuración inicial y en la comprobación de arranque, que son sitios
/// donde también se puede pasar un rato.
class UpdatesGate extends ConsumerStatefulWidget {
  const UpdatesGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdatesGate> createState() => _UpdatesGateState();
}

class _UpdatesGateState extends ConsumerState<UpdatesGate> {
  late final AppLifecycleListener _escucha;
  OverlayEntry? _aviso;

  @override
  void initState() {
    super.initState();
    _escucha = AppLifecycleListener(
      onResume: () => ref.read(updatesControllerProvider.notifier).alRegresar(),
    );

    // En el **overlay raíz** y no en un Stack de esta pantalla: Ajustes se abre
    // como ruta empujada, y desde ahí también se puede pulsar «buscar
    // actualizaciones». Colgado más abajo, el aviso saldría detrás de Ajustes.
    //
    // Después del primer fotograma porque el Overlay todavía no existe mientras
    // se construye este widget.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final entrada = OverlayEntry(builder: (_) => const UpdateToast());
      _aviso = entrada;
      Overlay.of(context, rootOverlay: true).insert(entrada);
    });
  }

  @override
  void dispose() {
    _escucha.dispose();
    _aviso?.remove();
    super.dispose();
  }

  // Se inserta **una vez y para siempre**, y es el propio aviso quien decide si
  // pinta algo. La alternativa —meterlo y sacarlo según la fase— obliga a llevar
  // la cuenta de si ya está puesto, y ahí es donde salen dos avisos a la vez o
  // ninguno. En reposo no pinta nada y no intercepta pulsaciones.
  @override
  Widget build(BuildContext context) => widget.child;
}
