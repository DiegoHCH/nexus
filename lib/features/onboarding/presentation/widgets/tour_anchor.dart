import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/onboarding/presentation/providers/tour_providers.dart';
import 'package:nexus/features/onboarding/presentation/state/tour_state.dart';

/// Marca una pieza del HUD como parada del tour.
///
/// No dibuja nada ni cambia la maquetación: solo cuelga una clave para poder
/// preguntar por su rectángulo. Envolver la pieza de verdad —y no apuntar a unas
/// coordenadas— es lo que hace que el tour siga señalando bien el día que alguien
/// mueva el muelle o cambie el reparto de la pantalla.
class TourAnchor extends ConsumerWidget {
  const TourAnchor({super.key, required this.stop, required this.child});

  final TourStop stop;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => KeyedSubtree(
    key: ref.watch(tourAnchorsProvider)[stop],
    child: child,
  );
}
