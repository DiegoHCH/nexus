import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/artifacts/presentation/providers/artifacts_providers.dart';
import 'package:nexus/features/history/presentation/providers/slack_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/el_visor_de_cambios.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/features/assistant/presentation/widgets/attachment_strip.dart';
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

    // **Una sola selección para toda la conversación.** Antes cada bloque de
    // markdown y cada mensaje traía la suya —`selectable: true` monta un
    // `SelectableText` por párrafo— y eso, que parece lo mismo, es justo lo que
    // impedía arrastrar de un párrafo al siguiente: cada isla cancelaba la de
    // al lado, así que copiar una respuesta entera había que hacerlo a trozos.
    // Con el área envolviendo la lista, la selección cruza párrafos, código,
    // tablas y mensajes, y ⌘C copia lo que se ve.
    return SelectionArea(
      child: ListView.builder(
        controller: _controller,
        padding: const EdgeInsets.only(bottom: NexusSpacing.s5),
        itemCount: widget.messages.length,
        itemBuilder: (context, index) => _Turn(message: widget.messages[index]),
      ),
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
                  color: isUser ? colors.faint : colors.accent,
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
          // Los adjuntos, con su miniatura, encima del texto: es el orden en
          // que ocurrió —primero sueltas el archivo, luego escribes— y es la
          // misma tira que ya veías en la caja al adjuntarlo. Sin la ✕: aquí
          // el mensaje ya salió y quitarlo no significaría nada.
          if (message.attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: AttachmentStrip(paths: message.attachments),
            ),
          // `Text` y no `SelectableText`: la selección la pone el área que
          // envuelve la conversación entera, y una isla propia aquí volvería a
          // cortar el arrastre justo al pasar de tu mensaje a la respuesta.
          if (isUser && message.text.trim().isNotEmpty)
            Text(
              message.text,
              style: NexusTypography.body.copyWith(
                color: colors.mute,
                height: 1.5,
              ),
            )
          else if (!isUser)
            _Answer(text: message.text),
          // Lo que este turno dejó, al pie de su propio mensaje.
          //
          // Aquí y no en una barra bajo la conversación, que es donde estaba:
          // esa barra enseñaba **solo el último** encargo, así que al pedir la
          // segunda cosa desaparecía lo que había hecho la primera. Colgado del
          // mensaje, cada turno conserva lo suyo aunque subas.
          // **Y el parte cuenta como «algo que dejó»**, aunque no toque ningún
          // archivo — que es lo normal: se pide sin permiso de escritura. Esta
          // condición se escribió cuando solo había cambios y documento, y al
          // añadir el parte se quedó fuera: el botón existía y no se dibujaba
          // nunca, porque el bloque entero se saltaba antes de llegar a él.
          if (message.cambios != null ||
              message.documento != null ||
              message.esElParte)
            _LoQueDejo(message: message),
        ],
      ),
    );
  }
}

/// Los botones de lo que produjo un turno: los cambios y el documento.
///
/// Solo aparecen si hay algo detrás. Un botón que a veces no lleva a ningún
/// sitio enseña a no pulsarlo, y entonces tampoco se pulsa el día que sí lleva.
class _LoQueDejo extends ConsumerWidget {
  const _LoQueDejo({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: NexusSpacing.s2,
        children: [
          if (message.cambios case final cambios?)
            _Boton(
              icono: Icons.difference,
              texto: strings.changedFiles(cambios.fileCount),
              onTap: () => ref
                  .read(elVisorDeCambiosProvider)
                  .abrir(cambios, strings.changesTitle),
            ),
          if (message.documento case final documento?)
            _Boton(
              icono: Icons.article_outlined,
              texto: documento.split('/').last,
              onTap: () =>
                  ref.read(artifactsDataSourceProvider).open(documento),
            ),
          // Solo en el parte, y solo si Slack está configurado: un botón de
          // enviar que a veces no puede enviar enseña a no pulsarlo.
          if (message.esElParte && ref.watch(slackControllerProvider).listo)
            _ElBotonDeSlack(texto: message.text),
        ],
      ),
    );
  }
}

/// Manda el parte a Slack, y dice si llegó.
///
/// **Con estado propio y no en el mensaje**: si esto viviera en el estado de la
/// conversación, reabrirla mañana diría «enviado» de un parte que se mandó ayer.
/// Lo que importa es haberlo mandado ahora, delante de quien lo pulsó.
class _ElBotonDeSlack extends ConsumerStatefulWidget {
  const _ElBotonDeSlack({required this.texto});

  final String texto;

  @override
  ConsumerState<_ElBotonDeSlack> createState() => _ElBotonDeSlackState();
}

class _ElBotonDeSlackState extends ConsumerState<_ElBotonDeSlack> {
  bool _mandando = false;
  String? _dicho;

  Future<void> _mandar() async {
    setState(() {
      _mandando = true;
      _dicho = null;
    });
    final fallo = await ref
        .read(slackControllerProvider.notifier)
        .mandar(widget.texto);
    if (!mounted) return;
    setState(() {
      _mandando = false;
      _dicho = fallo == null
          ? context.strings.parteEnviado
          : context.strings.parteFallo(fallo);
    });
  }

  @override
  Widget build(BuildContext context) {
    final enviado = _dicho == context.strings.parteEnviado;

    return _Boton(
      icono: enviado ? Icons.check : Icons.send_outlined,
      texto: _dicho ?? context.strings.parteAlSlack,
      onTap: _mandando || enviado ? () {} : () => unawaited(_mandar()),
    );
  }
}

class _Boton extends StatelessWidget {
  const _Boton({required this.icono, required this.texto, required this.onTap});

  final IconData icono;
  final String texto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icono, size: 13, color: colors.accent),
      label: Text(
        texto,
        style: NexusTypography.mono.copyWith(color: colors.accent),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
    final mono = NexusTypography.mono.copyWith(color: colors.accent);

    return MarkdownBody(
      data: text,
      // Sin `selectable`: lo pone el área de la conversación. Ver [ChatPanel].
      selectable: false,
      styleSheet: MarkdownStyleSheet(
        p: body,
        a: body.copyWith(color: colors.accent),
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
              color: colors.accent.withValues(alpha: 0.4),
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
