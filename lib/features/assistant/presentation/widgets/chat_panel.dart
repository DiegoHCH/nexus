import 'package:flutter/material.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/features/assistant/presentation/state/chat_message.dart';

/// La conversación entera a la derecha: lo que pediste y lo que respondió.
///
/// El diseño original insistía en «franja de subtítulos, no burbujas de chat»,
/// y para una sola conversación hablada tenía razón. Con tres hilos en paralelo
/// deja de tenerla: hace falta poder volver sobre lo dicho sin repreguntar.
/// Se conserva del HUD lo que sigue valiendo —monoespaciada, sin globos de
/// colores, autor en etiqueta— para que siga pareciendo un panel de control y
/// no una app de mensajería.
class ChatPanel extends StatefulWidget {
  const ChatPanel({super.key, required this.messages});

  final List<ChatMessage> messages;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _controller = ScrollController();

  @override
  void didUpdateWidget(covariant ChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messages == oldWidget.messages) return;
    // Seguir el final mientras se escribe: si no, la respuesta crece por
    // debajo del borde y hay que perseguirla a mano.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_controller.hasClients) return;
      _controller.jumpTo(_controller.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (widget.messages.isEmpty) {
      return Center(
        child: Text(
          'PÍDELE ALGO — POR VOZ CON ⌥ESPACIO O ESCRIBIENDO ABAJO',
          textAlign: TextAlign.center,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
      );
    }

    return ListView.builder(
      controller: _controller,
      padding: const EdgeInsets.only(bottom: NexusSpacing.s5),
      itemCount: widget.messages.length,
      itemBuilder: (context, index) => _Turn(message: widget.messages[index]),
    );
  }
}

class _Turn extends StatelessWidget {
  const _Turn({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isUser = message.author == ChatAuthor.user;

    return Padding(
      padding: const EdgeInsets.only(bottom: NexusSpacing.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                isUser ? 'TÚ' : 'NEXUS',
                style: NexusTypography.label.copyWith(
                  color: isUser ? colors.faint : colors.cyan,
                ),
              ),
              if (message.spoken) ...[
                const SizedBox(width: NexusSpacing.s2),
                // Marcado como hablado: si la transcripción se equivocó, saber
                // que venía del micrófono explica el disparate.
                Icon(Icons.graphic_eq, size: 11, color: colors.faint),
              ],
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            message.text,
            style: NexusTypography.body.copyWith(
              color: isUser ? colors.mute : colors.ink,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
