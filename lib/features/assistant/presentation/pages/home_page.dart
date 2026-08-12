import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/features/assistant/presentation/orb/nexus_orb.dart';
import 'package:nexus/features/assistant/presentation/providers/assistant_controller.dart';
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';
import 'package:nexus/features/assistant/presentation/widgets/activity_column.dart';
import 'package:nexus/features/assistant/presentation/widgets/history_panel.dart';
import 'package:nexus/features/assistant/presentation/widgets/history_sheet.dart';
import 'package:nexus/features/assistant/presentation/widgets/hud_bottom_bar.dart';
import 'package:nexus/features/assistant/presentation/widgets/subtitle_strip.dart';
import 'package:nexus/features/workspace/presentation/pages/settings_page.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:nexus/features/workspace/presentation/widgets/hud_top_bar.dart';

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
      keyDownHandler: (_) =>
          ref.read(assistantControllerProvider.notifier).toggleVoice(),
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
    final working = hud.orbState == NexusOrbState.think;

    return CallbackShortcuts(
      bindings: {
        // ⌘, es el atajo de preferencias de cualquier app de macOS: no hay
        // motivo para inventarse otro.
        const SingleActivator(LogicalKeyboardKey.comma, meta: true): () =>
            SettingsPage.open(context),
        // ⌘. es el «cancelar» de toda la vida en macOS, y el que pide el
        // diseño junto al botón Detener.
        const SingleActivator(LogicalKeyboardKey.period, meta: true):
            controller.stopWork,
        const SingleActivator(LogicalKeyboardKey.keyH, meta: true): () =>
            HistorySheet.open(
              context,
              entries: hud.history,
              onPick: controller.submit,
            ),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Column(
            children: [
              HudTopBar(
                status: _statusFor(hud.orbState),
                live: working || hud.voiceActive,
                meter: hud.meter,
              ),
              Expanded(
                child: Stack(
                  children: [
                    // El orbe se aparta a la izquierda cuando hay trabajo para
                    // dejarle el centro a la actividad. Es el cambio de
                    // composición que el diseño pide para cada estado: no basta
                    // con cambiar el color del orbe, cambia el reparto de la
                    // pantalla.
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 420),
                      curve: Curves.easeInOutCubic,
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: working
                          ? MediaQuery.sizeOf(context).width * 0.56
                          : MediaQuery.sizeOf(context).width,
                      child: GestureDetector(
                        onTap: controller.toggleVoice,
                        behavior: HitTestBehavior.opaque,
                        child: NexusOrb(state: hud.orbState),
                      ),
                    ),
                    // Sin saltarse nada: en la pantalla «Hablando» del mockup
                    // la primera entrada de ANTES es la pregunta que se está
                    // respondiendo, porque en pantalla se ve la respuesta, no
                    // la pregunta. Saltarla dejaba el panel vacío justo al
                    // terminar el primer turno.
                    if (!working)
                      Positioned(
                        right: 64,
                        top: NexusSpacing.s6,
                        width: 300,
                        child: HistoryPanel(
                          entries: hud.history,
                          onOpenAll: () => HistorySheet.open(
                            context,
                            entries: hud.history,
                            onPick: controller.submit,
                          ),
                        ),
                      ),
                    if (working)
                      Positioned(
                        left: MediaQuery.sizeOf(context).width * 0.58,
                        right: 64,
                        top: NexusSpacing.s8,
                        bottom: NexusSpacing.s6,
                        child: ActivityColumn(
                          items: hud.activity,
                          onStop: controller.stopWork,
                        ),
                      ),
                    if (hud.voiceActive)
                      Positioned(
                        top: NexusSpacing.s5,
                        left: 0,
                        right: 0,
                        child: _LiveBadge(
                          working: hud.orbState == NexusOrbState.think,
                        ),
                      ),
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
              HudBottomBar(
                consequence: _consequence(ref, context),
                escape: hud.voiceActive
                    ? 'Di «para» para interrumpir'
                    : (working ? 'Detener con ⌘.' : null),
              ),
              SubtitleStrip(
                subtitle: hud.subtitle,
                isStreaming: hud.isStreaming,
                onSubmit: controller.submit,
                onFocusChanged: controller.setListening,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El permiso dicho sobre la carpeta concreta, no en abstracto.
///
/// El diseño insiste en que «el permiso y su consecuencia se ven juntos», y la
/// diferencia es real: «puede editar» no dice nada, «puede editar archivos en
/// front-mobile-b2c» sí.
String _consequence(WidgetRef ref, BuildContext context) {
  final workspace = ref.watch(workspaceControllerProvider);
  final active = workspace.active;
  if (active == null) return 'Sin carpeta emparejada — nada que tocar todavía';
  return workspace.permission.canWrite
      ? 'Puede editar archivos en ${active.name}'
      : 'Solo lectura en ${active.name}';
}

/// Una palabra para lo que está pasando, como el «Dormido» del mockup.
String _statusFor(NexusOrbState state) => switch (state) {
  NexusOrbState.sleep => 'Dormido',
  NexusOrbState.listen => 'Escuchando',
  NexusOrbState.think => 'Trabajando',
  NexusOrbState.speak => 'Hablando',
};

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.working});

  /// Mientras Claude trabaja el aviso cambia: ahí lo que hace falta saber no
  /// es que el micro está abierto, sino que **se puede parar** — un encargo
  /// puede durar minutos y quedarse sin salida visible sería lo peor.
  final bool working;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = working ? colors.warn : colors.err;
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(NexusRadius.sm),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NexusSpacing.s3,
            vertical: 3,
          ),
          child: Text(
            working
                ? 'TRABAJANDO · ⌥ESPACIO PARA CANCELAR'
                : 'MICRÓFONO ABIERTO · SE CIERRA SOLO AL CALLARTE',
            style: NexusTypography.label.copyWith(color: color),
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
