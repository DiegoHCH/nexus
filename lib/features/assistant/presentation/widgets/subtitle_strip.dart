import 'package:flutter/material.dart';
import 'package:nexus/core/design_system/design_system.dart';

/// La franja de subtítulos: no es una burbuja de chat. El texto de Claude
/// aparece arriba, letra a letra a medida que llegan los `text_delta` del
/// bridge; el campo para escribir vive siempre debajo.
class SubtitleStrip extends StatefulWidget {
  const SubtitleStrip({
    super.key,
    required this.subtitle,
    required this.isStreaming,
    required this.onSubmit,
    required this.onFocusChanged,
  });

  final String subtitle;
  final bool isStreaming;
  final ValueChanged<String> onSubmit;
  final ValueChanged<bool> onFocusChanged;

  @override
  State<SubtitleStrip> createState() => _SubtitleStripState();
}

class _SubtitleStripState extends State<SubtitleStrip> {
  /// Cuánto de la ventana puede ocupar el texto antes de hacerse scroll.
  /// Es franja de subtítulos, no un panel de lectura: si se come la pantalla
  /// deja de ser lo que el diseño quería. Lo que no cabe se lee bajando.
  static const _maxSubtitleFraction = 0.45;

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() => widget.onFocusChanged(_focusNode.hasFocus);

  @override
  void didUpdateWidget(covariant SubtitleStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.subtitle == oldWidget.subtitle) return;
    // El texto llega en trozos, así que hay que seguir el final: si no, la
    // respuesta crece por debajo del borde y hay que ir bajando a mano
    // mientras habla.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  void _handleSubmit(String value) {
    if (value.trim().isEmpty) return;
    widget.onSubmit(value);
    _controller.clear();
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _controller.dispose();
    _scrollController.dispose();
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
            if (widget.subtitle.isNotEmpty)
              // Con tope y con scroll. La franja nació para una frase hablada,
              // pero por aquí también entran respuestas escritas de cuarenta
              // líneas: sin límite crecía hasta empujar el campo de texto
              // fuera de la pantalla y romper la vista entera.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight:
                      MediaQuery.sizeOf(context).height * _maxSubtitleFraction,
                ),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: NexusSpacing.s5),
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    child: RichText(
                      text: TextSpan(
                        style: NexusTypography.subtitle.copyWith(
                          color: colors.ink,
                        ),
                        children: [
                          TextSpan(text: widget.subtitle),
                          if (widget.isStreaming)
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: _BlinkingCursor(color: colors.cyan),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              style: NexusTypography.body.copyWith(color: colors.ink),
              decoration: InputDecoration(
                hintText: 'Escribe una instrucción…',
                hintStyle: NexusTypography.body.copyWith(color: colors.faint),
              ),
              onSubmitted: _handleSubmit,
            ),
          ],
        ),
      ),
    );
  }
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
