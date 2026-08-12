import 'package:flutter/material.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/features/assistant/presentation/orb/nexus_orb.dart';
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';

/// D00a del mockup: el primer fotograma. Sin logo animado ni barra de
/// progreso — solo el wordmark centrado, la etiqueta «Iniciando» abajo, y el
/// orbe apareciendo con un fundido suave.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOut,
              builder: (context, t, child) => Opacity(
                opacity: t,
                child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
              ),
              child: const NexusOrb(state: NexusOrbState.sleep),
            ),
          ),
          Positioned(
            top: NexusSpacing.s7,
            left: 0,
            right: 0,
            child: Text(
              'N E X U S',
              textAlign: TextAlign.center,
              style: NexusTypography.brand.copyWith(color: colors.mute, letterSpacing: 6.16),
            ),
          ),
          Positioned(
            bottom: NexusSpacing.s7,
            left: 0,
            right: 0,
            child: Text(
              'INICIANDO',
              textAlign: TextAlign.center,
              style: NexusTypography.label.copyWith(color: colors.faint, letterSpacing: 3.5),
            ),
          ),
        ],
      ),
    );
  }
}
