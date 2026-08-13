import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';

/// La caja para escribirle, siempre disponible — también mientras habla o
/// trabaja.
///
/// Nació mostrando además la respuesta letra a letra («franja de subtítulos,
/// no burbujas de chat»), y eso se fue a la ventana de conversación de la
/// derecha cuando aparecieron varios hilos en paralelo: con tres conversaciones
/// hace falta poder volver sobre lo dicho, y una franja solo enseña lo último.
class SubtitleStrip extends StatefulWidget {
  const SubtitleStrip({
    super.key,
    required this.onSubmit,
    required this.onFocusChanged,
  });

  final ValueChanged<String> onSubmit;
  final ValueChanged<bool> onFocusChanged;

  @override
  State<SubtitleStrip> createState() => _SubtitleStripState();
}

class _SubtitleStripState extends State<SubtitleStrip> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() => widget.onFocusChanged(_focusNode.hasFocus);

  void _handleSubmit(String value) {
    if (value.trim().isEmpty) return;
    widget.onSubmit(value);
    _controller.clear();
  }

  /// Vaciar la caja sin enviar nada. Devuelve el cursor al campo: quien borra
  /// es porque va a reescribir, y obligarle a volver a pinchar sería un paso
  /// de más.
  void _handleClear() {
    _controller.clear();
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
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.cyan.withValues(alpha: 0.28)),
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.0, 0.7],
          colors: [
            colors.cyan.withValues(alpha: 0.045),
            colors.cyan.withValues(alpha: 0),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          NexusSpacing.s8,
          NexusSpacing.s6,
          NexusSpacing.s8,
          NexusSpacing.s7,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Enter envía; ⇧Enter hace salto de línea. Se intercepta la tecla
            // porque un campo de varias líneas trata Enter como salto por
            // defecto, y entonces no habría forma de enviar sin ratón.
            Focus(
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                if (event.logicalKey != LogicalKeyboardKey.enter) {
                  return KeyEventResult.ignored;
                }
                if (HardwareKeyboard.instance.isShiftPressed) {
                  return KeyEventResult.ignored;
                }
                _handleSubmit(_controller.text);
                return KeyEventResult.handled;
              },
              // En escritorio Flutter le cuelga una barra de desplazamiento al
              // campo en cuanto pasa de una línea, y en una caja de seis se ve
              // como un cuerpo extraño. El scroll sigue funcionando con la
              // rueda y con el cursor; lo que se quita es la barra.
              child: ScrollConfiguration(
                behavior: const _NoScrollbar(),
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _controller,
                  builder: (context, value, child) => TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    style: NexusTypography.body.copyWith(color: colors.ink),
                    // Crece hacia abajo con lo que escribes, hasta seis líneas; a
                    // partir de ahí se queda quieto y hace scroll, para que una
                    // instrucción larga no se coma la conversación de arriba.
                    minLines: 1,
                    maxLines: 6,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: context.strings.composerHint,
                      hintStyle: NexusTypography.body.copyWith(
                        color: colors.faint,
                      ),
                      // Solo cuando hay algo que borrar: un botón permanente que
                      // la mitad del tiempo no hace nada es ruido en una caja
                      // que casi siempre está vacía.
                      suffixIcon: value.text.isEmpty
                          ? null
                          : Tooltip(
                              message: context.strings.clearWhatYouWrote,
                              child: IconButton(
                                onPressed: _handleClear,
                                padding: EdgeInsets.zero,
                                splashRadius: 14,
                                iconSize: 16,
                                color: colors.faint,
                                hoverColor: colors.cyan.withValues(alpha: 0.12),
                                icon: const Icon(Icons.backspace_outlined),
                              ),
                            ),
                      // Sin esto el icono impone su altura mínima de 48 y la
                      // caja de una línea deja de ser una línea.
                      suffixIconConstraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Campo de texto sin barra de desplazamiento.
///
/// No basta con un `ScrollConfiguration` que pida `scrollbars: false`: cuando
/// el campo es de varias líneas, `EditableText` toma el comportamiento heredado
/// y le vuelve a poner `scrollbars: true` él mismo. Lo que sí respeta es el
/// `buildScrollbar` del comportamiento de abajo, y aquí devuelve el hijo tal
/// cual. El desplazamiento no se toca: solo desaparece la barra.
class _NoScrollbar extends MaterialScrollBehavior {
  const _NoScrollbar();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

/// Cursor de la franja: parpadeo duro (on/off), no un fundido — igual que
/// el `steps(1)` del mockup.
class _BlinkingCursor extends StatefulWidget {
  const _BlinkingCursor({required this.color});

  final Color color;

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Opacity(
        opacity: _controller.value < 0.5 ? 1 : 0,
        child: Container(
          width: 2,
          height: 28,
          margin: const EdgeInsets.only(left: 6),
          color: widget.color,
        ),
      ),
    );
  }
}
