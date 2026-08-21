import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/nexus_colors.dart';
import 'package:nexus/features/remote/domain/remote_mirror.dart';
import 'package:nexus/features/remote/presentation/providers/mirror_providers.dart';
import 'package:nexus/features/remote/presentation/providers/outbox_providers.dart';
import 'package:nexus/features/remote/presentation/widgets/link_badge.dart';
import 'package:nexus/features/remote/presentation/widgets/write_phrase_sheet.dart';
import 'package:nexus/core/design_system/nexus_spacing.dart';
import 'package:nexus/core/design_system/nexus_typography.dart';
import 'package:nexus/features/remote/presentation/widgets/turn_block.dart';

/// Una conversación: lo que está haciendo, lo que respondió, y el compositor.
class ConversationPage extends ConsumerStatefulWidget {
  const ConversationPage({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends ConsumerState<ConversationPage> {
  final _campo = TextEditingController();
  final _scroll = ScrollController();
  var _mandando = false;

  @override
  void initState() {
    super.initState();
    // El permiso se pregunta al abrir. No se hereda de otra conversación: la
    // carpeta de cada una concede lo suyo, así que un valor compartido diría que
    // puedes escribir en una donde no.
    Future.microtask(() async {
      final notifier = ref.read(mirrorProvider.notifier);
      await ref
          .read(writePermissionProvider.notifier)
          .consultar(widget.conversationId);
      // El historial se pide al abrir, no antes: la lista de conversaciones no lo
      // trae, y traerlo con la lista sería mandar por 4G el pasado de tres
      // conversaciones para leer el de una.
      await notifier.masHistorial(widget.conversationId);
    });
  }

  @override
  void dispose() {
    _campo.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _mandar() async {
    final texto = _campo.text.trim();
    if (texto.isEmpty) return;
    setState(() => _mandando = true);

    // Todo va por la cola, con red y sin ella. **El campo se vacía en cuanto se
    // encola**, no cuando el Mac contesta: lo que el usuario acaba de escribir ya
    // está guardado, y dejarlo en el campo invita a mandarlo otra vez.
    final cupo = await ref
        .read(mirrorProvider.notifier)
        .mandar(widget.conversationId, texto);

    if (!mounted) return;
    setState(() => _mandando = false);
    if (cupo) {
      _campo.clear();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Hay demasiados encargos esperando. Espera a que se manden.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final conv = ref.watch(conversationProvider(widget.conversationId));

    // Se cerró en el Mac mientras estaba abierta aquí. Pasa: el teléfono guarda ids
    // y el Mac vive su vida. Se dice y se sale, en vez de dejar una pantalla que ya
    // no refleja nada.
    if (conv == null) {
      return Scaffold(
        backgroundColor: colors.void_,
        appBar: AppBar(backgroundColor: colors.void_),
        body: Center(
          child: Text(
            'Esta conversación ya no está abierta en el Mac',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.mute),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colors.void_,
      appBar: AppBar(
        backgroundColor: colors.void_,
        title: Text(
          conv.nombre.split('/').last,
          style: TextStyle(color: colors.ink, fontSize: 16),
        ),
        actions: const [
          Padding(padding: EdgeInsets.only(right: 16), child: LinkBadge()),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (conv.percent != null) _Medidor(conversacion: conv),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.all(20),
                children: [
                  // Más arriba lo más viejo: se lee hacia abajo, como una
                  // conversación.
                  if (conv.masHistorial != null)
                    Center(
                      child: TextButton(
                        key: const ValueKey('mas-historial'),
                        onPressed: () => ref
                            .read(mirrorProvider.notifier)
                            .masHistorial(widget.conversationId),
                        child: const Text('Ver lo anterior'),
                      ),
                    ),
                  for (final mensaje in conv.history)
                    _Mensaje(mensaje: mensaje),
                  if (conv.history.isNotEmpty) const SizedBox(height: 8),
                  if (conv.steps.isNotEmpty) _Pasos(pasos: conv.steps),
                  if (conv.reply.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: SelectableText(
                        conv.reply,
                        key: const ValueKey('respuesta'),
                        style: TextStyle(color: colors.ink, height: 1.5),
                      ),
                    ),
                  if (conv.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        conv.error!,
                        style: TextStyle(color: colors.err),
                      ),
                    ),
                  // Lo que está esperando salir. Se enseña **aquí y no en un cajón
                  // aparte**: un encargo escrito sin cobertura que no se ve por
                  // ninguna parte se da por perdido y se vuelve a escribir.
                  _Esperando(conversationId: widget.conversationId),
                ],
              ),
            ),
            _Compositor(
              campo: _campo,
              conversacion: conv,
              mandando: _mandando,
              alMandar: _mandar,
              alDetener: () => ref
                  .read(mirrorProvider.notifier)
                  .detener(widget.conversationId),
            ),
          ],
        ),
      ),
    );
  }
}

/// Un mensaje de lo dicho antes.
class _Mensaje extends StatelessWidget {
  const _Mensaje({required this.mensaje});

  final MirroredMessage mensaje;

  @override
  Widget build(BuildContext context) {
    // Lo tuyo no se interpreta como markdown, igual que en el escritorio: un
    // asterisco que escribiste tú se queda como asterisco. Eso lo hace `TurnBlock`.
    // **Un bloque y no una burbuja.** Lo que había eran `Container` redondeados
    // alineados a un lado y a otro —la convención de una app de mensajería— y esto no
    // lo es: el teléfono no ejecuta nada, refleja. `TurnBlock` ya dibuja la pila de
    // bloques con hairline y la etiqueta arriba, que es lo que dibuja el mockup, así
    // que aquí no se repite: se usa.
    return TurnBlock(mine: mensaje.mine, text: mensaje.text);
  }
}

/// Los encargos que todavía no salieron.
class _Esperando extends ConsumerWidget {
  const _Esperando({required this.conversationId});

  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final esperando = ref.watch(pendingForProvider(conversationId));
    if (esperando.isEmpty) return const SizedBox.shrink();
    final colors = context.colors;

    return Column(
      key: const ValueKey('esperando'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final encargo in esperando)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3, right: 10),
                  child: _Marca(color: colors.rule2),
                ),
                Expanded(
                  child: Text(
                    encargo.text,
                    // En mono y no en cursiva: la cursiva era la forma de decir «esto
                    // todavía no es real», y aquí eso ya lo dice la marca apagada.
                    style: NexusTypography.mono.copyWith(color: colors.mute),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// La marca de un paso: un punto de 7 px, y nada más.
///
/// Es lo que dibuja el mockup —`.act .mk::before`— y no un icono de Material. La
/// diferencia importa porque un icono trae su propio idioma: un ✓ de Material dice
/// «tarea completada en una lista de tareas», y un punto que cambia de color dice «esto
/// pasó, esto está pasando», que es lo que un registro cuenta.
///
/// Tres colores y un halo: `rule2` lo que no ha llegado, `ok` lo hecho, y el acento con
/// resplandor lo que está ocurriendo ahora — el único elemento que brilla, igual que el
/// orbe.
class _Marca extends StatelessWidget {
  const _Marca({required this.color, this.brilla = false});

  final Color color;
  final bool brilla;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 14,
    height: 14,
    child: Center(
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: brilla
              ? [BoxShadow(color: color.withValues(alpha: 0.8), blurRadius: 12)]
              : null,
        ),
      ),
    ),
  );
}

class _Medidor extends StatelessWidget {
  const _Medidor({required this.conversacion});

  final MirroredConversation conversacion;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final porcentaje = conversacion.percent!;
    // El color por tramos, igual que en el escritorio: un número solo no dice si
    // hay que preocuparse.
    final color = porcentaje >= 85
        ? colors.err
        : porcentaje >= 60
        ? colors.warn
        : colors.accent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: porcentaje / 100,
                minHeight: 4,
                backgroundColor: colors.rule,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            // El porcentaje **como lo mandó el Mac**. Recalcularlo aquí con una
            // ventana asumida es el error que ya se cometió en el escritorio.
            '$porcentaje %',
            key: const ValueKey('medidor'),
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _Pasos extends StatelessWidget {
  const _Pasos({required this.pasos});

  final List<MirroredStep> pasos;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final paso in pasos)
          Container(
            // Hairline entre pasos, como los bloques de arriba: es el mismo sistema, y
            // una lista con separadores propios se leería como otra app.
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.rule)),
            ),
            padding: const EdgeInsets.symmetric(vertical: NexusSpacing.s3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: _Marca(
                    // El que escribe manda sobre lo demás: es la única forma que tiene
                    // el teléfono de decir que algo está tocando archivos, y eso
                    // importa más que si ya terminó.
                    color: paso.writes
                        ? colors.warn
                        : paso.done
                        ? colors.ok
                        : colors.accent,
                    brilla: !paso.done,
                  ),
                ),
                Expanded(
                  child: Text(
                    paso.text,
                    style: NexusTypography.mono.copyWith(
                      color: paso.writes
                          ? colors.warn
                          : paso.done
                          ? colors.faint
                          : colors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Compositor extends ConsumerWidget {
  const _Compositor({
    required this.campo,
    required this.conversacion,
    required this.mandando,
    required this.alMandar,
    required this.alDetener,
  });

  final TextEditingController campo;
  final MirroredConversation conversacion;
  final bool mandando;
  final VoidCallback alMandar;
  final VoidCallback alDetener;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final hasta = ref.watch(writePermissionProvider).value;
    final puedeEscribir = hasta != null && DateTime.now().isBefore(hasta);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: colors.deep,
        border: Border(top: BorderSide(color: colors.rule)),
      ),
      child: Column(
        children: [
          // El permiso se dice **antes de escribir el encargo**, no al mandarlo.
          // Enterarse de que era solo lectura después de teclear tres frases es
          // hacer trabajo para tirarlo.
          InkWell(
            key: const ValueKey('permiso'),
            onTap: () => mostrarFraseDeEscritura(context, ref),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(
                    puedeEscribir ? Icons.edit : Icons.lock_outline,
                    size: 14,
                    color: puedeEscribir ? colors.ok : colors.mute,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    puedeEscribir
                        ? 'puede editar hasta las ${_hora(hasta)}'
                        : 'solo lectura · toca para abrir con tu frase',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: puedeEscribir ? colors.ok : colors.mute,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('encargo'),
                  controller: campo,
                  minLines: 1,
                  maxLines: 4,
                  style: TextStyle(color: colors.ink),
                  decoration: InputDecoration(
                    hintText: 'Qué hay que hacer',
                    hintStyle: TextStyle(color: colors.faint),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Mientras trabaja, el botón es **detener** y no mandar: mandar otro
              // encima es lo que en el escritorio pone el segundo encargo en cola, y
              // en un teléfono eso se hace sin darse cuenta.
              if (conversacion.streaming)
                IconButton(
                  key: const ValueKey('detener'),
                  onPressed: alDetener,
                  icon: const Icon(Icons.stop_circle_outlined),
                  color: colors.err,
                )
              else
                IconButton(
                  key: const ValueKey('mandar'),
                  onPressed: mandando ? null : alMandar,
                  icon: const Icon(Icons.arrow_upward),
                  color: colors.accent,
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _hora(DateTime cuando) =>
      '${cuando.hour.toString().padLeft(2, '0')}:'
      '${cuando.minute.toString().padLeft(2, '0')}';
}
