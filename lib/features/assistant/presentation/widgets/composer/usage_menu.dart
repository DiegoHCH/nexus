import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/assistant/data/datasources/claude_usage_data_source.dart';
import 'package:nexus/features/assistant/presentation/providers/model_providers.dart';
import 'package:nexus/features/assistant/presentation/widgets/gauge.dart';
import 'package:nexus/features/assistant/presentation/state/session_meter.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
/// El cupo y la ventana de contexto.
///
/// Aparte de los otros menús porque no es un menú de elegir: es un panel de
/// lectura, con su propio dial y sus propias cuentas.

/// El círculo de la derecha: contexto de esta conversación y cupo de la
/// suscripción.
///
/// Son dos cosas distintas y por eso están juntas: puedes tener la ventana medio
/// vacía y el cupo de la semana en las últimas. El contexto lo reporta el CLI en
/// cada turno; el cupo sale del mismo endpoint que usa la app de la barra de
/// menús.
class UsageMenu extends ConsumerWidget {
  const UsageMenu({
    super.key,required this.meter, required this.claudeProfile});

  final SessionMeter meter;
  final String? claudeProfile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final context_ = meter.contextPercent ?? 0;

    // `tooltip: ''` quita el globo **y también la etiqueta**: para un lector de
    // pantalla este círculo no existía. Se envuelve para devolverla sin traer el
    // globo de vuelta, y el valor lleva las cifras — que es lo que hay dentro.
    return Semantics(
      button: true,
      label: strings.contextWindow,
      value: meter.contextLabel ?? strings.noReadingYet,
      child: PopupMenuButton<void>(
      color: colors.deep,
      tooltip: '',
      onOpened: () => ref.invalidate(claudeUsageProvider(claudeProfile)),
      itemBuilder: (context) => [
        PopupMenuItem<void>(
          enabled: false,
          child: SizedBox(
            width: 300,
            child: Consumer(
              builder: (context, ref, _) {
                final leido = ref.watch(claudeUsageProvider(claudeProfile));
                final usage = leido.value?.usage;
                final estado = leido.value?.state;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Gauge(
                      label: strings.contextWindow,
                      percent: context_,
                      // Sin turno todavía no hay medida: se dice, en vez de
                      // enseñar «0 / 1,0M», que se leería como una ventana
                      // vacía comprobada y no como una que nadie ha mirado.
                      //
                      // Corto, y no la frase de la cuenta: esa habla de una
                      // sesión caducada, que aquí ni viene a cuento —esto mide
                      // la ventana de contexto— y además desbordaba el panel.
                      value: meter.contextLabel ?? strings.noReadingYet,
                      warnAt: 85,
                    ),
                    const SizedBox(height: NexusSpacing.s4),
                    Text(
                      usage == null ||
                              (ref.watch(claudeProfilesProvider).value ??
                                          const [])
                                      .length <
                                  2
                          ? strings.usageLimits
                          : '${strings.usageLimits} · ${usage.account}',
                      style: NexusTypography.label.copyWith(
                        color: colors.faint,
                      ),
                    ),
                    const SizedBox(height: NexusSpacing.s3),
                    if (usage == null)
                      // Sin dato no se dibuja una barra a cero: se leería como
                      // «no has gastado nada», que es lo contrario de «no se
                      // sabe». Y **el motivo importa**: que no haya sesión y
                      // que la lectura esté caducada piden cosas distintas de
                      // quien lo lee — iniciar sesión, o nada en absoluto.
                      Text(
                        switch (estado) {
                          UsageState.staleReading => strings.usageStale,
                          UsageState.unreachable => strings.usageUnreachable,
                          _ => strings.usageUnavailable,
                        },
                        style: NexusTypography.mono.copyWith(
                          color: colors.faint,
                        ),
                      )
                    else ...[
                      Gauge(
                        label: strings.usageFiveHour,
                        percent: usage.fiveHourPercent,
                        note: _resets(strings, usage.fiveHourResetsAt),
                      ),
                      const SizedBox(height: NexusSpacing.s3),
                      Gauge(
                        label: strings.usageWeekly,
                        percent: usage.weeklyPercent,
                        note: _resets(strings, usage.weeklyResetsAt),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ],
      child: Tooltip(
        message: meter.contextLabel == null
            ? strings.contextWindow
            : '${strings.contextWindow} · ${meter.contextLabel}',
        child: CustomPaint(
          size: const Size(15, 15),
          painter: _ContextDial(
            fraction: meter.contextFraction,
            ring: colors.rule,
            fill: context_ >= 85 ? colors.warn : colors.accent,
          ),
        ),
      ),
      ),
    );
  }

  static String? _resets(NexusStrings strings, DateTime? when) {
    if (when == null) return null;
    final falta = when.difference(DateTime.now());
    if (falta.isNegative) return null;
    final horas = falta.inHours;
    final minutos = falta.inMinutes % 60;
    return strings.resetsIn(
      horas > 0 ? 'en ${horas}h ${minutos}m' : 'en ${minutos}m',
    );
  }
}

/// El círculo que se llena según lo ocupada que esté la ventana de contexto.
///
/// Relleno y no un arco fino: lo que se mira de reojo mientras se trabaja es
/// «cuánto queda», y un sector macizo se lee sin enfocar la vista. El aro
/// alrededor está siempre entero para que se vea **de cuánto** se está
/// llenando — un sector suelto no dice contra qué se compara.
class _ContextDial extends CustomPainter {
  const _ContextDial({
    required this.fraction,
    required this.ring,
    required this.fill,
  });

  final double fraction;
  final Color ring;
  final Color fill;

  /// Grosor del aro. El mismo para el aro entero y para lo que se llena, que es
  /// lo que hace que se lea como **un** aro llenándose y no como dos círculos.
  static const _stroke = 2.5;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - _stroke / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // El aro entero, siempre: es contra lo que se compara lo lleno. Sin él, un
    // arco suelto no dice de cuánto se está llenando.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..color = ring,
    );
    if (fraction <= 0) return;

    // **Se llena el borde, no el interior.** Un sector macizo creciendo desde
    // el centro se lee como una tarta —cuánto vale este trozo— y lo que se
    // quiere leer aquí es un recorrido: cuánto se ha consumido del total, como
    // un anillo de progreso. Desde arriba y en el sentido del reloj.
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * fraction.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..strokeCap = StrokeCap.round
        ..color = fill,
    );
  }

  @override
  bool shouldRepaint(_ContextDial old) =>
      old.fraction != fraction || old.fill != fill;
}
