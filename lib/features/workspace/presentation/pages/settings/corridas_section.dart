import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/workspace/data/datasources/cierre_de_la_corrida_data_source.dart';
import 'package:nexus/features/workspace/presentation/providers/corrida_providers.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

/// Todas las tareas anotadas en una cuenta, abiertas y cerradas.
///
/// **Aquí es donde la medición empieza a servir.** Una corrida sola no se compara con
/// nada: lo que dice algo es ver diez seguidas y notar que el tramo del gate al cierre es
/// la mitad de la tarde. Por eso esto no es un historial bonito, es una tabla.
///
/// Va en Ajustes y no en la barra porque no se consulta mientras se trabaja —para eso está
/// el chip de la rama, que enseña la de ahora—: esto se mira al final de la semana.
class CorridasSection extends ConsumerStatefulWidget {
  const CorridasSection({super.key});

  @override
  ConsumerState<CorridasSection> createState() => _CorridasSectionState();
}

class _CorridasSectionState extends ConsumerState<CorridasSection> {
  String? _cuenta;

  /// La fila que está pidiendo confirmación para borrarse.
  ///
  /// Dos pulsaciones y no un diálogo: un diálogo para cada borrado convierte limpiar diez
  /// huérfanas en diez ventanas. Y la huérfana no lo pide — ahí no hay nada que perder.
  String? _confirmando;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;
    final cuentas = ref.watch(claudeProfilesProvider).value ?? const [];
    if (cuentas.isEmpty) {
      return Text(
        strings.statsNoAccounts,
        style: NexusTypography.mono.copyWith(color: colors.faint),
      );
    }

    // La misma regla que las estadísticas y los superpoderes: las pestañas separan cuentas
    // y solo existen si hay más de una en el Mac.
    final actual = cuentas.any((cuenta) => cuenta.path == _cuenta)
        ? _cuenta!
        : cuentas.first.path;
    final corridas =
        ref.watch(todasLasCorridasProvider(actual)).value ??
        const <CorridaEnLaLista>[];
    final huerfanas = corridas.where((c) => c.huerfana).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (cuentas.length > 1) ...[
          Row(
            children: [
              for (final cuenta in cuentas)
                Expanded(
                  child: _Tab(
                    label: cuenta.name,
                    activa: cuenta.path == actual,
                    alTocar: () => setState(() => _cuenta = cuenta.path),
                  ),
                ),
            ],
          ),
          const SizedBox(height: NexusSpacing.s4),
        ],
        Text(
          strings.corridasExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        if (huerfanas.isNotEmpty) ...[
          const SizedBox(height: NexusSpacing.s3),
          Row(
            children: [
              Expanded(
                child: Text(
                  strings.corridasOrphansFound(huerfanas.length),
                  style: NexusTypography.mono.copyWith(color: colors.warn),
                ),
              ),
              TextButton(
                key: const ValueKey('limpiar-las-huerfanas'),
                onPressed: () async {
                  for (final huerfana in huerfanas) {
                    await ref
                        .read(limpiarCorridasProvider.notifier)
                        .borrar(
                          actual,
                          huerfana.carpeta,
                          huerfana.corrida.rama,
                        );
                  }
                },
                child: Text(
                  strings.corridasCleanAll,
                  style: NexusTypography.label.copyWith(color: colors.accent),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: NexusSpacing.s4),
        if (corridas.isEmpty)
          Text(
            strings.corridasNone,
            style: NexusTypography.mono.copyWith(color: colors.faint),
          )
        else
          Expanded(
            child: ListView(
              children: [
                for (final fila in corridas)
                  _Fila(
                    fila: fila,
                    confirmando:
                        _confirmando == '${fila.carpeta}@${fila.corrida.rama}',
                    alQuitar: () {
                      final clave = '${fila.carpeta}@${fila.corrida.rama}';
                      if (fila.huerfana || _confirmando == clave) {
                        ref
                            .read(limpiarCorridasProvider.notifier)
                            .borrar(actual, fila.carpeta, fila.corrida.rama);
                        setState(() => _confirmando = null);
                        return;
                      }
                      setState(() => _confirmando = clave);
                    },
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({
    required this.fila,
    required this.alQuitar,
    this.confirmando = false,
  });

  final CorridaEnLaLista fila;
  final VoidCallback alQuitar;
  final bool confirmando;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;
    final corrida = fila.corrida;
    final cierre = corrida.cierre;

    final (estado, color) = switch (cierre?.como) {
      null => (strings.corridasOpenTag, colors.accent),
      ComoTermino.cerrada => (strings.corridasClosedTag, colors.faint),
      ComoTermino.sinProduccion => (strings.corridasNoProdTag, colors.mute),
      ComoTermino.cancelada => (strings.corridasCancelledTag, colors.faint),
    };

    // Lo que se dijo, o lo que salió. En una abierta lo único que hay es el plan, y es
    // justo lo que hace falta para reconocerla de un vistazo.
    final frase = cierre?.narrativa ?? corrida.plan ?? '';
    final cuanto = corrida.total ?? corrida.llevaEn(DateTime.now());

    return Padding(
      padding: const EdgeInsets.only(bottom: NexusSpacing.s3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Text(
              estado,
              style: NexusTypography.label.copyWith(color: color),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        corrida.rama ?? _corta(fila.carpeta),
                        overflow: TextOverflow.ellipsis,
                        style: NexusTypography.data.copyWith(color: colors.ink),
                      ),
                    ),
                    if (fila.huerfana) ...[
                      const SizedBox(width: NexusSpacing.s2),
                      Text(
                        strings.corridasOrphanTag,
                        style: NexusTypography.label.copyWith(
                          color: colors.warn,
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  // La carpeta debajo y en gris: con varios repos, la rama sola no dice
                  // de cuál es — `develop` la tienen todos.
                  frase.isEmpty
                      ? _corta(fila.carpeta)
                      : '${_corta(fila.carpeta)} · $frase',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: NexusTypography.mono.copyWith(color: colors.faint),
                ),
                // Los tramos, cuando se pudieron medir. Es el desglose que hace útil la
                // columna del total: dos tareas de tres horas no son la misma si en una
                // el gate se corrió al final.
                if (corrida.construyendo case final construyendo?)
                  if (corrida.cerrando case final cerrando?)
                    Text(
                      strings.corridasStretches(
                        _enLlano(construyendo, strings),
                        _enLlano(cerrando, strings),
                      ),
                      style: NexusTypography.mono.copyWith(color: colors.rule2),
                    ),
              ],
            ),
          ),
          const SizedBox(width: NexusSpacing.s3),
          SizedBox(
            width: 78,
            child: Text(
              // Sin dato no se escribe un cero: un tramo sin medir enseñado como «0 min»
              // convierte «no lo registramos» en «no costó nada».
              cuanto == null
                  ? '—'
                  : cuanto.inHours > 0
                  ? strings.durationHoursMinutes(
                      cuanto.inHours,
                      cuanto.inMinutes % 60,
                    )
                  : strings.durationMinutes(cuanto.inMinutes),
              textAlign: TextAlign.right,
              style: NexusTypography.mono.copyWith(color: colors.mute),
            ),
          ),
          IconButton(
            onPressed: alQuitar,
            icon: Icon(
              Icons.close,
              size: 14,
              color: confirmando ? colors.err : colors.faint,
            ),
            splashRadius: 14,
            tooltip: confirmando
                ? strings.corridasConfirmRemove
                : strings.corridasClean,
          ),
        ],
      ),
    );
  }

  static String _enLlano(Duration cuanto, NexusStrings strings) =>
      cuanto.inHours > 0
      ? strings.durationHoursMinutes(cuanto.inHours, cuanto.inMinutes % 60)
      : strings.durationMinutes(cuanto.inMinutes);

  static String _corta(String ruta) {
    final home = Platform.environment['HOME'];
    return home != null && ruta.startsWith(home)
        ? '~${ruta.substring(home.length)}'
        : ruta;
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.activa,
    required this.alTocar,
  });

  final String label;
  final bool activa;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return InkWell(
      onTap: alTocar,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: NexusSpacing.s3),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: activa ? colors.accent : colors.rule,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label.toUpperCase(),
          textAlign: TextAlign.center,
          style: NexusTypography.label.copyWith(
            color: activa ? colors.accent : colors.faint,
          ),
        ),
      ),
    );
  }
}
