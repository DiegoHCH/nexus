import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:nexus/features/assistant/presentation/state/chat_message.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/assistant/presentation/orb/nexus_orb.dart';
import 'package:nexus/features/assistant/presentation/providers/assistant_controller.dart';
import 'package:nexus/features/assistant/presentation/providers/la_ventana_de_actividad.dart';
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';
import 'package:nexus/features/artifacts/presentation/providers/artifacts_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/assistant/presentation/widgets/activity_button.dart';
import 'package:nexus/features/assistant/presentation/widgets/chat_panel.dart';
import 'package:nexus/features/onboarding/presentation/state/tour_state.dart';
import 'package:nexus/features/onboarding/presentation/widgets/tour_anchor.dart';
import 'package:nexus/features/assistant/presentation/widgets/status_presence.dart';
import 'package:nexus/features/onboarding/presentation/widgets/tour_overlay.dart';
import 'package:nexus/features/assistant/presentation/widgets/conversation_dock.dart';
import 'package:nexus/features/history/presentation/widgets/conversation_history_sheet.dart';
import 'package:nexus/features/assistant/presentation/widgets/composer_bar.dart';
import 'package:nexus/features/workspace/presentation/pages/settings_page.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:nexus/features/workspace/presentation/widgets/hud_top_bar.dart';

/// El orbe fijo a la izquierda y la conversación a la derecha: lo que le
/// pediste y lo que respondió, por voz o escrito, en el mismo sitio. Abajo, la
/// caja para escribirle, siempre disponible.
/// Dónde nace una conversación cuando no hay ninguna abierta.
///
/// **Manda la carpeta activa**, que es la que enseña la barra. Antes se abría
/// siempre sobre `folders.first`, y eso hacía que elegir carpeta y ponerse a
/// escribir empezara en otra — con «Sin proyecto», que la elección se perdiera
/// del todo, porque la carpeta de documentos no está entre las emparejadas.
///
/// Si no hay ninguna emparejada pero sí carpeta de documentos, se trabaja ahí:
/// pedir un mockup no exige tener un proyecto.
String? whereToStart(WidgetRef ref) {
  final workspace = ref.read(workspaceControllerProvider);
  return workspace.activePath ??
      workspace.folders.firstOrNull?.path ??
      ref.read(artifactsFolderProvider);
}

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
      final where = whereToStart(ref);
      if (where == null) return;
      final id = await ref.read(conversationsProvider.notifier).open(where);
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
    final conversaciones = ref.watch(conversationsProvider);
    // **Hasta que no se sabe, no se dice nada.** La lista nace vacía y el disco se lee
    // después, así que enseñar aquí la pantalla de primera vez era decir «no tienes
    // ninguna» durante la ventana de carga — y quien tocaba el orbe en ese momento se
    // llevaba una conversación **nueva** en lugar de la que tenía abierta. Esa es la
    // conversación vacía que aparecía tras cada arranque.
    if (!conversaciones.cargado) return const _Esperando();

    final focused = conversaciones.focused;
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
    final anchoDelOrbe = hasChat
        ? MediaQuery.sizeOf(context).width * 0.42
        : MediaQuery.sizeOf(context).width;

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
        const SingleActivator(
          LogicalKeyboardKey.keyY,
          meta: true,
        ): () => ConversationHistorySheet.open(
          context,
          forgetFolder: focused.folderPath.split('/').last,
          // **No `controller.resume`.** Eso pintaba el registro elegido dentro de
          // la conversación que tenías delante: elegías una de otra carpeta y te
          // cambiaba la que estabas mirando, con las dos escribiendo en el mismo
          // sitio. Es el fallo que se reportó tres veces.
          //
          // El proveedor decide: si esa conversación ya está abierta va a su
          // pestaña, y si no, abre una nueva sobre **su** carpeta. Había dos
          // sitios que abren el historial —el menú y este atajo— y solo se arregló
          // uno; de ahí que siguiera pasando.
          onPick: (record) => ref.read(retomarDelArchivoProvider)(record),
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
                folderPath: focused.folderPath,
              ),
              // Se mide en vez de preguntarle a `MediaQuery` porque lo que
              // decide el cruce con el muelle es **el alto que le queda al
              // HUD**, no el de la ventana: la barra de arriba se lleva su
              // parte, y con el alto de la ventana el orbe sale más grande de
              // lo que cabe justo en el caso que se está midiendo.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, cajaDelHud) {
                    // El muelle de conversaciones flota sobre este mismo
                    // `Stack`, en la esquina de abajo a la izquierda — justo
                    // donde vive el orbe. Se le aparta su franja **solo si de
                    // verdad se cruzan**: con varias abiertas la pila subía
                    // hasta la mitad del orbe y quedaba una encima de la otra
                    // según el orden de pintado, que no es una decisión de
                    // diseño sino un accidente; pero en la pantalla de arranque
                    // no se tocan y restarla solo encogía el orbe.
                    final franjaDelMuelle = ConversationDock.franjaQueEstorba(
                      Size(anchoDelOrbe, cajaDelHud.maxHeight),
                      conversaciones,
                    );

                    return Stack(
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
                          bottom: franjaDelMuelle,
                          width: anchoDelOrbe,
                          child: TourAnchor(
                            stop: TourStop.orb,
                            // El orbe es el mando principal de la app y para un
                            // lector de pantalla no existía: un `CustomPaint` sin
                            // nombre. `value` lleva el estado —dormido, escuchando,
                            // trabajando— porque es la única forma de saber qué
                            // está pasando sin ver el dibujo.
                            child: Semantics(
                              button: true,
                              label: context.strings.orbLabel,
                              hint: context.strings.orbHint,
                              value: _statusFor(hud.orbState, context.strings),
                              child: GestureDetector(
                                onTap: controller.toggleVoice,
                                behavior: HitTestBehavior.opaque,
                                // Llenando su caja, que aquí es apaisada: el
                                // muelle se lleva la franja de abajo y lo que
                                // queda es ancho y bajo. La fracción de siempre
                                // mide contra el alto y dejaba el orbe pequeño
                                // con sitio de sobra alrededor.
                                child: NexusOrb(
                                  state: hud.orbState,
                                  fillsBox: true,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (hasChat)
                          Positioned(
                            left: MediaQuery.sizeOf(context).width * 0.44,
                            right: NexusSpacing.s7,
                            // **Le deja sitio al aviso cuando el aviso está.**
                            //
                            // El chip de «micro abierto» / «trabajando» flota en una capa
                            // de encima, así que se pintaba sobre el primer mensaje: lo
                            // tapaba justo cuando más se mira la conversación. Se baja la
                            // columna en vez de mover el chip porque el chip **tiene** que
                            // estar arriba y centrado —es el aviso de que se está
                            // grabando— y la conversación sí puede empezar más abajo.
                            //
                            // Y solo mientras está: dejar el hueco siempre regalaría una
                            // franja vacía en la vista normal, que es la de casi siempre.
                            top: hud.voiceActive
                                ? NexusSpacing.s6 + _altoDelAviso
                                : NexusSpacing.s6,
                            bottom: NexusSpacing.s4,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  child: ChatPanel(
                                    messages: hud.messages,
                                    // El nombre configurado en Ajustes › Nombres, o
                                    // el de la app si no se ha elegido ninguno.
                                    etiquetaDelAgente: ref
                                        .watch(losNombresProvider)
                                        .etiqueta(context.strings.nexus),
                                    onRetry: controller.reintentar,
                                    onPermiso: controller.responderPermiso,
                                  ),
                                ),
                                // 🔴 Aquí había un segundo botón de «ver los
                                // archivos que tocó», y salía **a la vez** que el
                                // que cuelga del mensaje: el mismo botón dos veces,
                                // uno encima del otro. Este es el que sobra — el
                                // del mensaje es el que se guarda con la
                                // conversación y el que conserva lo suyo cuando
                                // pides la segunda cosa. Su propio comentario en
                                // `chat_panel` ya explicaba que esta barra
                                // enseñaba solo el último encargo; lo que faltó
                                // fue borrarla al mudarlo.
                                // La actividad no desaparece: se resume en una
                                // línea al pie de la conversación, y el detalle se
                                // abre aparte.
                                //
                                // Antes era la lista entera aquí abajo, con hasta
                                // el 40% del alto para ella. El problema no era el
                                // tamaño sino de quién lo quitaba: quince pasos
                                // empujando hacia arriba lo que se acababa de
                                // responder, justo mientras se lee.
                                //
                                // Detener sigue a mano sin abrir nada: **⌘.** está
                                // atado arriba, en esta misma pantalla.
                                if (working)
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    children: [
                                      Flexible(
                                        child: ActivityButton(
                                          items: hud.activity,
                                          onOpen: () => unawaited(
                                            ref
                                                .read(
                                                  laVentanaDeActividadProvider,
                                                )
                                                .seguir(focused.id),
                                          ),
                                        ),
                                      ),
                                      // Detener, al lado y no dentro de la ventana.
                                      //
                                      // Vivía al pie de la lista de pasos, y esa
                                      // lista se fue a una ventana aparte: dejarlo
                                      // allí obligaría a abrirla para poder parar.
                                      // ⌘. sigue atado arriba, pero un atajo sin
                                      // nada que lo enseñe solo lo usa quien ya lo
                                      // sabe.
                                      Tooltip(
                                        message: context.strings.stopButton,
                                        child: IconButton(
                                          onPressed: controller.stopWork,
                                          icon: const Icon(
                                            Icons.stop,
                                            size: 16,
                                          ),
                                          color: context.colors.faint,
                                          splashRadius: 16,
                                        ),
                                      ),
                                    ],
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
                        const Positioned(
                          left: NexusSpacing.s6,
                          bottom: ConversationDock.alDelSuelo,
                          child: TourAnchor(
                            stop: TourStop.dock,
                            child: ConversationDock(),
                          ),
                        ),
                        // El fallo y el aviso son dos cosas distintas y pueden
                        // coincidir, así que se apilan en vez de competir por el
                        // mismo hueco. El fallo va arriba: es el que urge.
                        if (hud.errorMessage != null || hud.notice != null)
                          Positioned(
                            top: NexusSpacing.s5,
                            left: NexusSpacing.s6,
                            right: NexusSpacing.s6,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (hud.errorMessage != null)
                                  _AvisoChip(
                                    message: hud.errorMessage!,
                                    color: context.colors.err,
                                    onDismiss: controller.dismissError,
                                    accion: hud.laSesionCaduco
                                        ? (
                                            texto: context
                                                .strings
                                                .entrarConLaCuenta,
                                            alPulsar: () => unawaited(
                                              controller.entrarConLaCuenta(),
                                            ),
                                          )
                                        : null,
                                  ),
                                if (hud.errorMessage != null &&
                                    hud.notice != null)
                                  const SizedBox(height: NexusSpacing.s2),
                                if (hud.notice != null)
                                  _AvisoChip(
                                    message: hud.notice!,
                                    // Ámbar y no rojo: algo cambió, no algo se
                                    // rompió. En rojo se lee como un fallo del
                                    // encargo, que es justo lo que no es.
                                    color: context.colors.warn,
                                    onDismiss: controller.dismissNotice,
                                  ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              // Los ajustes de la conversación viven aquí, junto a la
              // caja, y ya no arriba del todo: se leen justo antes de pedir
              // algo y se cambian sin cruzar la pantalla.
              TourAnchor(
                stop: TourStop.composer,
                child: ComposerBar(
                  onSubmit: (texto, adjuntos) =>
                      controller.submit(texto, attachments: adjuntos),
                  onFocusChanged: controller.setListening,
                  // El historial de las flechas: lo que ya escribiste en esta
                  // conversación. Sale de los turnos que ya están y no de un
                  // almacén nuevo — son lo mismo, y dos sitios con lo mismo hay
                  // que mantenerlos de acuerdo para siempre.
                  loQueYaEscribi: [
                    for (final mensaje in hud.messages)
                      if (mensaje.author == ChatAuthor.user) mensaje.text,
                  ],
                  folderPath: focused.folderPath,
                  meter: hud.meter,
                  voiceActive: hud.voiceActive,
                  onToggleVoice: controller.toggleVoice,
                ),
              ),
              // Fuera del `Stack` a propósito: se pinta en el `Overlay` de la app,
              // así que su sitio en el árbol da igual — pero **dentro** del Stack
              // le fijaba el ancho a cero, porque un Stack se dimensiona por sus
              // hijos sin posicionar y este mide 0. Eso dejaba el orbe con ancho
              // cero y el muelle desplazado.
              const TourOverlay(),
              // El icono de la barra de estado, al día con el orbe. Tamaño cero,
              // como el velo, y fuera del `Stack` por el mismo motivo: dentro le
              // fijaría el ancho.
              StatusPresence(conversationId: focused.id),
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
/// Mientras se lee del disco qué había abierto.
///
/// El orbe dormido y nada más: **ninguna acción**, porque cualquiera de ellas crearía
/// una conversación y el sentido de esta pantalla es no crear ninguna por no saber
/// todavía. Dura lo que tarda una lectura de preferencias, así que no lleva texto: un
/// cartel que aparece y desaparece en un parpadeo se lee como un fallo.
class _Esperando extends StatelessWidget {
  const _Esperando();

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.colors.void_,
    body: const Center(
      child: SizedBox(height: 220, child: NexusOrb(state: NexusOrbState.sleep)),
    ),
  );
}

class _FirstRun extends ConsumerStatefulWidget {
  const _FirstRun();

  @override
  ConsumerState<_FirstRun> createState() => _FirstRunState();
}

class _FirstRunState extends ConsumerState<_FirstRun> {
  Future<void> _startWith(String text, List<String> adjuntos) async {
    final where = whereToStart(ref);
    if (where == null) {
      // Ni carpeta emparejada ni carpeta de documentos: no hay dónde trabajar,
      // así que se lleva a elegir en vez de crear una conversación que no
      // podría hacer nada.
      if (mounted) await SettingsPage.open(context);
      return;
    }
    final id = await ref.read(conversationsProvider.notifier).open(where);
    if (id == null) return;
    await ref
        .read(assistantControllerProvider(id).notifier)
        .submit(text, attachments: adjuntos);
  }

  /// Tocar el orbe abre la voz, **creando la conversación si no hay ninguna**.
  ///
  /// Es el cuarto camino para empezar, y era el único que no funcionaba. Los
  /// otros tres —«NUEVA», escribir y ⌥Espacio— ya lo hacían; aquí el orbe era
  /// decorativo, del mismo tamaño y en el mismo sitio que el que sí responde
  /// con una conversación abierta. Se pulsaba y no pasaba nada, sin decir por
  /// qué, que es lo peor: no distingues «no me oye» de «no te estoy oyendo».
  Future<void> _talk() async {
    final where = whereToStart(ref);
    if (where == null) {
      if (mounted) await SettingsPage.open(context);
      return;
    }
    final id = await ref.read(conversationsProvider.notifier).open(where);
    if (id == null) return;
    await ref.read(assistantControllerProvider(id).notifier).toggleVoice();
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
                    Positioned.fill(
                      // Opaco, como el de la pantalla con conversación: el
                      // orbe es dibujo sobre un fondo casi vacío, y sin esto
                      // solo respondería donde hay pintado un punto.
                      child: TourAnchor(
                        stop: TourStop.orb,
                        child: Semantics(
                          button: true,
                          label: context.strings.orbLabel,
                          hint: context.strings.orbHint,
                          value: context.strings.asleep,
                          child: GestureDetector(
                            onTap: _talk,
                            behavior: HitTestBehavior.opaque,
                            child: const NexusOrb(state: NexusOrbState.sleep),
                          ),
                        ),
                      ),
                    ),
                    const Positioned(
                      left: NexusSpacing.s6,
                      bottom: ConversationDock.alDelSuelo,
                      child: TourAnchor(
                        stop: TourStop.dock,
                        child: ConversationDock(),
                      ),
                    ),
                    if (folders.isEmpty &&
                        ref.watch(artifactsFolderProvider) == null)
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
                                color: colors.accent,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              TourAnchor(
                stop: TourStop.composer,
                child: ComposerBar(
                  onSubmit: _startWith,
                  onFocusChanged: (_) {},
                ),
              ),
              // Fuera del `Stack` a propósito: se pinta en el `Overlay` de la app,
              // así que su sitio en el árbol da igual — pero **dentro** del Stack
              // le fijaba el ancho a cero, porque un Stack se dimensiona por sus
              // hijos sin posicionar y este mide 0. Eso dejaba el orbe con ancho
              // cero y el muelle desplazado.
              const TourOverlay(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Una palabra para lo que está pasando, como el «Dormido» del mockup.
String _statusFor(NexusOrbState state, NexusStrings strings) => switch (state) {
  NexusOrbState.sleep => strings.asleep,
  NexusOrbState.listen => strings.listening,
  NexusOrbState.think => strings.working,
  NexusOrbState.speak => strings.speaking,
};

/// Lo que ocupa el aviso flotante, para dejarle sitio sin adivinarlo.
///
/// Sale de sus partes y no de mirar la pantalla: el alto de la etiqueta —10 de fuente
/// con su interlineado—, los 3 px de relleno arriba y abajo, el borde, y un hueco para
/// que el primer mensaje no quede pegado. Escrito así, cambiar el relleno del chip no
/// vuelve a tapar la conversación sin que nadie se entere.
const _altoDelAviso = 14.0 + 3 * 2 + 2 + NexusSpacing.s3;

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
/// Una línea que se puede cerrar, del color de lo que cuenta.
///
/// El color entra por parámetro y no por el tipo del mensaje: son el mismo
/// objeto en pantalla y solo cambia lo que significan, así que duplicar el
/// widget para pintarlo en ámbar habría dejado dos sitios que arreglar.
class _AvisoChip extends StatelessWidget {
  const _AvisoChip({
    required this.message,
    required this.color,
    required this.onDismiss,
    this.accion,
  });

  final String message;
  final Color color;
  final VoidCallback onDismiss;

  /// Lo que se puede hacer con este aviso, cuando se puede hacer algo.
  ///
  /// La mayoría de los fallos solo se leen. Este hueco existe para el que **sí
  /// tiene arreglo desde aquí**: la sesión caducada, que se resuelve abriendo
  /// el navegador. Un botón que a veces está y a veces no es más honesto que
  /// uno permanente que casi nunca sirve.
  final ({String texto, VoidCallback alPulsar})? accion;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            border: Border.all(color: color.withValues(alpha: 0.35)),
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
                    color: color,
                  ),
                ),
                const SizedBox(width: NexusSpacing.s3),
                Flexible(
                  child: Text(
                    message,
                    style: NexusTypography.mono.copyWith(
                      color: color,
                      height: 1.4,
                    ),
                  ),
                ),
                if (accion case final accion?) ...[
                  const SizedBox(width: NexusSpacing.s3),
                  InkWell(
                    onTap: accion.alPulsar,
                    child: Text(
                      accion.texto,
                      style: NexusTypography.mono.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                        decorationColor: color.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: NexusSpacing.s2),
                InkWell(
                  onTap: onDismiss,
                  child: Icon(
                    Icons.close,
                    size: 13,
                    color: color.withValues(alpha: 0.7),
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
