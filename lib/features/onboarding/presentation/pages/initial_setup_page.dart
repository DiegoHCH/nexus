import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/features/assistant/presentation/orb/nexus_orb.dart';
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';
import 'package:nexus/features/onboarding/presentation/providers/onboarding_providers.dart';
import 'package:nexus/features/onboarding/presentation/state/onboarding_state.dart';
import 'package:url_launcher/url_launcher.dart';

/// D00b del mockup: solo la primera vez, sin llave de Gemini guardada. El
/// interruptor de permisos de las demás pantallas no aparece aquí porque
/// todavía no hay ninguna carpeta emparejada sobre la que decidir.
class InitialSetupPage extends ConsumerStatefulWidget {
  const InitialSetupPage({super.key});

  @override
  ConsumerState<InitialSetupPage> createState() => _InitialSetupPageState();
}

class _InitialSetupPageState extends ConsumerState<InitialSetupPage> {
  final _keyController = TextEditingController();

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _openApiKeyPage() async {
    final uri = Uri.parse('https://aistudio.google.com/apikey');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _finish() async {
    final ok = await ref.read(setupControllerProvider.notifier).finish();
    if (ok && mounted) {
      ref.read(appRouteControllerProvider.notifier).completeSetup();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final setup = ref.watch(setupControllerProvider);

    return Scaffold(
      body: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 220,
            child: const NexusOrb(state: NexusOrbState.sleep, showHorizon: false),
          ),
          Positioned(
            top: NexusSpacing.s6,
            left: 0,
            right: 0,
            child: Text(
              'N E X U S',
              textAlign: TextAlign.center,
              style: NexusTypography.brand.copyWith(color: colors.mute),
            ),
          ),
          Positioned.fill(
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: NexusSpacing.s9),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'ANTES DE EMPEZAR',
                          style: NexusTypography.label.copyWith(color: colors.cyan),
                        ),
                        const SizedBox(height: NexusSpacing.s3),
                        Text(
                          'Dos cosas antes de poder hablar contigo',
                          style: NexusTypography.title.copyWith(
                            color: colors.ink,
                            fontSize: 26,
                          ),
                        ),
                        const SizedBox(height: NexusSpacing.s3),
                        Text(
                          'Nexus necesita tu micrófono para escucharte y una llave de '
                          'Gemini para darte voz. Ninguna de las dos se comparte con nada más.',
                          style: NexusTypography.body.copyWith(color: colors.mute),
                        ),
                        const SizedBox(height: NexusSpacing.s7),
                        _MicrophoneField(
                          status: setup.micStatus,
                          onRequestPermission: () =>
                              ref.read(setupControllerProvider.notifier).requestMicrophonePermission(),
                        ),
                        const SizedBox(height: NexusSpacing.s6),
                        _GeminiKeyField(
                          controller: _keyController,
                          onChanged: (value) =>
                              ref.read(setupControllerProvider.notifier).updateKeyText(value),
                          onGetKey: _openApiKeyPage,
                        ),
                        if (setup.errorMessage != null) ...[
                          const SizedBox(height: NexusSpacing.s4),
                          Text(
                            'No se pudo guardar la llave: ${setup.errorMessage}',
                            style: NexusTypography.label.copyWith(color: colors.err, letterSpacing: 0.4),
                          ),
                        ],
                        const SizedBox(height: NexusSpacing.s6),
                        // El tema global del botón usa un solo color para todos
                        // los estados (`WidgetStatePropertyAll`), así que
                        // deshabilitado y habilitado se ven igual sin este
                        // opacity — el mockup marca el bloqueado con .38.
                        Opacity(
                          opacity: setup.canFinish ? 1 : 0.38,
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: setup.canFinish ? _finish : null,
                              child: setup.saving
                                  ? SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: colors.void_,
                                      ),
                                    )
                                  : const Text('EMPEZAR A USAR NEXUS'),
                            ),
                          ),
                        ),
                        const SizedBox(height: NexusSpacing.s5),
                        Text(
                          'Puedes cambiar esto después en Ajustes · Voz',
                          textAlign: TextAlign.center,
                          style: NexusTypography.mono.copyWith(color: colors.faint),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MicrophoneField extends StatelessWidget {
  const _MicrophoneField({required this.status, required this.onRequestPermission});

  final MicPermissionStatus status;
  final VoidCallback onRequestPermission;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (chipText, chipColor, dataText) = switch (status) {
      MicPermissionStatus.pending => ('PENDIENTE', colors.warn, 'Nexus no puede escucharte todavía'),
      MicPermissionStatus.granted => ('CONCEDIDO', colors.ok, 'Nexus puede escucharte'),
      MicPermissionStatus.denied => ('DENEGADO', colors.err, 'Actívalo en Ajustes del Sistema'),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('MICRÓFONO', style: NexusTypography.label.copyWith(color: colors.faint)),
        const SizedBox(height: NexusSpacing.s3),
        Row(
          children: [
            _StatusChip(text: chipText, color: chipColor),
            const SizedBox(width: NexusSpacing.s4),
            Text(dataText, style: NexusTypography.data.copyWith(color: colors.faint)),
          ],
        ),
        const SizedBox(height: NexusSpacing.s2),
        Opacity(
          opacity: status == MicPermissionStatus.granted ? 0.38 : 1,
          child: ElevatedButton(
            onPressed: status == MicPermissionStatus.granted ? null : onRequestPermission,
            child: const Text('PERMITIR ACCESO AL MICRÓFONO'),
          ),
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          'Abre el diálogo de permisos de macOS. Nexus solo graba después de oír la palabra clave.',
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
      ],
    );
  }
}

class _GeminiKeyField extends StatelessWidget {
  const _GeminiKeyField({
    required this.controller,
    required this.onChanged,
    required this.onGetKey,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onGetKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('LLAVE DE VOZ (GEMINI)', style: NexusTypography.label.copyWith(color: colors.faint)),
        const SizedBox(height: NexusSpacing.s3),
        TextField(
          controller: controller,
          onChanged: onChanged,
          obscureText: true,
          style: NexusTypography.mono.copyWith(color: colors.ink),
          decoration: const InputDecoration(hintText: 'Pega tu llave de API aquí'),
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          'Se guarda cifrada en este Mac. Solo viaja hacia Google para sostener la voz en tiempo real.',
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        OutlinedButton(
          onPressed: onGetKey,
          child: const Text('CONSEGUIR UNA LLAVE GRATIS ↗'),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(NexusRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.s3, vertical: NexusSpacing.s1),
        child: Text(text, style: NexusTypography.label.copyWith(color: color)),
      ),
    );
  }
}
