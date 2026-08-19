import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/onboarding/domain/entities/readiness.dart';
import 'package:nexus/features/onboarding/presentation/providers/onboarding_providers.dart';
import 'package:url_launcher/url_launcher.dart';

/// Lo que falta **del sistema** para que Nexus pueda trabajar, dicho antes de
/// entrar.
///
/// No es una pantalla de error: es la respuesta a una pregunta que la app no se
/// hacía. Hasta ahora se comprobaba solo la llave de Gemini, así que un Mac sin
/// Claude Code arrancaba contento y moría en el primer encargo con una
/// `ProcessException` — un fallo sin frase, que es el peor tipo.
///
/// Enseña **solo lo que se sabe que falta**. Un `unknown` no llega hasta aquí:
/// esta pantalla no aparece cuando no se pudo preguntar, porque acusar de algo
/// que no se ha comprobado es peor que dejar pasar.
class ReadinessPage extends ConsumerWidget {
  const ReadinessPage({super.key, required this.readiness});

  final Readiness readiness;

  static final _installDocs = Uri.parse(
    'https://docs.claude.com/en/docs/claude-code/setup',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(NexusSpacing.s7),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.brand,
                  style: NexusTypography.brand.copyWith(color: colors.cyan),
                ),
                const SizedBox(height: NexusSpacing.s6),
                Text(
                  strings.readinessTitle,
                  style: NexusTypography.title.copyWith(color: colors.ink),
                ),
                const SizedBox(height: NexusSpacing.s4),
                Text(
                  strings.readinessExplainer,
                  style: NexusTypography.body.copyWith(color: colors.mute),
                ),
                const SizedBox(height: NexusSpacing.s7),

                if (readiness.cli == CheckResult.failed)
                  _Missing(
                    title: strings.readinessCliMissing,
                    fix: strings.readinessCliMissingFix,
                    linkLabel: strings.readinessHowToInstall,
                    onLink: () => launchUrl(
                      _installDocs,
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                // Solo una de las dos: sin binario no se le pudo preguntar por
                // la sesión, y enseñar las dos como si fueran dos problemas
                // manda a arreglar algo que quizá ya está bien.
                if (readiness.cli != CheckResult.failed &&
                    readiness.session == CheckResult.failed)
                  _Missing(
                    title: strings.readinessSessionMissing,
                    fix: strings.readinessSessionMissingFix,
                  ),

                const SizedBox(height: NexusSpacing.s7),
                Row(
                  children: [
                    _Action(
                      label: strings.readinessRecheck,
                      color: colors.cyan,
                      onTap: () => ref
                          .read(appRouteControllerProvider.notifier)
                          .recheck(),
                    ),
                    const SizedBox(width: NexusSpacing.s5),
                    _Action(
                      label: strings.readinessContinueAnyway,
                      color: colors.faint,
                      onTap: () => ref
                          .read(appRouteControllerProvider.notifier)
                          .continueAnyway(),
                    ),
                  ],
                ),
                const SizedBox(height: NexusSpacing.s4),
                Text(
                  strings.readinessContinueHint,
                  style: NexusTypography.label.copyWith(color: colors.faint),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Una cosa que falta: qué es, y qué hacer. Las dos juntas siempre — un aviso
/// que no dice cómo salir de él es solo una mala noticia.
class _Missing extends StatelessWidget {
  const _Missing({
    required this.title,
    required this.fix,
    this.linkLabel,
    this.onLink,
  });

  final String title;
  final String fix;
  final String? linkLabel;
  final VoidCallback? onLink;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = linkLabel;

    return Container(
      padding: const EdgeInsets.all(NexusSpacing.s5),
      decoration: BoxDecoration(
        color: colors.rise,
        border: Border.all(color: colors.rule),
        borderRadius: BorderRadius.circular(NexusRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Icon(Icons.error_outline, size: 16, color: colors.warn),
              ),
              const SizedBox(width: NexusSpacing.s3),
              Expanded(
                child: Text(
                  title,
                  style: NexusTypography.lead.copyWith(color: colors.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: NexusSpacing.s3),
          Text(
            fix,
            style: NexusTypography.body.copyWith(color: colors.mute),
          ),
          if (label != null) ...[
            const SizedBox(height: NexusSpacing.s4),
            _Action(label: label, color: colors.cyan, onTap: onLink),
          ],
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.label, required this.color, this.onTap});

  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(NexusRadius.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: NexusSpacing.s5,
          vertical: NexusSpacing.s3,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(NexusRadius.sm),
        ),
        child: Text(
          label,
          style: NexusTypography.label.copyWith(color: color),
        ),
      ),
    );
  }
}
