import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/assistant/presentation/orb/nexus_orb.dart';
import 'package:nexus/features/assistant/presentation/providers/assistant_controller.dart';
import 'package:nexus/features/assistant/presentation/widgets/subtitle_strip.dart';

/// El hito visual de la Fase 1: el orbe con su horizonte arriba, la franja
/// de subtítulos abajo. Sin memoria entre turnos, sin permisos a la vista,
/// sin voz — eso es Fase 2 y 3.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hud = ref.watch(assistantControllerProvider);
    final controller = ref.read(assistantControllerProvider.notifier);

    return Scaffold(
      body: Column(
        children: [
          Expanded(child: NexusOrb(state: hud.orbState)),
          SubtitleStrip(
            subtitle: hud.subtitle,
            isStreaming: hud.isStreaming,
            onSubmit: controller.submit,
            onFocusChanged: controller.setListening,
          ),
        ],
      ),
    );
  }
}
