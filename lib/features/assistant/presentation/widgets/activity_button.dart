import 'package:flutter/material.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/assistant/presentation/state/activity_layout.dart';
import 'package:nexus/features/assistant/presentation/state/assistant_hud_state.dart';

/// El trabajo en curso, reducido a una línea que se pulsa.
///
/// La lista de pasos vivía debajo de la conversación y crecía con el turno:
/// quince filas empujando hacia arriba lo que se acababa de decir, justo
/// mientras se lee. El detalle no se pierde —está entero a un clic, en la
/// misma clase de ventana que los documentos—, pero deja de competir con el
/// chat.
///
/// 🔴 **Lo que no se hace es dejar solo una ruleta.** La columna existía porque
/// «pensando…» durante dos minutos es indistinguible de estar colgado, y un
/// giro sin texto vuelve exactamente a eso: dice que algo pasa y no dice qué.
/// Por eso el botón lleva el paso en curso y cuántos van. Es la misma promesa
/// de antes en una línea en vez de en quince, no una promesa más pequeña.
class ActivityButton extends StatelessWidget {
  const ActivityButton({super.key, required this.items, required this.onOpen});

  final List<ActivityItem> items;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;

    // El mismo «en curso» que pinta la columna: el paso vivo más hondo, que con
    // un subagente trabajando es el suyo y no la delegación que lo espera.
    // Sale de `layoutActivity` en vez de calcularse otra vez aquí — dos reglas
    // para lo mismo acaban discrepando, y esta ya se equivocó una vez.
    ActivityItem? enCurso;
    for (final row in layoutActivity(items)) {
      if (row.running) enCurso = row.item;
    }
    // Entre una herramienta y la siguiente no hay ninguna corriendo, y eso son
    // segundos de nada: se dice «trabajando» en vez de dejar la línea vacía.
    final done = items.where((item) => item.done).length;

    return Semantics(
      button: true,
      label: strings.seeActivity,
      value: enCurso?.description ?? strings.working,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(NexusRadius.md),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: NexusSpacing.s3,
              vertical: NexusSpacing.s2,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: colors.rule),
              borderRadius: BorderRadius.circular(NexusRadius.md),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Indeterminada a propósito: no se sabe cuántos pasos quedan, y
                // una barra que finge saberlo miente en cada turno.
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation(colors.accent),
                  ),
                ),
                const SizedBox(width: NexusSpacing.s3),
                Flexible(
                  child: Text(
                    enCurso?.description ?? strings.working,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NexusTypography.mono.copyWith(color: colors.ink),
                  ),
                ),
                if (items.isNotEmpty) ...[
                  const SizedBox(width: NexusSpacing.s3),
                  Text(
                    strings.stepsProgress(done, items.length),
                    style: NexusTypography.data.copyWith(color: colors.faint),
                  ),
                ],
                const SizedBox(width: NexusSpacing.s2),
                Icon(Icons.chevron_right, size: 14, color: colors.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
