import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/assistant/presentation/orb/nexus_orb.dart';
import 'package:nexus/features/assistant/presentation/providers/assistant_controller.dart';
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/assistant/presentation/widgets/activity_column.dart';
import 'package:nexus/features/assistant/presentation/widgets/chat_panel.dart';
import 'package:nexus/features/assistant/presentation/widgets/conversation_dock.dart';
import 'package:nexus/features/assistant/presentation/widgets/hud_bottom_bar.dart';
import 'package:nexus/features/history/presentation/widgets/conversation_history_sheet.dart';
import 'package:nexus/features/assistant/presentation/widgets/subtitle_strip.dart';
import 'package:nexus/features/workspace/presentation/pages/settings_page.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:nexus/features/workspace/presentation/widgets/hud_top_bar.dart';

/// El orbe fijo a la izquierda y la conversación a la derecha: lo que le
/// pediste y lo que respondió, por voz o escrito, en el mismo sitio. Abajo, la
/// caja para escribirle, siempre disponible.
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
      keyDownHandler: (_) => unawaited(_talk()),
    );
  }

  /// El atajo abre la voz, y **crea la conversación si no hay ninguna**.
  ///
  /// Antes se rendía en silencio: pulsabas ⌥Espacio recién abierta la app y no
  /// pasaba nada, sin decir por qué. Los tres caminos —«NUEVA», escribir y
  /// hablar— crean conversación igual.
  Future<void> _talk() async {
    var focused = ref.read(conversationsProvider).focused;
    if (focused == null) {
      final folders = ref.read(workspaceControllerProvider).folders;
      if (folders.isEmpty) return;
      final id = await ref
          .read(conversationsProvider.notifier)
          .open(folders.first.path);
      if (id == null) return;
      focused = ref.read(conversationsProvider).byId(id);
      if (focused == null) return;
    }
    await ref
        .read(assistantControllerProvider(focused.id).notifier)
        .toggleVoice();
  }

  @override
  void dispose() {
    hotKeyManager.unregister(HomePage._talkHotKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = ref.watch(conversationsProvider).focused;
    // Sin conversación abierta no se planta una pantalla de por medio: se
    // entra al orbe, con el hueco «NUEVA» y la caja lista. Escribir crea la
    // conversación — preguntar antes de dejarte escribir era un peaje.
    if (focused == null) return const _FirstRun();

    final hud = ref.watch(assistantControllerProvider(focused.id));
    final controller = ref.read(
      assistantControllerProvider(focused.id).notifier,
    );
    final working = hud.orbState == NexusOrbState.think;
    // Mientras no se haya dicho nada, el orbe es todo lo que hay que mirar y
    // ocupa la pantalla entera. Se aparta a la izquierda solo cuando aparece
    // algo que leer: repartir la pantalla en dos para dejar media vacía sería
    // pedirle al ojo que ignore un hueco.
    final hasChat = hud.messages.isNotEmpty;

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
        // ⌘Y y no ⌘H: en macOS **⌘H es «ocultar la aplicación»**, y el menú se
        // lo queda antes de que la tecla llegue a Flutter — así que el atajo no
        // fallaba, escondía la ventana. Es la misma trampa de ⌘, y no se pelea
        // con ella: ocultar con ⌘H lo espera cualquiera que use un Mac.
        const SingleActivator(LogicalKeyboardKey.keyY, meta: true): () =>
            ConversationHistorySheet.open(
              context,
              forgetFolder: focused.folderPath.split('/').last,
              onPick: controller.resume,
              onForget: controller.forgetConversation,
            ),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Column(
            children: [
              HudTopBar(
                status: _statusFor(hud.orbState, context.strings),
                live: working || hud.voiceActive,
                meter: hud.meter,
                folderPath: focused.folderPath,
              ),
              Expanded(
                child: Stack(
                  children: [
                    // El orbe se queda a la izquierda, fijo. Antes saltaba del
                    // centro a un lado según el estado; con la conversación
                    // siempre a la derecha, ese baile movía media pantalla cada
                    // vez que empezaba o terminaba un turno.
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 420),
                      curve: Curves.easeInOutCubic,
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: hasChat
                          ? MediaQuery.sizeOf(context).width * 0.42
                          : MediaQuery.sizeOf(context).width,
                      child: GestureDetector(
                        onTap: controller.toggleVoice,
                        behavior: HitTestBehavior.opaque,
                        child: NexusOrb(state: hud.orbState),
                      ),
                    ),
                    if (hasChat)
                      Positioned(
                        left: MediaQuery.sizeOf(context).width * 0.44,
                        right: NexusSpacing.s7,
                        top: NexusSpacing.s6,
                        bottom: NexusSpacing.s4,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: ChatPanel(messages: hud.messages)),
                            // La actividad no desaparece: baja al pie de la
                            // conversación mientras hay trabajo, para verse sin
                            // tapar lo que ya se dijo.
                            if (working)
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight:
                                      MediaQuery.sizeOf(context).height * 0.4,
                                ),
                                child: ActivityColumn(
                                  items: hud.activity,
                                  onStop: controller.stopWork,
                                ),
                              ),
                          ],
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
                    Positioned(
                      left: NexusSpacing.s6,
                      bottom: NexusSpacing.s5,
                      child: const ConversationDock(),
                    ),
                    if (hud.errorMessage != null)
                      Positioned(
                        top: NexusSpacing.s5,
                        left: NexusSpacing.s6,
                        right: NexusSpacing.s6,
                        child: _ErrorChip(
                          message: hud.errorMessage!,
                          onDismiss: controller.dismissError,
                        ),
                      ),
                  ],
                ),
              ),
              HudBottomBar(
                consequence: _consequence(
                  ref,
                  focused.folderPath,
                  context.strings,
                ),
                escape: hud.voiceActive
                    ? context.strings.sayStopToInterrupt
                    : (working ? context.strings.stopWithShortcut : null),
              ),
              // Sin el texto de la respuesta: ahora vive en la ventana de la
              // derecha. Abajo queda solo la caja, que **siempre** está
              // disponible — también mientras habla o trabaja.
              SubtitleStrip(
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

/// Sin conversaciones no hay pantalla que pintar: lo único útil es llevar a
/// emparejar una carpeta, que es lo que falta.
/// La casa sin ninguna conversación abierta: el mismo orbe, centrado, con el
/// hueco «NUEVA» y la caja de escribir.
///
/// Escribir aquí **crea la conversación** sobre la primera carpeta emparejada.
/// Elegir carpeta sigue estando a un clic —en «NUEVA»— pero no se exige antes
/// de dejarte escribir: plantar una pantalla de «¿dónde quieres trabajar?»
/// delante de cada arranque es un peaje para responder casi siempre lo mismo.
class _FirstRun extends ConsumerStatefulWidget {
  const _FirstRun();

  @override
  ConsumerState<_FirstRun> createState() => _FirstRunState();
}

class _FirstRunState extends ConsumerState<_FirstRun> {
  Future<void> _startWith(String text) async {
    final folders = ref.read(workspaceControllerProvider).folders;
    if (folders.isEmpty) {
      // Sin carpetas no hay dónde trabajar: se lleva a emparejar en vez de
      // crear una conversación que no podría hacer nada.
      if (mounted) await SettingsPage.open(context);
      return;
    }
    final id = await ref
        .read(conversationsProvider.notifier)
        .open(folders.first.path);
    if (id == null) return;
    await ref.read(assistantControllerProvider(id).notifier).submit(text);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final folders = ref.watch(workspaceControllerProvider).folders;

    // Los atajos también viven aquí, no solo con una conversación abierta:
    // ⌘, es justo lo que hace falta cuando todavía no hay nada emparejado, y
    // era el único momento en que no respondía.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.comma, meta: true): () =>
            SettingsPage.open(context),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Column(
            children: [
              HudTopBar(status: context.strings.asleep),
              Expanded(
                child: Stack(
                  children: [
                    const Positioned.fill(
                      child: NexusOrb(state: NexusOrbState.sleep),
                    ),
                    const Positioned(
                      left: NexusSpacing.s6,
                      bottom: NexusSpacing.s5,
                      child: ConversationDock(),
                    ),
                    if (folders.isEmpty)
                      Positioned(
                        top: NexusSpacing.s5,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: TextButton(
                            onPressed: () => SettingsPage.open(context),
                            child: Text(
                              context.strings.pairAFolderToStart,
                              style: NexusTypography.label.copyWith(
                                color: colors.cyan,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SubtitleStrip(onSubmit: _startWith, onFocusChanged: (_) {}),
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
String _consequence(WidgetRef ref, String folderPath, NexusStrings strings) {
  final workspace = ref.watch(workspaceControllerProvider);
  final folder = workspace.folders
      .where((item) => item.path == folderPath)
      .firstOrNull;
  if (folder == null) return strings.noFolderNothingToTouch;
  return workspace.permission.canWrite
      ? strings.canEditFilesIn(folder.name)
      : strings.readOnlyIn(folder.name);
}

/// Una palabra para lo que está pasando, como el «Dormido» del mockup.
String _statusFor(NexusOrbState state, NexusStrings strings) => switch (state) {
  NexusOrbState.sleep => strings.asleep,
  NexusOrbState.listen => strings.listening,
  NexusOrbState.think => strings.working,
  NexusOrbState.speak => strings.speaking,
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
                ? context.strings.workingCancelHint
                : context.strings.micOpenHint,
            style: NexusTypography.label.copyWith(color: color),
          ),
        ),
      ),
    );
  }
}

/// El aviso, con la forma que el diseño ya tiene para esto: un chip, no una
/// banda roja de lado a lado.
///
/// Va acotado y con punto delante —el mismo recurso del interruptor de
/// permisos— y se puede descartar: un error que no se va obliga a convivir con
/// él aunque ya lo hayas leído.
class _ErrorChip extends StatelessWidget {
  const _ErrorChip({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.err.withValues(alpha: 0.1),
            border: Border.all(color: colors.err.withValues(alpha: 0.35)),
            borderRadius: BorderRadius.circular(NexusRadius.sm),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              NexusSpacing.s3,
              NexusSpacing.s2,
              NexusSpacing.s2,
              NexusSpacing.s2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.err,
                  ),
                ),
                const SizedBox(width: NexusSpacing.s3),
                Flexible(
                  child: Text(
                    message,
                    style: NexusTypography.mono.copyWith(
                      color: colors.err,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(width: NexusSpacing.s2),
                InkWell(
                  onTap: onDismiss,
                  child: Icon(
                    Icons.close,
                    size: 13,
                    color: colors.err.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
