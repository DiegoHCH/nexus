import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/nexus_colors.dart';
import 'package:nexus/features/remote/data/channel_link.dart';
import 'package:nexus/features/remote/domain/remote_mirror.dart';
import 'package:nexus/features/remote/presentation/providers/mirror_providers.dart';
import 'package:nexus/features/remote/presentation/widgets/link_badge.dart';
import 'package:nexus/features/remote/presentation/widgets/write_phrase_sheet.dart';

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
    Future.microtask(
      () => ref
          .read(writePermissionProvider.notifier)
          .consultar(widget.conversationId),
    );
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

    final error = await ref
        .read(mirrorProvider.notifier)
        .mandar(widget.conversationId, texto);

    if (!mounted) return;
    setState(() => _mandando = false);
    if (error == null) {
      _campo.clear();
      return;
    }
    // Se dice **qué** pasó y si se puede repetir. «No se pudo» a secas deja a quien
    // lo lee sin saber si volver a pulsar o esperar.
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_decir(error))));
  }

  String _decir(LinkError error) => switch (error.failure) {
    LinkFailure.sinConfirmacion => 'No llegó al Mac. Puedes volver a mandarlo.',
    // Reintentar esto no sirve: ya está allí, y el Mac contestaría «duplicada».
    LinkFailure.sinRespuesta => 'Llegó al Mac y no ha contestado todavía.',
    LinkFailure.desconectado => 'Sin conexión con el Mac.',
    LinkFailure.rechazada => switch (error.code) {
      'unknownConversation' => 'Esa conversación ya no está abierta en el Mac.',
      'badParams' => 'El Mac no entendió el encargo.',
      _ => 'El Mac no lo aceptó (${error.code}).',
    },
  };

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
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 10),
                  child: Icon(
                    paso.done ? Icons.check : Icons.more_horiz,
                    size: 13,
                    // Los que escriben, en el color de aviso: es la única forma que
                    // tiene el teléfono de decir que algo está tocando archivos.
                    color: paso.writes ? colors.warn : colors.mute,
                  ),
                ),
                Expanded(
                  child: Text(
                    paso.text,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: paso.writes ? colors.warn : colors.mute,
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
