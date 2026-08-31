import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:nexus/features/assistant/presentation/widgets/composer/composer_chips.dart';
import 'package:nexus/features/assistant/presentation/widgets/composer/composer_menus.dart';
import 'package:nexus/features/emulators/presentation/widgets/dispositivos_menu.dart';
import 'package:nexus/features/e2e/presentation/providers/e2e_providers.dart';
import 'package:nexus/features/e2e/presentation/widgets/pruebas_sheet.dart';
import 'package:nexus/features/run/presentation/widgets/correr_menu.dart';
import 'package:nexus/features/assistant/presentation/widgets/composer/usage_menu.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/assistant/domain/usecases/attached_files.dart';
import 'package:nexus/features/assistant/domain/usecases/lo_que_ya_escribi.dart';
import 'package:nexus/features/assistant/presentation/widgets/attachment_strip.dart';
import 'package:nexus/features/assistant/presentation/state/session_meter.dart';
import 'package:nexus/features/onboarding/presentation/state/tour_state.dart';
import 'package:nexus/features/onboarding/presentation/widgets/tour_anchor.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/domain/entities/workspace.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

/// La caja para escribirle, con sus controles alrededor.
///
/// Los ajustes de la conversación —dónde trabaja, con qué cuenta, qué puede
/// tocar— estaban arriba del todo, lejos de donde se escribe. Aquí están donde
/// se decide: se lee la carpeta justo antes de pedir algo, y se cambia el
/// permiso sin cruzar la pantalla. Es la forma del compositor de Claude Code, y
/// se adopta por lo mismo que la organización del vault: si la herramienta que
/// tienes al lado ya resolvió dónde va cada cosa, inventar otra distribución
/// solo obliga a aprender dos.
///
/// Arriba, lo que **no** se cambia a menudo: carpeta, cuenta, si se le puede
/// hablar. Abajo, lo que sí: el permiso, el micrófono, y a la derecha el modelo
/// y cuánto contexto lleva ocupado.
class ComposerBar extends ConsumerStatefulWidget {
  const ComposerBar({
    super.key,
    required this.onSubmit,
    required this.onFocusChanged,
    this.loQueYaEscribi = const [],
    this.folderPath,
    this.meter = const SessionMeter(),
    this.voiceActive = false,
    this.onToggleVoice,
  });

  /// Recibe **el texto y las rutas por separado**, no un texto ya compuesto.
  /// Quién decide qué se le manda a Claude es el controlador, que además tiene
  /// los textos del idioma; la caja solo dice qué se escribió y qué se adjuntó.
  final void Function(String text, List<String> attachments) onSubmit;
  final ValueChanged<bool> onFocusChanged;

  /// Lo que ya se envió en esta conversación, en el orden en que se envió.
  ///
  /// La caja lo recorre con las flechas. Llega de fuera y no se guarda aquí
  /// porque **ya existe**: son los turnos del usuario de esta conversación, y un
  /// segundo almacén con lo mismo habría que mantenerlo sincronizado para
  /// siempre. Ver [LoQueYaEscribi].
  final List<String> loQueYaEscribi;

  final String? folderPath;
  final SessionMeter meter;
  final bool voiceActive;
  final VoidCallback? onToggleVoice;

  @override
  ConsumerState<ComposerBar> createState() => _ComposerBarState();
}

class _ComposerBarState extends ConsumerState<ComposerBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  /// Las rutas que acompañan a lo que se está escribiendo. Viven aquí y no en
  /// un provider porque son del mensaje a medio escribir, no de la
  /// conversación: al enviarlo se van con él.
  var _attachments = <String>[];

  /// Hay algo encima esperando a que lo sueltes.
  var _dragging = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() => widget.onFocusChanged(_focusNode.hasFocus);

  void _handleSubmit(String value) {
    if (value.trim().isEmpty && _attachments.isEmpty) return;
    widget.onSubmit(value, _attachments);
    _controller.clear();
    setState(() => _attachments = const []);
  }

  void _attach(Iterable<String> paths) =>
      setState(() => _attachments = AttachedFiles.add(_attachments, paths));

  void _detach(String path) =>
      setState(() => _attachments = [..._attachments]..remove(path));

  void _handleClear() {
    _controller.clear();
    // Borrar la caja se lleva también los adjuntos: son parte del mensaje que
    // se está descartando, y dejarlos pegados a un texto que ya no existe los
    // colaría en la siguiente petición.
    setState(() => _attachments = const []);
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final workspace = ref.watch(workspaceControllerProvider);
    // La carpeta de esta conversación; y sin conversación abierta —el primer
    // arranque, antes de escribir nada— la activa, que es donde iría a parar lo
    // que escribas. Sin esto, al abrir la app no salía ni modelo ni esfuerzo y
    // tampoco había dónde elegirlos: los controles existían apagados.
    final folder =
        workspace.folders
            .where((item) => item.path == widget.folderPath)
            .firstOrNull ??
        workspace.folders
            .where((item) => item.path == workspace.activePath)
            .firstOrNull ??
        workspace.folders.firstOrNull;

    return DropTarget(
      // Alrededor de toda la barra y no solo de la caja de texto: quien
      // arrastra apunta al sitio donde escribe, no a un rectángulo de 30 px de
      // alto, y fallar el blanco devuelve el archivo a su carpeta de un salto.
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (detail) {
        setState(() => _dragging = false);
        _attach(detail.files.map((file) => file.path));
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: colors.accent.withValues(alpha: _dragging ? 0.9 : 0.28),
              width: _dragging ? 2 : 1,
            ),
          ),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0.0, 0.7],
            colors: [
              colors.accent.withValues(alpha: _dragging ? 0.16 : 0.045),
              colors.accent.withValues(alpha: 0),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            NexusSpacing.s8,
            NexusSpacing.s4,
            NexusSpacing.s8,
            NexusSpacing.s5,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ComposerChips(folder: folder, folderPath: widget.folderPath),
              const SizedBox(height: NexusSpacing.s3),
              AttachmentStrip(paths: _attachments, onRemove: _detach),
              _Field(
                controller: _controller,
                focusNode: _focusNode,
                loQueYaEscribi: widget.loQueYaEscribi,
                onSubmit: _handleSubmit,
                onClear: _handleClear,
              ),
              const SizedBox(height: NexusSpacing.s3),
              _Controls(
                folder: folder,
                // `workingDirectory` y no `path`: con una raíz de varios repos,
                // el proyecto que se corre es el repo elegido y no la carpeta de
                // arriba, que es donde no hay `launch.json`.
                proyecto: folder?.workingDirectory ?? widget.folderPath,
                workspace: workspace,
                meter: widget.meter,
                voiceActive: widget.voiceActive,
                onToggleVoice: widget.onToggleVoice,
                onAttach: _attach,
              ),
              // Solo mientras hay algo encima. macOS ya enseña la miniatura de lo
              // que llevas colgando del cursor; lo que falta decir es que **este**
              // sitio lo acepta, y eso se dice una vez y en pequeño.
              if (_dragging) ...[
                const SizedBox(height: NexusSpacing.s2),
                Row(
                  children: [
                    Icon(
                      Icons.file_download_outlined,
                      size: 13,
                      color: colors.accent,
                    ),
                    const SizedBox(width: NexusSpacing.s2),
                    Text(
                      context.strings.dropHere,
                      style: NexusTypography.label.copyWith(
                        color: colors.accent,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatefulWidget {
  const _Field({
    required this.controller,
    required this.focusNode,
    required this.loQueYaEscribi,
    required this.onSubmit,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final List<String> loQueYaEscribi;
  final ValueChanged<String> onSubmit;
  final VoidCallback onClear;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  /// Dónde va el recorrido del historial. Vive en el campo y no más arriba
  /// porque se pierde a propósito al enviar: lo que se envió ya no está a medias.
  var _historial = const LoQueYaEscribi();

  /// Mueve el recorrido y pone en la caja lo que toque.
  ///
  /// **La lista se rearma solo cuando no se está recorriendo.** Mientras se
  /// recorre hay que congelarla: si llegara un turno nuevo a mitad de recorrido,
  /// las posiciones se moverían bajo los pies y la siguiente flecha daría un
  /// salto que nadie pidió.
  ///
  /// Sin `setState`: `_historial` solo se lee al pulsar una tecla, y de repintar
  /// el campo ya se encarga el controlador. Un `setState` aquí reconstruiría la
  /// barra entera para nada.
  void _mueveElHistorial({required bool atras}) {
    final antes = _historial.recorriendo
        ? _historial
        : LoQueYaEscribi.de(widget.loQueYaEscribi);

    final despues = atras
        ? antes.haciaAtras(widget.controller.text)
        : antes.haciaAdelante();
    _historial = despues;

    // Nada se movió: se llegó al tope del historial, o no hay historial. La caja
    // **no se toca**, y eso es lo que hace que una flecha de más no borre lo que
    // llevas escrito.
    if (despues.posicion == antes.posicion) return;
    widget.controller.value = TextEditingValue(
      text: despues.texto,
      // El cursor al final, que es donde uno quiere seguir escribiendo cuando
      // recupera algo para cambiarle una palabra.
      selection: TextSelection.collapsed(offset: despues.texto.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final controller = widget.controller;
    final focusNode = widget.focusNode;
    final onSubmit = widget.onSubmit;
    final onClear = widget.onClear;

    // Enter envía; ⇧Enter hace salto de línea. Se intercepta la tecla porque un
    // campo de varias líneas trata Enter como salto por defecto, y entonces no
    // habría forma de enviar sin ratón.
    //
    // Y las flechas recorren el historial, como en una terminal — pero **solo
    // desde el borde**: ver [LoQueYaEscribi.navegaHaciaAtras]. La caja llega a
    // seis líneas, así que arriba también sirve para moverse dentro de lo que
    // estás escribiendo.
    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        final cursor = controller.selection.baseOffset;
        if (event.logicalKey == LogicalKeyboardKey.arrowUp && cursor >= 0) {
          if (!LoQueYaEscribi.navegaHaciaAtras(controller.text, cursor)) {
            return KeyEventResult.ignored;
          }
          _mueveElHistorial(atras: true);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown && cursor >= 0) {
          // Hacia delante solo cuando ya se estaba recorriendo: si no, abajo es
          // una flecha normal y secuestrarla no haría nada visible salvo comerse
          // el movimiento del cursor.
          if (!_historial.recorriendo ||
              !LoQueYaEscribi.navegaHaciaAdelante(controller.text, cursor)) {
            return KeyEventResult.ignored;
          }
          _mueveElHistorial(atras: false);
          return KeyEventResult.handled;
        }

        if (event.logicalKey != LogicalKeyboardKey.enter) {
          return KeyEventResult.ignored;
        }
        if (HardwareKeyboard.instance.isShiftPressed) {
          return KeyEventResult.ignored;
        }
        _historial = _historial.suelta();
        onSubmit(controller.text);
        return KeyEventResult.handled;
      },
      // En escritorio Flutter le cuelga una barra de desplazamiento al campo en
      // cuanto pasa de una línea, y en una caja de seis se ve como un cuerpo
      // extraño. El scroll sigue funcionando con la rueda y con el cursor.
      child: ScrollConfiguration(
        behavior: const _NoScrollbar(),
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, child) => TextField(
            controller: controller,
            focusNode: focusNode,
            style: NexusTypography.body.copyWith(color: colors.ink),
            minLines: 1,
            maxLines: 6,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              hintText: context.strings.composerHint,
              hintStyle: NexusTypography.body.copyWith(color: colors.faint),
              suffixIcon: value.text.isEmpty
                  ? null
                  : Tooltip(
                      message: context.strings.clearWhatYouWrote,
                      child: IconButton(
                        onPressed: onClear,
                        padding: EdgeInsets.zero,
                        splashRadius: 14,
                        iconSize: 16,
                        color: colors.faint,
                        hoverColor: colors.accent.withValues(alpha: 0.12),
                        icon: const Icon(Icons.backspace_outlined),
                      ),
                    ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 28,
                minHeight: 28,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lo que se toca a menudo: permiso, micrófono, y a la derecha lo que informa.
class _Controls extends ConsumerWidget {
  const _Controls({
    required this.folder,
    required this.proyecto,
    required this.workspace,
    required this.meter,
    required this.voiceActive,
    required this.onToggleVoice,
    required this.onAttach,
  });

  /// La carpeta de esta conversación: de ella salen la cuenta, el modelo y el
  /// esfuerzo, porque los tres se deciden por carpeta.
  final PairedFolder? folder;

  /// La carpeta de trabajo, para las configuraciones de arranque.
  ///
  /// **La de trabajo y no la emparejada**, que con una raíz de varios repos no
  /// son la misma: lo que se corre es el repo elegido. Es el mismo criterio con
  /// el que el compositor decide qué rama enseñar.
  final String? proyecto;
  final Workspace workspace;
  final SessionMeter meter;
  final bool voiceActive;
  final VoidCallback? onToggleVoice;
  final void Function(Iterable<String>) onAttach;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final canWrite = workspace.permission.canWrite;

    return Row(
      children: [
        // El permiso, como un menú y no como un interruptor: al desplegarlo se
        // lee la consecuencia de cada opción, que es lo que hay que saber para
        // elegir bien y no cabía junto a un conmutador.
        PopupMenuButton<FilePermission>(
          color: colors.deep,
          tooltip: '',
          initialValue: workspace.permission,
          onSelected: ref
              .read(workspaceControllerProvider.notifier)
              .setPermission,
          itemBuilder: (context) => [
            for (final option in FilePermission.values)
              PopupMenuItem<FilePermission>(
                value: option,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.canWrite ? strings.canEdit : strings.readOnly,
                      style: NexusTypography.data.copyWith(color: colors.ink),
                    ),
                    Text(
                      option.canWrite
                          ? strings.canEditExplainer
                          : strings.readOnlyExplainer,
                      style: NexusTypography.mono.copyWith(color: colors.faint),
                    ),
                  ],
                ),
              ),
          ],
          child: Row(
            children: [
              Icon(
                canWrite ? Icons.edit_outlined : Icons.lock_outline,
                size: 13,
                color: canWrite ? colors.warn : colors.faint,
              ),
              const SizedBox(width: 6),
              Text(
                canWrite ? strings.canEdit : strings.readOnly,
                style: NexusTypography.label.copyWith(
                  color: canWrite ? colors.warn : colors.faint,
                ),
              ),
              Icon(Icons.expand_more, size: 14, color: colors.faint),
            ],
          ),
        ),
        const SizedBox(width: NexusSpacing.s3),
        MoreMenu(onAttach: onAttach),
        const SizedBox(width: NexusSpacing.s2),
        if (onToggleVoice case final toggle?)
          IconButton(
            onPressed: toggle,
            tooltip: voiceActive
                ? strings.micOpenHint
                : strings.sayStopToInterrupt,
            iconSize: 15,
            splashRadius: 15,
            color: voiceActive ? colors.accent : colors.faint,
            icon: Icon(voiceActive ? Icons.mic : Icons.mic_none),
          ),
        // **Los dispositivos, aquí y no solo en Ajustes.** Arrancar un emulador
        // se hace a media faena; irse a Ajustes para eso es salirse de la
        // conversación. Va junto al micrófono porque son la misma clase de cosa:
        // herramientas de la sesión, no estado del proyecto —eso es la fila de
        // arriba.
        const DispositivosMenu(),
        // Correr la app va justo al lado de los dispositivos porque son los dos
        // pasos del mismo gesto: encender dónde, y lanzar qué.
        CorrerMenu(proyecto: proyecto),
        // Y las pruebas, el tercer paso del mismo gesto: enciendes dónde, lanzas
        // qué, y compruebas que sigue funcionando.
        _BotonDePruebas(proyecto: proyecto),
        const Spacer(),
        ModelMenu(folder: folder, meter: meter),
        const SizedBox(width: NexusSpacing.s3),
        EffortMenu(folder: folder),
        const SizedBox(width: NexusSpacing.s3),
        TourAnchor(
          stop: TourStop.meter,
          child: UsageMenu(meter: meter, claudeProfile: folder?.claudeProfile),
        ),
      ],
    );
  }
}

class _NoScrollbar extends MaterialScrollBehavior {
  const _NoScrollbar();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

/// El icono que abre las pruebas.
///
/// **Un sheet y no un menú desplegable**, al contrario que los dispositivos y el
/// correr: una prueba corriendo se mira un rato —ocho pasos, medio minuto— y un
/// popover se cierra al primer clic fuera. Es el mismo motivo por el que los
/// documentos abren en sheet.
class _BotonDePruebas extends ConsumerWidget {
  const _BotonDePruebas({required this.proyecto});

  final String? proyecto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final corriendo = ref.watch(pruebaEnMarchaProvider)?.viva ?? false;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          onPressed: () => PruebasSheet.open(context, proyecto: proyecto),
          tooltip: context.strings.e2eTitle,
          iconSize: 15,
          splashRadius: 15,
          color: corriendo ? colors.accent : colors.faint,
          icon: const Icon(Icons.checklist_rtl),
        ),
        if (corriendo)
          Positioned(
            top: 2,
            right: 2,
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: colors.accent,
                shape: BoxShape.circle,
                border: Border.all(color: colors.void_, width: 1),
              ),
            ),
          ),
      ],
    );
  }
}
