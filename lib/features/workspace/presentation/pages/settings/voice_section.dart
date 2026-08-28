import 'package:flutter/material.dart';
import 'package:nexus/features/workspace/presentation/pages/settings/settings_chooser.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/assistant/domain/entities/nexus_voice.dart';
import 'package:nexus/features/assistant/presentation/providers/audio_output_providers.dart';
import 'package:nexus/features/assistant/presentation/providers/voice_preference_providers.dart';
import 'package:nexus/features/assistant/presentation/widgets/microphone_tester.dart';
import 'package:nexus/features/onboarding/presentation/providers/onboarding_providers.dart';
import 'package:nexus/features/workspace/presentation/pages/settings/salidas_section.dart';

/// La sección de Voz de Ajustes.
///
/// Vive en su propio archivo desde que `settings_page.dart` pasó de las 1.400
/// líneas: cada sección es independiente —solo la usa el `switch` de la pantalla—
/// así que tenerlas juntas solo hacía que buscar una costara desplazarse por las
/// otras siete.

/// La voz con la que responde. Existe porque sin fijarla el servicio elegía
/// una distinta en cada sesión.
class VoiceSection extends ConsumerWidget {
  const VoiceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final selected = ref.watch(voicePreferenceProvider);
    final controller = ref.read(voicePreferenceProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.strings.nexusVoice,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          context.strings.voiceExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s5),
        SettingsChooser<NexusVoice>(
          value: NexusVoice.all.firstWhere(
            (voice) => voice.name == selected.name,
            orElse: () => NexusVoice.all.first,
          ),
          options: NexusVoice.all,
          label: (voice) => voice.name,
          detail: (voice) => voice.character,
          onSelected: controller.select,
        ),
        const SizedBox(height: NexusSpacing.s6),
        // La llave. Aquí y no solo en el primer arranque, porque hasta ahora la
        // pantalla de configuración prometía «puedes cambiar esto después en
        // Ajustes» y **no había dónde**: una llave mal escrita solo se arreglaba
        // tocando el llavero a mano. Y desde que la llave dejó de ser
        // obligatoria para entrar, este es el sitio donde se enciende la voz.
        const _GeminiKeyRow(),
        const SizedBox(height: NexusSpacing.s6),
        const _AudioOutputPicker(),
        const SizedBox(height: NexusSpacing.s6),
        // El micrófono se prueba aquí y no solo en el primer arranque: es donde
        // se viene cuando algo no se oye, y hasta ahora esta sección solo
        // dejaba cambiar la voz con la que Nexus habla, no comprobar la que
        // escucha.
        const Expanded(child: MicrophoneTester()),
      ],
    );
  }
}

/// La llave del servicio de voz: si hay una guardada, y cómo cambiarla.
///
/// **No se enseña la llave guardada**, ni recortada. Enseñarla no sirve para
/// nada —no se compara a ojo— y la deja en pantalla a la vista de cualquiera que
/// pase por detrás, en la única pantalla que alguien abre cuando está enseñando
/// la app. Lo único que hace falta saber es si hay una, y eso cabe en una
/// palabra.
class _GeminiKeyRow extends ConsumerStatefulWidget {
  const _GeminiKeyRow();

  @override
  ConsumerState<_GeminiKeyRow> createState() => _GeminiKeyRowState();
}

class _GeminiKeyRowState extends ConsumerState<_GeminiKeyRow> {
  final _controller = TextEditingController();
  bool _guardando = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final llave = _controller.text.trim();
    if (llave.isEmpty || _guardando) return;
    setState(() => _guardando = true);
    await ref.read(saveGeminiKeyProvider)(llave);
    if (!mounted) return;
    _controller.clear();
    setState(() => _guardando = false);
    // Para que la pantalla de salidas y la sesión de voz vean la nueva sin
    // reiniciar: las dos leen del llavero por su cuenta.
    ref.invalidate(geminiKeyStoreProvider);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;
    final hay = ref.watch(hayLlaveDeGeminiProvider).value ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.geminiKey,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          hay ? strings.geminiKeySaved : strings.geminiKeyMissing,
          style: NexusTypography.mono.copyWith(
            color: hay ? colors.ok : colors.warn,
          ),
        ),
        const SizedBox(height: NexusSpacing.s3),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                obscureText: true,
                onSubmitted: (_) => _guardar(),
                style: NexusTypography.mono.copyWith(color: colors.ink),
                decoration: InputDecoration(hintText: strings.geminiKeyHint),
              ),
            ),
            const SizedBox(width: NexusSpacing.s3),
            OutlinedButton(
              onPressed: _guardando ? null : _guardar,
              child: Text(strings.geminiKeySave),
            ),
          ],
        ),
      ],
    );
  }
}

/// Por dónde sale la voz de Nexus, cuando hay más de un aparato conectado.
class _AudioOutputPicker extends ConsumerWidget {
  const _AudioOutputPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final devices = ref.watch(audioOutputDevicesProvider).value ?? const [];
    // Con un solo aparato no hay nada que elegir; el desplegable sobra.
    if (devices.length < 2) return const SizedBox.shrink();

    final selected = ref.watch(audioOutputControllerProvider);
    final options = <int?>[null, ...devices.map((device) => device.id)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.audioOutput,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        SettingsChooser<int?>(
          value: options.contains(selected) ? selected : null,
          options: options,
          label: (id) {
            if (id == null) return strings.audioOutputSystem;
            return devices.firstWhere((device) => device.id == id).name;
          },
          // El que usa el sistema se marca, para que elegir «el del sistema» no
          // sea elegir a ciegas.
          detail: (id) => id == null
              ? (devices
                        .where((device) => device.isDefault)
                        .firstOrNull
                        ?.name ??
                    '')
              : '',
          onSelected: ref.read(audioOutputControllerProvider.notifier).select,
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          strings.audioOutputExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
      ],
    );
  }
}
