import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/nexus_colors.dart';
import 'package:nexus/core/design_system/nexus_radius.dart';
import 'package:nexus/core/design_system/nexus_spacing.dart';
import 'package:nexus/core/design_system/nexus_typography.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/workspace/data/datasources/cierre_de_la_corrida_data_source.dart';
import 'package:nexus/features/workspace/presentation/providers/corrida_providers.dart';
import 'package:nexus/features/workspace/presentation/providers/plan_firmado_providers.dart';

/// La tarea de esta rama de punta a punta: qué se acordó, cómo salió el gate, cuánto
/// llevó, y cómo se cierra.
///
/// **Cerrar no publica.** Ni commitea, ni sube, ni abre nada — y se dice en la hoja,
/// porque «cerrar» en una herramienta de trabajo suena a que algo sale. Lo que hace es
/// escribir la bitácora y devolver el resumen para pegarlo donde haga falta.
///
/// Se abre desde el chip de la rama y no desde un menú: la corrida **es** la rama, y ese
/// chip ya estaba en la barra diciendo cuál.
class CorridaSheet {
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
  final _narrativa = TextEditingController();
  var _copiado = false;

  /// Cancelar pide otra cosa —por qué se abandona, no qué se hizo— y por eso enseña otro
  /// texto de ayuda en vez de aceptar cualquier frase en la misma casilla.
  var _cancelando = false;

  @override
  void dispose() {
    _narrativa.dispose();
    super.dispose();
  }

  Future<void> _cerrar(ComoTermino como) async {
    await ref
        .read(cerrarLaCorridaProvider(widget.donde).notifier)
        .cerrar(como, _narrativa.text);
    if (!mounted) return;
    _narrativa.clear();
    setState(() => _cancelando = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;
    final corrida = ref.watch(laCorridaProvider(widget.donde));
    final lleva = corrida.llevaEn(DateTime.now());

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
            strings.corridaTitle,
            style: NexusTypography.lead.copyWith(color: colors.ink),
          ),
          const SizedBox(height: NexusSpacing.s3),
          Text(
            strings.corridaBody,
            style: NexusTypography.body.copyWith(color: colors.mute),
          ),

          if (lleva != null) ...[
            const SizedBox(height: NexusSpacing.s4),
            Text(
              '${strings.corridaOpenFor} '
              '${lleva.inHours > 0 ? strings.durationHoursMinutes(lleva.inHours, lleva.inMinutes % 60) : strings.durationMinutes(lleva.inMinutes)}',
              style: NexusTypography.label.copyWith(color: colors.accent),
            ),
          ],

          const SizedBox(height: NexusSpacing.s5),
          // El resumen está siempre, abierta o cerrada: mientras dura sirve para ver qué
          // falta —el gate que no corrió, el plan que no se firmó— y no solo para contarlo
          // al final.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(NexusSpacing.s3),
            decoration: BoxDecoration(
              color: colors.rise,
              border: Border.all(color: colors.rule),
              borderRadius: BorderRadius.circular(NexusRadius.sm),
            ),
            child: SelectableText(
              corrida.resumen(strings),
              style: NexusTypography.mono.copyWith(color: colors.mute),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const ValueKey('copiar-el-resumen'),
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: corrida.resumen(strings)),
                );
                if (mounted) setState(() => _copiado = true);
              },
              child: Text(
                _copiado ? strings.corridaCopied : strings.corridaCopy,
                style: NexusTypography.label.copyWith(
                  color: _copiado ? colors.ok : colors.accent,
                ),
              ),
            ),
          ),

          if (corrida.abierta) ...[
            const SizedBox(height: NexusSpacing.s3),
            TextField(
              controller: _narrativa,
              style: NexusTypography.body.copyWith(color: colors.ink),
              decoration: InputDecoration(
                isDense: true,
                hintText: _cancelando
                    ? strings.corridaCancelHint
                    : strings.corridaNarrativeHint,
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
            const SizedBox(height: NexusSpacing.s2),
            Text(
              strings.corridaNotPublishing,
              style: NexusTypography.mono.copyWith(color: colors.faint),
            ),
            const SizedBox(height: NexusSpacing.s3),
            Wrap(
              spacing: NexusSpacing.s2,
              children: [
                TextButton(
                  key: const ValueKey('cerrar-la-corrida'),
                  onPressed: () => _cerrar(ComoTermino.cerrada),
                  child: Text(
                    strings.corridaClose.toUpperCase(),
                    style: NexusTypography.label.copyWith(color: colors.accent),
                  ),
                ),
                TextButton(
                  key: const ValueKey('cerrar-sin-produccion'),
                  onPressed: () => _cerrar(ComoTermino.sinProduccion),
                  child: Text(
                    strings.corridaCloseNoProd,
                    style: NexusTypography.label.copyWith(color: colors.mute),
                  ),
                ),
                TextButton(
                  key: const ValueKey('cancelar-la-corrida'),
                  // El primer toque solo cambia lo que se pide: cancelar borra la
                  // medición, así que se escribe el motivo con la pregunta delante y no
                  // después de haberla contestado sin querer.
                  onPressed: () => _cancelando
                      ? _cerrar(ComoTermino.cancelada)
                      : setState(() => _cancelando = true),
                  child: Text(
                    strings.corridaCancel,
                    style: NexusTypography.label.copyWith(
                      color: _cancelando ? colors.err : colors.faint,
                    ),
                  ),
                ),
              ],
            ),
          ],

          if (corrida.anteriores.isNotEmpty) ...[
            const SizedBox(height: NexusSpacing.s3),
            Text(
              strings.corridaPrevious(corrida.anteriores.length),
              style: NexusTypography.mono.copyWith(color: colors.faint),
            ),
          ],
        ],
      ),
    );
  }
}
