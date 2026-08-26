import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/nexus_colors.dart';
import 'package:nexus/core/design_system/nexus_radius.dart';
import 'package:nexus/core/design_system/nexus_spacing.dart';
import 'package:nexus/core/design_system/nexus_typography.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/workspace/data/datasources/gate_del_repo_data_source.dart';
import 'package:nexus/features/workspace/presentation/providers/gate_del_repo_providers.dart';
import 'package:nexus/features/workspace/presentation/providers/plan_firmado_providers.dart';

/// El gate del repositorio: qué comando es, cómo salió y el botón para correrlo.
///
/// **Se llama gate y no «pruebas» a propósito.** En esta app «Pruebas» ya son las de
/// Maestro sobre la interfaz, y son otra cosa: aquellas se miran mientras pasan, esto es
/// una puerta que se abre o no. Dos cosas con el mismo nombre en la misma barra es cómo
/// alguien acaba corriendo la que no era.
///
/// **Se ofrece, no se lanza.** Nada aquí ocurre por iniciativa propia: un gate tarda
/// minutos y consume la máquina, así que correrlo es una decisión de quien está delante.
/// Lo que sí hace la pantalla es no dejar que el estado se lea mal — un verde de antes de
/// los últimos cambios se dice que no cubre, en vez de enseñarse como verde a secas.
class GateSheet {
  static void open(BuildContext context, DondeMirar donde) =>
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => _Hoja(donde: donde),
      );
}

class _Hoja extends ConsumerStatefulWidget {
  const _Hoja({required this.donde});

  final DondeMirar donde;

  @override
  ConsumerState<_Hoja> createState() => _HojaState();
}

class _HojaState extends ConsumerState<_Hoja> {
  /// El controlador lo posee la hoja y no el `build`, como en la de firmar: uno creado al
  /// dibujar se usa después de morir.
  final _motivo = TextEditingController();
  final _salida = TextEditingController();

  @override
  void dispose() {
    _motivo.dispose();
    _salida.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final donde = widget.donde;
    final colors = context.colors;
    final strings = context.strings;
    final gate = ref.watch(gateDelRepoProvider(donde)).value;
    final huella = ref.watch(huellaDelArbolProvider(donde.carpeta)).value;
    final corriendo = gate?.resultado == ResultadoDelGate.corriendo;

    final (estado, color) = switch (gate) {
      null => (strings.gateNotRun, colors.faint),
      final g when g.resultado == ResultadoDelGate.corriendo => (
        strings.gateRunning,
        colors.accent,
      ),
      final g when g.resultado == ResultadoDelGate.rojo => (
        strings.gateRed,
        colors.err,
      ),
      // El verde que ya no cubre se dice entero, no se degrada a un color: es la
      // diferencia entre «pasó» y «pasó antes de lo que acabas de escribir».
      //
      // Y el declarado nunca se pinta de verde. Puede ser igual de cierto y no es lo
      // mismo: uno es un número y el otro la palabra de alguien.
      final g when g.resultado == ResultadoDelGate.verde && !g.cubre(huella) =>
        (strings.gateStale, colors.warn),
      final g when g.resultado == ResultadoDelGate.verde && !g.quien.medido => (
        strings.gateDeclared,
        colors.mute,
      ),
      final g when g.resultado == ResultadoDelGate.verde => (
        strings.gateGreen,
        colors.ok,
      ),
      _ => (strings.gateNotRun, colors.faint),
    };

    return Container(
      decoration: BoxDecoration(
        color: colors.deep,
        border: Border(top: BorderSide(color: colors.rule)),
      ),
      padding: EdgeInsets.fromLTRB(
        NexusSpacing.s6,
        NexusSpacing.s5,
        NexusSpacing.s6,
        NexusSpacing.s6 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.gateTitle,
            style: NexusTypography.lead.copyWith(color: colors.ink),
          ),
          const SizedBox(height: NexusSpacing.s3),
          Text(
            strings.gateBody,
            style: NexusTypography.body.copyWith(color: colors.mute),
          ),
          const SizedBox(height: NexusSpacing.s5),

          Text(
            strings.gateCommand,
            style: NexusTypography.label.copyWith(color: colors.accent),
          ),
          const SizedBox(height: NexusSpacing.s2),
          Text(
            gate?.comando ?? '—',
            style: NexusTypography.data.copyWith(color: colors.ink),
          ),

          if (gate?.aviso case final aviso?) ...[
            const SizedBox(height: NexusSpacing.s3),
            Text(
              aviso,
              style: NexusTypography.mono.copyWith(color: colors.warn),
            ),
          ],

          const SizedBox(height: NexusSpacing.s5),
          Row(
            children: [
              Text(estado, style: NexusTypography.label.copyWith(color: color)),
              if (gate?.cuando case final cuando? when !corriendo) ...[
                const SizedBox(width: NexusSpacing.s3),
                Text(
                  strings.gateWhen(
                    DateTime.now().toUtc().difference(cuando).inMinutes,
                  ),
                  style: NexusTypography.mono.copyWith(color: colors.faint),
                ),
              ],
              const Spacer(),
              TextButton(
                key: const ValueKey('correr-el-gate'),
                onPressed: corriendo || gate?.comando == null
                    ? null
                    : () => ref
                          .read(gateDelRepoProvider(donde).notifier)
                          .correr(),
                child: Text(
                  strings.gateRun.toUpperCase(),
                  style: NexusTypography.label.copyWith(
                    color: corriendo ? colors.faint : colors.accent,
                  ),
                ),
              ),
            ],
          ),

          // Declarar, **solo cuando el gate no cubre lo que hay**. Con un verde medido y
          // vigente no hay nada que declarar, y ofrecerlo ahí sería invitar a sustituir
          // una medición que ya existe por una afirmación.
          if (gate != null && gate.comando != null && !gate.cubre(huella)) ...[
            const SizedBox(height: NexusSpacing.s5),
            Text(
              strings.gateDeclareTitle,
              style: NexusTypography.label.copyWith(color: colors.mute),
            ),
            const SizedBox(height: NexusSpacing.s2),
            TextField(
              controller: _salida,
              minLines: 2,
              maxLines: 4,
              style: NexusTypography.mono.copyWith(color: colors.ink),
              decoration: InputDecoration(
                isDense: true,
                hintText: strings.gateDeclareHint,
                hintStyle: NexusTypography.mono.copyWith(color: colors.rule2),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: colors.rule),
                  borderRadius: BorderRadius.circular(NexusRadius.sm),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: colors.accent),
                  borderRadius: BorderRadius.circular(NexusRadius.sm),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const ValueKey('declarar-el-gate'),
                // Sin salida no se registra nada, y por eso el botón no la pide dos
                // veces: es lo único que separa esto de un botón que pone verde.
                onPressed: corriendo
                    ? null
                    : () => ref
                          .read(gateDelRepoProvider(donde).notifier)
                          .declarar(_salida.text),
                child: Text(
                  strings.gateDeclareAction,
                  style: NexusTypography.label.copyWith(color: colors.mute),
                ),
              ),
            ),
          ],

          // Publicar igual, **solo sobre un verde que ya no cubre**. No aparece con el
          // gate sin correr ni en rojo, y no por ahorrar sitio: ahí no hay una caducidad
          // que justificar. Un botón que existiera siempre convertiría la puerta en un
          // trámite de dos clics.
          if (gate != null &&
              gate.resultado == ResultadoDelGate.verde &&
              !gate.cubre(huella)) ...[
            const SizedBox(height: NexusSpacing.s5),
            Text(
              strings.gateAnywayTitle,
              style: NexusTypography.label.copyWith(color: colors.warn),
            ),
            const SizedBox(height: NexusSpacing.s2),
            if (gate.aunque case final aunque?
                when aunque.huella != null && aunque.huella == huella)
              Text(
                strings.gateAnywayWritten(aunque.motivo),
                style: NexusTypography.mono.copyWith(color: colors.mute),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _motivo,
                      style: NexusTypography.body.copyWith(color: colors.ink),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: strings.gateAnywayHint,
                        hintStyle: NexusTypography.mono.copyWith(
                          color: colors.rule2,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: colors.rule),
                          borderRadius: BorderRadius.circular(NexusRadius.sm),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: colors.accent),
                          borderRadius: BorderRadius.circular(NexusRadius.sm),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: NexusSpacing.s3),
                  TextButton(
                    key: const ValueKey('publicar-igual'),
                    onPressed: () => ref
                        .read(gateDelRepoProvider(donde).notifier)
                        .publicarIgual(_motivo.text),
                    child: Text(
                      strings.gateAnywayAction,
                      style: NexusTypography.label.copyWith(
                        color: colors.accent,
                      ),
                    ),
                  ),
                ],
              ),
          ],

          if (gate?.salida case final salida?
              when salida.trim().isNotEmpty) ...[
            const SizedBox(height: NexusSpacing.s3),
            // La cola y con scroll: lo que hace falta de un gate rojo es el final, y
            // meterlo entero en la hoja la volvería impracticable.
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              width: double.infinity,
              padding: const EdgeInsets.all(NexusSpacing.s3),
              decoration: BoxDecoration(
                color: colors.rise,
                border: Border.all(color: colors.rule),
                borderRadius: BorderRadius.circular(NexusRadius.sm),
              ),
              child: SingleChildScrollView(
                reverse: true,
                child: SelectableText(
                  salida.trimRight(),
                  style: NexusTypography.mono.copyWith(color: colors.mute),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
