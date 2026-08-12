import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/features/assistant/presentation/orb/nexus_orb.dart';
import 'package:nexus/features/assistant/presentation/providers/assistant_controller.dart';
import 'package:nexus/features/assistant/presentation/widgets/subtitle_strip.dart';

/// El orbe con su horizonte arriba, la franja de subtítulos abajo. Se puede
/// escribir —camino de la Fase 1, por Claude— o hablar.
///
/// Sin memoria entre turnos ni permisos a la vista todavía: eso es Fase 3.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  /// ⌥Espacio, la convención de los lanzadores de macOS. Es global: funciona
  /// con la ventana detrás, que es el único modo en que un asistente sirve de
  /// algo mientras trabajas en otra cosa.
  static final _talkHotKey = HotKey(
    key: PhysicalKeyboardKey.space,
    modifiers: [HotKeyModifier.alt],
    scope: HotKeyScope.system,
  );

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  @override
  void initState() {
    super.initState();
    // Se registra aquí y no al arrancar la app: durante el splash y la
    // configuración inicial no hay con qué hablar todavía.
    hotKeyManager.register(
      HomePage._talkHotKey,
      keyDownHandler: (_) => ref.read(assistantControllerProvider.notifier).toggleVoice(),
    );
  }

  @override
  void dispose() {
    hotKeyManager.unregister(HomePage._talkHotKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hud = ref.watch(assistantControllerProvider);
    final controller = ref.read(assistantControllerProvider.notifier);

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: controller.toggleVoice,
                    behavior: HitTestBehavior.opaque,
                    child: NexusOrb(state: hud.orbState),
                  ),
                ),
                if (hud.voiceActive)
                  const Positioned(top: NexusSpacing.s5, left: 0, right: 0, child: _LiveBadge()),
                if (hud.errorMessage != null)
                  Positioned(
                    bottom: NexusSpacing.s4,
                    left: NexusSpacing.s6,
                    right: NexusSpacing.s6,
                    child: _ErrorLine(hud.errorMessage!),
                  ),
              ],
            ),
          ),
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

/// Que el micrófono esté saliendo hacia Google no puede ser invisible: si el
/// orbe se quedara igual, la única señal sería el punto naranja de macOS.
class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.err.withValues(alpha: 0.12),
          border: Border.all(color: colors.err.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(NexusRadius.sm),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.s3, vertical: 3),
          child: Text(
            'MICRÓFONO ABIERTO · SE CIERRA SOLO AL CALLARTE',
            style: NexusTypography.label.copyWith(color: colors.err),
          ),
        ),
      ),
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      textAlign: TextAlign.center,
      style: NexusTypography.mono.copyWith(color: context.colors.err),
    );
  }
}
