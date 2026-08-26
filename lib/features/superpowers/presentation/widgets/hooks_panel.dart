import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/superpowers/domain/entities/nexus_hook.dart';
import 'package:nexus/features/superpowers/domain/usecases/fallos_por_cuenta.dart';
import 'package:nexus/features/superpowers/presentation/providers/superpowers_providers.dart';

/// Los ganchos de Nexus en una cuenta: qué hacen, cómo están y el botón para cambiarlo.
///
/// **Es una lista cerrada, no un catálogo que se busca.** Los ganchos los escribe esta
/// app y viajan dentro de ella: no hay un repo de dónde traerlos ni versiones que elegir,
/// y por eso esto no se parece al panel de skills. Lo único que se decide aquí es si el
/// mecanismo está puesto en esta cuenta o no.
class HooksPanel extends ConsumerStatefulWidget {
  const HooksPanel({
    super.key,
    required this.configDir,
    this.tambienEn = const [],
  });

  final String configDir;

  /// Las demás cuentas donde replicar lo que se instale aquí. Misma regla que las skills,
  /// y aquí duele más: un gancho puesto en una sola cuenta hace que el mismo proyecto
  /// niegue una edición o no según con qué cuenta se abra, sin decir por qué.
  final List<String> tambienEn;

  @override
  ConsumerState<HooksPanel> createState() => _HooksPanelState();
}

class _HooksPanelState extends ConsumerState<HooksPanel> {
  var _busy = false;
  String? _error;

  Future<void> _act(Future<String?> Function() accion) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await accion();
    // Las demás cuentas también: si se instaló en todas, el estado que enseñan sus
    // pestañas es de antes.
    for (final configDir in [widget.configDir, ...widget.tambienEn]) {
      ref.invalidate(estadoDeLosGanchosProvider(configDir));
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;
    final estados =
        ref.watch(estadoDeLosGanchosProvider(widget.configDir)).value ??
        const <String, EstadoDelGancho>{};

    return ListView(
      children: [
        Text(
          strings.hooksExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s5),
        for (final gancho in NexusHook.catalogo)
          _GanchoRow(
            titulo: switch (gancho.id) {
              'inyectar_reglas' => strings.hooksInjectRules,
              _ => strings.hooksRequirePlan,
            },
            explicacion: switch (gancho.id) {
              'inyectar_reglas' => strings.hooksInjectRulesWhat,
              _ => strings.hooksRequirePlanWhat,
            },
            estado: estados[gancho.id] ?? EstadoDelGancho.ausente,
            busy: _busy,
            onInstalar: () => _act(
              () => ref
                  .read(hooksDataSourceProvider)
                  .installEn(
                    [widget.configDir, ...widget.tambienEn],
                    gancho,
                    statusMessage: gancho.id == 'inyectar_reglas'
                        ? strings.hooksInjectingStatus
                        : null,
                  )
                  .then(FallosPorCuenta.primero),
            ),
            // Quitar es **solo de esta cuenta**, aunque instalar sea de todas. Borrar de
            // cuentas que no se están mirando es un efecto que nadie pidió, y con el
            // gancho del plan significaría dejar sin gate carpetas de otro perfil.
            onQuitar: () => _act(
              () => ref
                  .read(hooksDataSourceProvider)
                  .remove(widget.configDir, gancho),
            ),
          ),
        if (_error case final mensaje?) ...[
          const SizedBox(height: NexusSpacing.s3),
          Text(
            mensaje,
            style: NexusTypography.mono.copyWith(color: colors.err),
          ),
        ],
      ],
    );
  }
}

class _GanchoRow extends StatelessWidget {
  const _GanchoRow({
    required this.titulo,
    required this.explicacion,
    required this.estado,
    required this.busy,
    required this.onInstalar,
    required this.onQuitar,
  });

  final String titulo;
  final String explicacion;
  final EstadoDelGancho estado;
  final bool busy;
  final VoidCallback onInstalar;
  final VoidCallback onQuitar;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;

    // Cada estado con su color, y el peligroso en rojo: «a medias» es el único que no se
    // nota por el síntoma —no hay error, simplemente no pasa nada— así que aquí tiene que
    // gritar más que «sin instalar», que al menos es lo que uno espera.
    final (texto, color) = switch (estado) {
      EstadoDelGancho.ausente => (strings.hooksNotInstalled, colors.faint),
      EstadoDelGancho.aMedias => (strings.hooksHalf, colors.err),
      EstadoDelGancho.desactualizado => (strings.hooksOutdated, colors.warn),
      EstadoDelGancho.alDia => (strings.hooksUpToDate, colors.ok),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: NexusSpacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  titulo,
                  style: NexusTypography.data.copyWith(color: colors.ink),
                ),
              ),
              Text(texto, style: NexusTypography.label.copyWith(color: color)),
              const SizedBox(width: NexusSpacing.s2),
              if (estado != EstadoDelGancho.alDia)
                IconButton(
                  onPressed: busy ? null : onInstalar,
                  icon: Icon(
                    estado == EstadoDelGancho.desactualizado
                        ? Icons.refresh
                        : Icons.add,
                    size: 15,
                    color: colors.accent,
                  ),
                  splashRadius: 14,
                  tooltip: estado == EstadoDelGancho.desactualizado
                      ? strings.hooksUpdate
                      : strings.hooksInstall,
                ),
              if (estado != EstadoDelGancho.ausente)
                IconButton(
                  onPressed: busy ? null : onQuitar,
                  icon: Icon(Icons.close, size: 14, color: colors.faint),
                  splashRadius: 14,
                  tooltip: strings.hooksRemove,
                ),
            ],
          ),
          Text(
            explicacion,
            style: NexusTypography.mono.copyWith(color: colors.faint),
          ),
        ],
      ),
    );
  }
}
