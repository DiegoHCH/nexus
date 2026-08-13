import 'package:flutter/material.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/assistant/presentation/state/activity_layout.dart';
import 'package:nexus/features/assistant/presentation/state/assistant_hud_state.dart';

/// La columna «Ahora mismo» (D03 del mockup): qué archivo lee, qué comando
/// corre.
///
/// Su razón de ser está en el tracker y conviene no perderla: sin esto,
/// «pensando…» durante dos minutos es indistinguible de estar colgado. Por eso
/// muestra la acción concreta y no una barra de progreso: una barra dice que
/// algo pasa, esto dice **qué** pasa.
class ActivityColumn extends StatelessWidget {
  const ActivityColumn({super.key, required this.items, required this.onStop});

  final List<ActivityItem> items;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final done = items.where((item) => item.done).length;
    // Claude reparte trabajo solo: lo que hace un subagente cuelga de la
    // delegación que lo mandó, en vez de caer al mismo nivel y hacer parecer
    // que quien delegó está haciendo el trabajo que acaba de repartir.
    final rows = layoutActivity(items);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              context.strings.rightNow,
              style: NexusTypography.label.copyWith(color: colors.cyan),
            ),
            const Spacer(),
            if (items.isNotEmpty)
              Text(
                '$done de ${items.length}',
                style: NexusTypography.data.copyWith(color: colors.faint),
              ),
          ],
        ),
        const SizedBox(height: NexusSpacing.s4),
        Flexible(
          child: ListView.builder(
            shrinkWrap: true,
            reverse: true,
            itemCount: rows.length,
            itemBuilder: (context, index) {
              // Al revés: lo último que hace es lo que importa, y con la lista
              // invertida se queda pegado abajo sin tener que perseguirlo.
              return _ActivityRow(row: rows[rows.length - 1 - index]);
            },
          ),
        ),
        const SizedBox(height: NexusSpacing.s6),
        OutlinedButton(
          onPressed: onStop,
          child: Text(context.strings.stopButton),
        ),
      ],
    );
  }
}

class _ActivityRow extends StatefulWidget {
  const _ActivityRow({required this.row});

  final ActivityRow row;

  @override
  State<_ActivityRow> createState() => _ActivityRowState();
}

class _ActivityRowState extends State<_ActivityRow> {
  /// Cerrado por defecto: la columna existe para saber **qué** pasa de un
  /// vistazo. El detalle es para cuando algo no cuadra, y entonces se pide.
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.row.item;
    final colors = context.colors;
    // En curso es el paso más hondo que sigue vivo: es el que lleva el punto
    // cian encendido, para saber dónde está el trabajo sin leer.
    final running = widget.row.running;
    final isChild = widget.row.depth > 0;
    final dotColor = item.done
        ? colors.ok
        : (running ? colors.cyan : colors.rule2);

    return Container(
      // Los pasos del subagente van metidos hacia dentro y con una guía a la
      // izquierda: se lee de un vistazo que ese trabajo es de quien recibió el
      // encargo, no de quien lo repartió.
      padding: EdgeInsets.only(left: isChild ? NexusSpacing.s5 : 0),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.rule),
          left: isChild
              ? BorderSide(color: colors.cyan.withValues(alpha: 0.25), width: 2)
              : BorderSide.none,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: item.hasDetail ? () => setState(() => _open = !_open) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: NexusSpacing.s3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(
                      top: 5,
                      right: NexusSpacing.s3,
                    ),
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dotColor,
                        boxShadow: running
                            ? [
                                BoxShadow(
                                  color: colors.cyan.withValues(alpha: 0.8),
                                  blurRadius: 12,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item.description,
                      style: NexusTypography.mono.copyWith(
                        color: running ? colors.ink : colors.faint,
                        height: 1.5,
                      ),
                    ),
                  ),
                  if (item.writes)
                    Padding(
                      padding: const EdgeInsets.only(left: NexusSpacing.s3),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.warn.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(NexusRadius.sm),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          // El permiso y su consecuencia, juntos: el interruptor
                          // dice que puede escribir y esta etiqueta dice cuándo
                          // lo está haciendo de verdad.
                          child: Text(
                            context.strings.writesTag,
                            style: NexusTypography.label.copyWith(
                              color: colors.warn,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (item.hasDetail)
                    Padding(
                      padding: const EdgeInsets.only(left: NexusSpacing.s3),
                      child: Icon(
                        _open ? Icons.expand_less : Icons.expand_more,
                        size: 14,
                        color: colors.faint,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_open) _Detail(item: item),
        ],
      ),
    );
  }
}

/// Lo que pasa por dentro: el comando literal y lo que devolvió.
///
/// Va en monoespaciada y con scroll propio porque aquí sí se lee carácter a
/// carácter — es la diferencia entre «hizo algo con git» y «corrió
/// `git log --oneline -20` y devolvió esto».
class _Detail extends StatelessWidget {
  const _Detail({required this.item});

  final ActivityItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(left: 18, bottom: NexusSpacing.s3),
      padding: const EdgeInsets.all(NexusSpacing.s3),
      decoration: BoxDecoration(
        color: colors.void_.withValues(alpha: 0.5),
        border: Border.all(color: colors.rule),
        borderRadius: BorderRadius.circular(NexusRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.detail case final detail?) ...[
            Text(
              context.strings.ranLabel,
              style: NexusTypography.label.copyWith(color: colors.faint),
            ),
            const SizedBox(height: 4),
            SelectableText(
              detail,
              style: NexusTypography.mono.copyWith(
                color: colors.cyan,
                height: 1.45,
              ),
            ),
          ],
          if (item.output case final output?) ...[
            if (item.detail != null) const SizedBox(height: NexusSpacing.s3),
            Text(
              context.strings.returnedLabel,
              style: NexusTypography.label.copyWith(color: colors.faint),
            ),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: SelectableText(
                  output,
                  style: NexusTypography.mono.copyWith(
                    color: colors.mute,
                    height: 1.45,
                  ),
                ),
              ),
            ),
          ] else if (!item.done)
            Text(
              context.strings.stillRunning,
              style: NexusTypography.mono.copyWith(color: colors.faint),
            ),
        ],
      ),
    );
  }
}
