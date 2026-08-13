import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
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
          context.strings.askSomething,
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
                isUser ? context.strings.you : context.strings.nexus,
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
          // Lo tuyo se enseña tal cual lo escribiste: interpretar markdown en
          // lo que uno teclea convertiría un `*` en cursiva sin haberlo
          // pedido. Lo que responde Claude sí viene en markdown —tablas,
          // listas, bloques de código— y hasta ahora salía crudo.
          if (isUser)
            SelectableText(
              message.text,
              style: NexusTypography.body.copyWith(
                color: colors.mute,
                height: 1.5,
              ),
            )
          else
            _Answer(text: message.text),
        ],
      ),
    );
  }
}

/// La respuesta de Claude, con su markdown puesto.
///
/// Nació como texto plano porque la franja de subtítulos pintaba una frase
/// hablada, y por ahí entraron respuestas escritas de cuarenta líneas: tablas
/// con `| Commit | Qué hace |` a la vista y asteriscos por todas partes.
///
/// El estilo no es el de una app de notas: monoespaciada para el código, cian
/// para lo que se ejecuta y tablas ajustadas al ancho en vez de desbordar la
/// ventana — esto sigue siendo un panel de control.
class _Answer extends StatelessWidget {
  const _Answer({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final body = NexusTypography.body.copyWith(color: colors.ink, height: 1.5);
    final mono = NexusTypography.mono.copyWith(color: colors.cyan);

    return MarkdownBody(
      data: text,
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: body,
        a: body.copyWith(color: colors.cyan),
        strong: body.copyWith(fontWeight: FontWeight.w600),
        em: body.copyWith(fontStyle: FontStyle.italic),
        h1: NexusTypography.title.copyWith(color: colors.ink),
        h2: NexusTypography.title.copyWith(color: colors.ink),
        h3: body.copyWith(fontWeight: FontWeight.w600),
        listBullet: body,
        code: mono,
        codeblockPadding: const EdgeInsets.all(NexusSpacing.s3),
        codeblockDecoration: BoxDecoration(
          color: colors.void_.withValues(alpha: 0.5),
          border: Border.all(color: colors.rule),
          borderRadius: BorderRadius.circular(NexusRadius.sm),
        ),
        blockquote: body.copyWith(color: colors.mute),
        blockquotePadding: const EdgeInsets.only(left: NexusSpacing.s3),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: colors.cyan.withValues(alpha: 0.4),
              width: 2,
            ),
          ),
        ),
        tableHead: NexusTypography.label.copyWith(color: colors.faint),
        tableBody: NexusTypography.mono.copyWith(color: colors.mute),
        tableBorder: TableBorder.all(color: colors.rule),
        tableCellsPadding: const EdgeInsets.symmetric(
          horizontal: NexusSpacing.s3,
          vertical: 6,
        ),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.rule)),
        ),
      ),
    );
  }
}
