import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/assistant/presentation/providers/model_providers.dart';
import 'package:nexus/features/workspace/presentation/pages/settings_page.dart';
import 'package:nexus/features/assistant/presentation/state/session_meter.dart';
import 'package:nexus/features/workspace/domain/entities/paired_folder.dart';
import 'package:nexus/features/updates/presentation/widgets/pending_dot.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
/// Los tres menús del compositor: adjuntar y ajustes, el modelo, y el esfuerzo.
///
/// Juntos porque son la misma forma repetida tres veces —un `PopupMenuButton` con
/// sus filas— y separarlos en tres archivos habría multiplicado los imports sin
/// que ninguno pese lo suficiente para vivir solo.

/// El «+»: lo que se añade a lo que estás pidiendo.
///
/// Adjuntar es **señalar una ruta**, no subir un archivo a ningún sitio: Claude
/// trabaja en tu disco y lee lo que le señales, así que copiar el contenido
/// sería duplicarlo y perder el vínculo con el original.
///
/// Lo que se añade por aquí y lo que se suelta arrastrando acaban en el mismo
/// sitio —la tira de miniaturas—, porque son el mismo gesto dicho de dos
/// formas.
class MoreMenu extends ConsumerWidget {
  const MoreMenu({
    super.key,required this.onAttach});

  final void Function(Iterable<String>) onAttach;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;

    // Mismo caso que el círculo del cupo: sin globo se quedó sin etiqueta, y
    // este es el único camino para adjuntar sin arrastrar un archivo.
    return Semantics(
      button: true,
      label: context.strings.attachFile,
      child: PopupMenuButton<String>(
      color: colors.deep,
      tooltip: '',
      onSelected: (value) async {
        switch (value) {
          case 'file':
            // Varios de una vez, como al arrastrar: elegir tres archivos de una
            // carpeta y tener que abrir el diálogo tres veces es de las cosas
            // que hacen que nadie use el botón.
            final files = await openFiles();
            if (files.isNotEmpty) onAttach(files.map((file) => file.path));
          case 'folder':
            await ref.read(workspaceControllerProvider.notifier).pairFolder();
          case 'settings':
            if (context.mounted) await SettingsPage.open(context);
        }
      },
      itemBuilder: (context) => [
        _item('file', Icons.attach_file, strings.attachFile, colors),
        _item(
          'folder',
          Icons.create_new_folder_outlined,
          strings.addFolderShort,
          colors,
        ),
        _item('settings', Icons.tune, strings.openSettings, colors),
      ],
      // Con punto rojo mientras quede una versión sin instalar: Ajustes vive
      // dentro de este menú, así que el aviso va pegado al camino que lleva a
      // la actualización.
      child: PendingDot(child: Icon(Icons.add, size: 16, color: colors.faint)),
      ),
    );
  }

  PopupMenuItem<String> _item(
    String value,
    IconData icon,
    String label,
    NexusColors colors,
  ) => PopupMenuItem<String>(
    value: value,
    child: Row(
      children: [
        Icon(icon, size: 14, color: colors.faint),
        const SizedBox(width: NexusSpacing.s3),
        Text(label, style: NexusTypography.data.copyWith(color: colors.ink)),
      ],
    ),
  );
}

/// Qué modelo pide Nexus. «El del CLI» es lo de fábrica y no un hueco: Claude
/// se usa también desde la terminal, y pisar su configuración desde aquí
/// sorprendería allí.
class ModelMenu extends ConsumerWidget {
  const ModelMenu({
    super.key,required this.folder, required this.meter});

  final PairedFolder? folder;
  final SessionMeter meter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final model = ClaudeModel.fromStored(folder?.claudeModel);
    // Lo que se usaría sin elegir nada: primero lo que reportó el CLI en este
    // turno, y si no ha corrido ninguno, lo que tenga configurado ese perfil.
    final actual =
        meter.displayModel ??
        ref.watch(claudeDefaultsProvider(folder?.claudeProfile)).value?.model ??
        // Un perfil puede no fijar modelo —`private` no lo hace—: entonces vale
        // el último con el que se le vio trabajar.
        ref.watch(seenModelsProvider)[folder?.claudeProfile ?? 'por-defecto'];
    // El que está en uso: el elegido para esta carpeta, o el del CLI.
    final vigente = model ?? ClaudeModel.fromCliName(actual);

    return PopupMenuButton<ClaudeModel?>(
      color: colors.deep,
      tooltip: '',
      // Sin carpeta no hay dónde guardarlo: el menú se abre igual, pero elegir
      // no haría nada, así que no se ofrece.
      onSelected: folder == null
          ? null
          : (option) => ref
                .read(workspaceControllerProvider.notifier)
                .setClaudeModel(folder!.path, option?.alias),
      // Sin opción «el del CLI»: lo que el CLI ya usa **es** uno de estos, y
      // sale marcado. Una entrada aparte para lo mismo obliga a saber de
      // antemano a qué modelo equivale.
      itemBuilder: (context) => [
        for (final option in ClaudeModel.values)
          PopupMenuItem<ClaudeModel?>(
            value: option,
            child: Row(
              children: [
                Text(
                  option.label,
                  style: NexusTypography.data.copyWith(color: colors.ink),
                ),
                if (option == vigente) ...[
                  const SizedBox(width: NexusSpacing.s3),
                  Icon(Icons.check, size: 13, color: colors.accent),
                ],
              ],
            ),
          ),
      ],
      child: Text(
        vigente?.label ??
            (actual == null ? strings.modelTitle : _clean(actual)),
        style: NexusTypography.label.copyWith(
          color: model == null ? colors.faint : colors.mute,
        ),
      ),
    );
  }

  /// `claude-opus-5[1m]` se enseña sin el corchete: dice el tamaño de ventana,
  /// no el modelo, y en un botón de dos centímetros estorba.
  static String _clean(String model) {
    final bracket = model.indexOf('[');
    return bracket == -1 ? model : model.substring(0, bracket);
  }
}

/// Cuánto razona antes de contestar, de más rápido a más listo.
class EffortMenu extends ConsumerWidget {
  const EffortMenu({
    super.key,required this.folder});

  final PairedFolder? folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final effort = ClaudeEffort.fromStored(folder?.claudeEffort);
    final actual = ref
        .watch(claudeDefaultsProvider(folder?.claudeProfile))
        .value
        ?.effort;
    // El vigente: el elegido aquí, o el que ese perfil tenga fijado.
    final vigente = effort ?? ClaudeEffort.fromStored(actual);

    return PopupMenuButton<ClaudeEffort?>(
      color: colors.deep,
      tooltip: '',
      onSelected: folder == null
          ? null
          : (option) => ref
                .read(workspaceControllerProvider.notifier)
                .setClaudeEffort(folder!.path, option?.flag),
      itemBuilder: (context) => [
        for (final option in ClaudeEffort.values)
          PopupMenuItem<ClaudeEffort?>(
            value: option,
            child: Row(
              children: [
                Text(
                  option.flag,
                  style: NexusTypography.data.copyWith(color: colors.ink),
                ),
                const SizedBox(width: NexusSpacing.s3),
                // Los extremos se nombran, porque «xhigh» no dice por sí solo
                // hacia qué lado tira.
                if (option == ClaudeEffort.low)
                  Text(
                    strings.effortFaster,
                    style: NexusTypography.mono.copyWith(color: colors.faint),
                  ),
                if (option == ClaudeEffort.max)
                  Text(
                    strings.effortSmarter,
                    style: NexusTypography.mono.copyWith(color: colors.faint),
                  ),
                if (option == vigente) ...[
                  const SizedBox(width: NexusSpacing.s3),
                  Icon(Icons.check, size: 13, color: colors.accent),
                ],
              ],
            ),
          ),
      ],
      child: Text(
        vigente?.flag ?? strings.effortTitle,
        style: NexusTypography.label.copyWith(
          color: effort == null ? colors.faint : colors.mute,
        ),
      ),
    );
  }
}
