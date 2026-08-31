import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/agenda/presentation/providers/el_vigilante_de_la_agenda.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/workspace/presentation/pages/settings/settings_chooser.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

/// Los avisos de agenda: lo único de Nexus que ocurre sin que se lo pidas.
///
/// Nace apagado y el interruptor es lo primero de la sección, no lo último:
/// toda la app está construida sobre que el trabajo lo disparas tú, así que
/// esto es la excepción y se enseña como tal.
class AvisosSection extends ConsumerWidget {
  const AvisosSection({super.key});

  /// Las opciones de cuánto antes. Cortas y cerradas: un campo de minutos
  /// invita a escribir 90, y un aviso hora y media antes no saca a nadie de
  /// donde está.
  static const minutos = [2, 5, 10, 15];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final avisos = ref.watch(elVigilanteDeLaAgendaProvider);
    final vigilante = ref.read(elVigilanteDeLaAgendaProvider.notifier);
    final carpetas = ref.watch(workspaceControllerProvider).folders;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.avisosExplainer,
            style: NexusTypography.mono.copyWith(color: colors.faint),
          ),
          const SizedBox(height: NexusSpacing.s5),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: avisos.encendidos,
            onChanged: (on) => vigilante.cambiar(encendidos: on),
            title: Text(
              strings.avisosOn,
              style: NexusTypography.body.copyWith(color: colors.ink),
            ),
          ),
          const SizedBox(height: NexusSpacing.s5),
          Text(
            strings.avisosCarpeta,
            style: NexusTypography.label.copyWith(color: colors.faint),
          ),
          const SizedBox(height: NexusSpacing.s2),
          SettingsChooser<String>(
            value: _elegida(avisos.carpeta, carpetas),
            options: ['', for (final carpeta in carpetas) carpeta.path],
            label: (ruta) =>
                ruta.isEmpty ? strings.avisosSinCarpeta : ruta.split('/').last,
            detail: (ruta) => ruta.isEmpty ? '' : ruta,
            onSelected: (ruta) =>
                vigilante.cambiar(carpeta: ruta.isEmpty ? null : ruta),
          ),
          const SizedBox(height: NexusSpacing.s5),
          Text(
            strings.avisosCuanto,
            style: NexusTypography.label.copyWith(color: colors.faint),
          ),
          const SizedBox(height: NexusSpacing.s2),
          SettingsChooser<int>(
            value: minutos.contains(avisos.minutos) ? avisos.minutos : 5,
            options: minutos,
            label: (m) => '$m min',
            onSelected: (m) => vigilante.cambiar(minutos: m),
          ),
          const SizedBox(height: NexusSpacing.s5),
          // 🔴 El botón y la hora juntos, y no el botón solo.
          //
          // La agenda en memoria **envejece sin avisar**: lo que programes a
          // media mañana no está en lo que se leyó al arrancar. Ver a qué hora
          // se leyó es lo que convierte eso en algo que puedes corregir, en vez
          // de en una ausencia de la que nadie se entera.
          Row(
            children: [
              OutlinedButton(
                onPressed: avisos.listos
                    ? () => ref
                          .read(elVigilanteDeLaAgendaProvider.notifier)
                          .releer()
                    : null,
                child: Text(strings.avisosReleer),
              ),
              const SizedBox(width: NexusSpacing.s3),
              Text(switch (avisos.ultimaLectura) {
                final cuando? => strings.avisosLeidoA(_laHora(cuando)),
                null => strings.avisosSinLeer,
              }, style: NexusTypography.data.copyWith(color: colors.faint)),
            ],
          ),
          const SizedBox(height: NexusSpacing.s5),
          Text(
            strings.avisosNota,
            style: NexusTypography.mono.copyWith(color: colors.faint),
          ),
        ],
      ),
    );
  }

  /// La guardada, si sigue emparejada. Una carpeta que se desemparejó dejaría
  /// el selector apuntando a algo que ya no existe, y el vigilante mirando un
  /// calendario que no se puede leer.
  static String _laHora(DateTime cuando) =>
      '${cuando.hour.toString().padLeft(2, '0')}:'
      '${cuando.minute.toString().padLeft(2, '0')}';

  static String _elegida(String? guardada, List<PairedFolder> carpetas) =>
      carpetas.any((c) => c.path == guardada) ? guardada! : '';
}
