import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/artifacts/domain/entities/artifact.dart';
import 'package:nexus/features/artifacts/presentation/providers/artifacts_providers.dart';
import 'package:nexus/features/history/presentation/providers/slack_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/el_visor_de_cambios.dart';
import 'package:nexus/features/assistant/presentation/providers/la_ventana_de_actividad.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:nexus/core/design_system/el_resaltado_del_codigo.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/features/assistant/presentation/widgets/attachment_strip.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/assistant/domain/usecases/los_enlaces_del_texto.dart';
import 'package:nexus/features/assistant/presentation/state/chat_message.dart';
import 'package:url_launcher/url_launcher.dart';

/// La conversación entera a la derecha: lo que pediste y lo que respondió.
///
/// El diseño original insistía en «franja de subtítulos, no burbujas de chat»,
/// y para una sola conversación hablada tenía razón. Con tres hilos en paralelo
/// deja de tenerla: hace falta poder volver sobre lo dicho sin repreguntar.
/// Se conserva del HUD lo que sigue valiendo —monoespaciada, sin globos de
/// colores, autor en etiqueta— para que siga pareciendo un panel de control y
/// no una app de mensajería.
class ChatPanel extends StatefulWidget {
  const ChatPanel({
    super.key,
    required this.messages,
    this.onRetry,
    this.etiquetaDelAgente,
  });

  /// Cómo se llama quien contesta. Opcional a propósito: sin ella se usa el
  /// nombre de la app, así que quien solo quiere pintar mensajes —los tests, y
  /// cualquier sitio futuro— no tiene que saber que esto se configura.
  final String? etiquetaDelAgente;

  /// Volver a mandar un encargo que no llegó a hacerse.
  ///
  /// Entra por parámetro en vez de leerse de un proveedor aquí dentro porque
  /// este panel no sabe de qué conversación es —recibe los mensajes ya
  /// resueltos— y hacer que lo supiera solo por esto lo ataría a una.
  final void Function(ChatMessage mensaje)? onRetry;

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
        itemBuilder: (context, index) => _Turn(
          message: widget.messages[index],
          etiqueta: widget.etiquetaDelAgente,
          onRetry: widget.onRetry,
        ),
      ),
    );
  }
}

/// 🔴 **La etiqueta llega de fuera, no se lee de un provider aquí.**
///
/// El primer intento hizo esto un `ConsumerWidget` para leer el nombre
/// configurado, y reventó **siete tests de widget** con «No ProviderScope
/// found»: pintar una conversación no necesitaba un contenedor de providers y
/// de pronto sí. Meter un `ProviderScope` en siete pruebas para que un widget
/// lea una cadena es pagar mucho por poco.
///
/// Llega como parámetro desde donde el provider ya está a mano —la pantalla— y
/// con eso este widget sigue siendo una función de sus datos. Que es además lo
/// que lo hace fácil de probar.
class _Turn extends StatelessWidget {
  const _Turn({required this.message, this.etiqueta, this.onRetry});

  /// Cómo se llama quien contesta, o `null` para el nombre de la app.
  final String? etiqueta;

  final ChatMessage message;
  final void Function(ChatMessage mensaje)? onRetry;

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
                isUser
                    ? context.strings.you
                    : etiqueta ?? context.strings.nexus,
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
              // Al otro extremo de la fila, y **solo si falló**.
              //
              // Sin esto, un encargo que se cae deja como única salida copiar
              // el mensaje y pegarlo otra vez — teniéndolo escrito ahí mismo.
              // Va aquí y no en el aviso de arriba porque el aviso es de «lo
              // último» y esto es de **este** mensaje: si mientras tanto
              // pediste otra cosa, un botón suelto ya no sabría a qué se
              // refiere.
              if (message.fallo && onRetry != null) ...[
                const Spacer(),
                _Reintentar(onTap: () => onRetry!(message)),
              ],
            ],
          ),
          const SizedBox(height: 4),
          // A qué pregunta contesta, **cuando no es la de justo arriba**.
          //
          // La cola introdujo el problema: escribes tres cosas seguidas y las
          // tres respuestas llegan después, así que el orden deja de decir a
          // cuál contesta cada una. En un intercambio normal esto no aparece,
          // porque ahí la respuesta va pegada a su pregunta y citarla sería
          // ruido.
          if (message.respondeA case final pregunta?) ...[
            _LaPreguntaCitada(pregunta),
            const SizedBox(height: NexusSpacing.s2),
          ],
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
              message.esElParte ||
              message.actividad.isNotEmpty)
            _LoQueDejo(message: message),
        ],
      ),
    );
  }
}

/// Volver a mandarlo, sin escribirlo otra vez.
///
/// Pequeño y en rojo: no es una acción del día a día, es la salida de algo que
/// se rompió. Y en la fila del autor y no bajo el texto, que es donde van las
/// cosas que **dejó** un turno — este no dejó nada, ése es el problema.
class _Reintentar extends StatelessWidget {
  const _Reintentar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final texto = context.strings.retryErrand;

    return Semantics(
      button: true,
      label: texto,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(NexusRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.refresh, size: 12, color: colors.err),
              const SizedBox(width: 4),
              Text(
                texto,
                style: NexusTypography.label.copyWith(color: colors.err),
              ),
            ],
          ),
        ),
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

    // **Una imagen se enseña, no se anuncia.** Con el botón de siempre, lo que
    // acababa de generarse era un nombre de archivo: para saber si había salido
    // bien había que abrirla. Se pinta con la misma tira que los adjuntos —la
    // miniatura del sistema, la del Finder— porque es el mismo gesto por el otro
    // lado: tú le pasas una imagen al chat y la ves; él te devuelve una y
    // también.
    final imagen = message.documento;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (imagen != null && Artifact.isImage(imagen))
            AttachmentStrip(paths: [imagen]),
          Wrap(
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
              // Los pasos de ESTE turno, cuando ya terminó.
              //
              // El botón con el giro que hay al pie de la conversación es el
              // del encargo en curso y desaparece al acabar — tiene que
              // desaparecer, porque lo que anuncia es que hay algo corriendo.
              // Lo que hizo se mira después, y después es aquí: colgado del
              // turno, guardado con la conversación, y sin caducar cuando pides
              // la segunda cosa.
              if (message.actividad.isNotEmpty)
                _Boton(
                  icono: Icons.list_alt,
                  texto: strings.stepsTaken(message.actividad.length),
                  onTap: () => ref
                      .read(laVentanaDeActividadProvider)
                      .ver(message.actividad),
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

  /// Abre el enlace, **y si no puede lo dice**.
  ///
  /// Callarse aquí es lo que hizo perder una tarde: pulsas, no pasa nada, y no
  /// hay forma de saber si el enlace no era enlace, si el sistema lo rechazó o
  /// si el código ni se ejecutó. Un fallo mudo en un gesto de un clic es peor
  /// que uno ruidoso, porque el siguiente paso es dudar de todo lo demás.
  static Future<void> _abrirEnlace(
    BuildContext context,
    String? destino,
  ) async {
    final mensajero = ScaffoldMessenger.maybeOf(context);
    void decir(String queja) {
      mensajero?.showSnackBar(
        SnackBar(
          content: Text('$queja${destino == null ? '' : ' · $destino'}'),
        ),
      );
    }

    if (destino == null || destino.isEmpty) return decir('Enlace vacío');
    final uri = Uri.tryParse(destino);
    if (uri == null) return decir('No se entiende el enlace');
    try {
      if (!await launchUrl(uri)) decir('El sistema no abrió el enlace');
    } on Object catch (error) {
      decir('$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final body = NexusTypography.body.copyWith(color: colors.ink, height: 1.5);
    final mono = NexusTypography.mono.copyWith(color: colors.accent);

    return MarkdownBody(
      // Las URLs que el modelo escribe entre comillas invertidas vuelven a ser
      // enlaces antes de pintar. Ver [LosEnlacesDelTexto].
      data: LosEnlacesDelTexto.sinComillas(text),
      // Sin `selectable`: lo pone el área de la conversación. Ver [ChatPanel].
      selectable: false,
      // **Sin esto un enlace es texto de color.** El paquete pinta el estilo de
      // `a:` igual, así que parecía pulsable y no hacía nada: se le daba clic,
      // se le daba ⌘-clic, y nada. `onTapLink` no trae valor por defecto —quien
      // dibuja decide a dónde va un enlace— y aquí no se había puesto nunca.
      onTapLink: (texto, destino, titulo) =>
          unawaited(_abrirEnlace(context, destino)),
      // **Los bloques largos se pliegan.** Ver [_BloqueDeCodigo]: la salida de un
      // `!git log` o un diff que escriba Claude pueden ser cientos de líneas, y
      // una conversación en la que un turno ocupa cinco pantallas deja de poder
      // recorrerse.
      builders: {
        'pre': _CodigoPlegable(estilo: mono, relleno: _rellenoDelCodigo),
      },
      styleSheet: MarkdownStyleSheet(
        p: body,
        // Subrayado, y no solo en color: en una conversación de texto plano el
        // color solo no dice «esto se pulsa», y menos con el acento ya usado en
        // otras cosas. Lo que es pulsable tiene que parecerlo.
        a: body.copyWith(
          color: colors.accent,
          decoration: TextDecoration.underline,
          decorationColor: colors.accent.withValues(alpha: 0.5),
        ),
        strong: body.copyWith(fontWeight: FontWeight.w600),
        em: body.copyWith(fontStyle: FontStyle.italic),
        h1: NexusTypography.title.copyWith(color: colors.ink),
        h2: NexusTypography.title.copyWith(color: colors.ink),
        h3: body.copyWith(fontWeight: FontWeight.w600),
        listBullet: body,
        code: mono,
        codeblockPadding: _rellenoDelCodigo,
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

/// El relleno del bloque de código, en un solo sitio.
///
/// Lo comparten la hoja de estilo y [_BloqueDeCodigo] porque el paquete lo
/// aplica **dentro** del scroll horizontal, no en la caja: quien pinta el
/// contenido a mano tiene que ponerlo él, y dos valores distintos se ven como
/// un bloque que salta de sitio según su largo.
const _rellenoDelCodigo = EdgeInsets.all(NexusSpacing.s3);

/// Cuántas líneas se ven de un bloque plegado.
const _lineasAlaVista = 5;

/// Desde cuántas líneas se pliega.
///
/// Doce y no seis: plegar un bloque de siete líneas molesta más de lo que
/// ahorra, porque el propio botón ocupa una línea y esconde dos. El umbral
/// tiene que dejar hueco a que plegar valga la pena.
const _sePliegaDesde = 12;

/// Pinta los bloques de código, plegando los largos.
///
/// 🔴 **Devuelve widget siempre, corto o largo.** El paquete hace
/// `if (child != null)` con lo que devuelve esto y, si es nulo, no cae al camino
/// por defecto: descarta el hijo y el bloque se pinta **vacío**. Así que aquí no
/// hay «déjalo como estaba»; el caso corto también se dibuja a mano.
class _CodigoPlegable extends MarkdownElementBuilder {
  _CodigoPlegable({required this.estilo, required this.relleno});

  final TextStyle estilo;
  final EdgeInsets relleno;

  /// El lenguaje del bloque que se está visitando ahora.
  ///
  /// 🔴 **Se guarda aquí porque `visitText` no lo recibe.** Solo llega el texto,
  /// y el lenguaje vive en la clase del hijo `code` —`language-dart`— que se ve
  /// desde el `pre`. Así que se lee al entrar y se usa al pintar. Funciona porque
  /// el paquete recorre un bloque entero antes del siguiente; si algún día
  /// intercalara, esto pintaría un bloque con la gramática del vecino.
  String? _lenguaje;

  @override
  bool isBlockElement() => true;

  @override
  void visitElementBefore(md.Element element) {
    _lenguaje = null;
    for (final hijo in element.children ?? const <md.Node>[]) {
      if (hijo is md.Element && hijo.tag == 'code') {
        _lenguaje = ElResaltadoDelCodigo.lenguajeDe(hijo.attributes['class']);
        return;
      }
    }
  }

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) => _BloqueDeCodigo(
    texto: text.text,
    lenguaje: _lenguaje,
    estilo: estilo,
    relleno: relleno,
  );
}

/// Un bloque de código con scroll horizontal y, si es largo, un pliegue.
///
/// El scroll horizontal se conserva porque es del paquete y hace falta: una
/// línea de `git log --oneline` no cabe, y envolverla rompería la única cosa que
/// hace legible un log — que los hashes queden en columna.
class _BloqueDeCodigo extends StatefulWidget {
  const _BloqueDeCodigo({
    required this.texto,
    required this.lenguaje,
    required this.estilo,
    required this.relleno,
  });

  final String texto;
  final String? lenguaje;
  final TextStyle estilo;
  final EdgeInsets relleno;

  @override
  State<_BloqueDeCodigo> createState() => _BloqueDeCodigoState();
}

class _BloqueDeCodigoState extends State<_BloqueDeCodigo> {
  final _scroll = ScrollController();
  var _desplegado = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final lineas = widget.texto.trimRight().split('\n');
    final pliega = lineas.length >= _sePliegaDesde;
    final visibles = pliega && !_desplegado
        ? lineas.take(_lineasAlaVista)
        : lineas;
    final escondidas = lineas.length - _lineasAlaVista;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // El lenguaje, discreto y arriba: es lo que un editor te dice en una
        // esquina. Solo cuando el cercado lo declaró — inventarlo para la salida
        // de un `!`, que no es ningún lenguaje, sería decir algo falso en un
        // sitio donde uno confía.
        if (widget.lenguaje != null)
          Padding(
            padding: EdgeInsets.only(
              left: widget.relleno.left,
              right: widget.relleno.right,
              top: widget.relleno.top,
            ),
            child: Text(
              widget.lenguaje!,
              style: NexusTypography.label.copyWith(color: colors.faint),
            ),
          ),
        Scrollbar(
          controller: _scroll,
          child: SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            padding: widget.relleno,
            child: Text.rich(
              ElResaltadoDelCodigo.enSpans(
                visibles.join('\n'),
                lenguaje: widget.lenguaje,
                colores: colors,
                base: widget.estilo,
              ),
            ),
          ),
        ),
        // El botón va **fuera** del scroll horizontal: dentro se iría de la
        // pantalla con la primera línea larga, que es justo el caso en que hace
        // falta.
        if (pliega)
          Padding(
            padding: EdgeInsets.only(
              left: widget.relleno.left,
              right: widget.relleno.right,
              bottom: widget.relleno.bottom,
            ),
            child: _MasOMenos(
              desplegado: _desplegado,
              escondidas: escondidas,
              color: colors.accent,
              onTap: () => setState(() => _desplegado = !_desplegado),
            ),
          ),
      ],
    );
  }
}

class _MasOMenos extends StatelessWidget {
  const _MasOMenos({
    required this.desplegado,
    required this.escondidas,
    required this.color,
    required this.onTap,
  });

  final bool desplegado;
  final int escondidas;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.strings;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(NexusRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: NexusSpacing.s1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              desplegado ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              size: 16,
              color: color,
            ),
            const SizedBox(width: NexusSpacing.s1),
            Text(
              desplegado ? s.mostrarMenos : s.masLineas(escondidas),
              style: NexusTypography.label.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// La pregunta que se está contestando, citada encima de la respuesta.
///
/// La forma es la de cualquier chat que cite —barra al canto, autor, y el texto
/// atenuado en una línea— porque es la convención que la gente ya sabe leer sin
/// que nadie se la explique. Se recorta a una línea a propósito: es una
/// referencia para reconocer cuál era, no para volver a leerla entera.
class _LaPreguntaCitada extends StatelessWidget {
  const _LaPreguntaCitada(this.pregunta);

  final String pregunta;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.only(left: NexusSpacing.s3),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: colors.accent, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.strings.you,
            style: NexusTypography.label.copyWith(color: colors.accent),
          ),
          const SizedBox(height: 2),
          Text(
            pregunta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: NexusTypography.mono.copyWith(color: colors.faint),
          ),
        ],
      ),
    );
  }
}
