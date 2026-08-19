import 'package:flutter/material.dart';
import 'package:nexus/features/workspace/presentation/pages/settings/settings_chooser.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/language_preference.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
/// El idioma de la app, que no es el del sistema salvo que se elija así.

class LanguageSection extends ConsumerWidget {
  const LanguageSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final choice = ref.watch(languageControllerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.languageTitle,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          strings.languageExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s5),
        SettingsChooser<LanguageChoice>(
          value: choice,
          options: LanguageChoice.values,
          label: (option) => switch (option) {
            LanguageChoice.system => strings.languageSystem,
            LanguageChoice.spanish => strings.languageSpanish,
            LanguageChoice.english => strings.languageEnglish,
          },
          onSelected: ref.read(languageControllerProvider.notifier).select,
        ),
      ],
    );
  }
}
