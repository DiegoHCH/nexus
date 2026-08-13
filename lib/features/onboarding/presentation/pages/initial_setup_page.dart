import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/assistant/presentation/orb/nexus_orb.dart';
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';
import 'package:nexus/features/onboarding/presentation/providers/onboarding_providers.dart';
import 'package:nexus/features/onboarding/presentation/state/onboarding_state.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';
import 'package:url_launcher/url_launcher.dart';

/// D00b del mockup: solo la primera vez. El interruptor de permisos de las
/// demás pantallas no aparece aquí porque todavía no hay ninguna carpeta
/// emparejada sobre la que decidir "solo leer" o "puede editar".
///
/// El orbe vive en una franja fija arriba (altura [_orbZoneHeight]); el
/// contenido siempre arranca por debajo de esa franja — nunca centrado en
/// toda la pantalla — para que no se monten cuando la ventana es baja.
class InitialSetupPage extends ConsumerStatefulWidget {
  const InitialSetupPage({super.key});

  // El orbe se centra al 46% de la altura de su caja (NexusOrbPainter), así
  // que con top:0 su mitad superior queda casi a la misma altura que el
  // wordmark de arriba. Bajarla despega la esfera del título; el padding del
  // contenido baja lo mismo para conservar el hueco que ya había debajo.
  static const _orbZoneTop = 32.0;
  static const _orbZoneHeight = 170.0;
  static const _contentTopPadding = 210.0 + _orbZoneTop;

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
    // Las tres cosas: micrófono, llave y carpeta. Sin la tercera la app
    // arrancaría sin sitio donde trabajar, y el primer encargo respondería
    // sobre la raíz del disco.
    final canFinish =
        setup.canFinish &&
        ref.watch(workspaceControllerProvider).folders.isNotEmpty;

    return Scaffold(
      body: Stack(
        children: [
          Positioned(
            top: InitialSetupPage._orbZoneTop,
            left: 0,
            right: 0,
            height: InitialSetupPage._orbZoneHeight,
            child: const NexusOrb(
              state: NexusOrbState.sleep,
              showHorizon: false,
            ),
          ),
          Positioned(
            top: NexusSpacing.s5,
            left: 0,
            right: 0,
            child: Text(
              context.strings.brand,
              textAlign: TextAlign.center,
              style: NexusTypography.brand.copyWith(color: colors.mute),
            ),
          ),
          Positioned.fill(
            child: SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(
                    top: InitialSetupPage._contentTopPadding,
                    bottom: NexusSpacing.s9,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          context.strings.beforeWeStart,
                          style: NexusTypography.label.copyWith(
                            color: colors.cyan,
                          ),
                        ),
                        const SizedBox(height: NexusSpacing.s3),
                        Text(
                          context.strings.setupTitle,
                          style: NexusTypography.title.copyWith(
                            color: colors.ink,
                            fontSize: 26,
                          ),
                        ),
                        const SizedBox(height: NexusSpacing.s3),
                        Text(
                          context.strings.setupExplainer,
                          style: NexusTypography.body.copyWith(
                            color: colors.mute,
                          ),
                        ),
                        const SizedBox(height: NexusSpacing.s7),
                        _MicrophoneField(
                          status: setup.micStatus,
                          amplitude: setup.amplitude,
                          onRequest: () => ref
                              .read(setupControllerProvider.notifier)
                              .requestMicrophoneAccess(),
                        ),
                        const SizedBox(height: NexusSpacing.s6),
                        const _WorkFolderField(),
                        const SizedBox(height: NexusSpacing.s6),
                        _GeminiKeyField(
                          controller: _keyController,
                          onChanged: (value) => ref
                              .read(setupControllerProvider.notifier)
                              .updateKeyText(value),
                          onGetKey: _openApiKeyPage,
                        ),
                        if (setup.errorMessage != null) ...[
                          const SizedBox(height: NexusSpacing.s4),
                          Text(
                            context.strings.keySaveFailed(
                              setup.errorMessage ?? '',
                            ),
                            style: NexusTypography.label.copyWith(
                              color: colors.err,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                        const SizedBox(height: NexusSpacing.s6),
                        // El tema global del botón usa un solo color para todos
                        // los estados (`WidgetStatePropertyAll`), así que
                        // deshabilitado y habilitado se ven igual sin este
                        // opacity — el mockup marca el bloqueado con .38.
                        Opacity(
                          opacity: canFinish ? 1 : 0.38,
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: canFinish ? _finish : null,
                              child: setup.saving
                                  ? SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: colors.void_,
                                      ),
                                    )
                                  : Text(context.strings.startUsingNexus),
                            ),
                          ),
                        ),
                        const SizedBox(height: NexusSpacing.s5),
                        Text(
                          context.strings.changeLaterHint,
                          textAlign: TextAlign.center,
                          style: NexusTypography.mono.copyWith(
                            color: colors.faint,
                          ),
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
  const _MicrophoneField({
    required this.status,
    required this.amplitude,
    required this.onRequest,
  });

  final MicrophoneStatus status;
  final double amplitude;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (chipText, chipColor, dataText, hint) = switch (status) {
      MicrophoneStatus.idle => (
        context.strings.request,
        colors.cyan,
        context.strings.micPending,
        context.strings.micPendingExplainer,
      ),
      MicrophoneStatus.checking => (
        context.strings.micPending,
        colors.warn,
        context.strings.micAsking,
        context.strings.micAskingExplainer,
      ),
      MicrophoneStatus.granted => (
        context.strings.micGranted,
        colors.ok,
        context.strings.micGranted,
        context.strings.micGrantedExplainer,
      ),
      MicrophoneStatus.denied => (
        context.strings.micDenied,
        colors.err,
        context.strings.micDeniedShort,
        context.strings.micDeniedExplainer,
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.strings.microphone,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s3),
        Row(
          children: [
            _StatusChip(
              text: chipText,
              color: chipColor,
              onTap: status == MicrophoneStatus.idle ? onRequest : null,
            ),
            const SizedBox(width: NexusSpacing.s4),
            Text(
              dataText,
              style: NexusTypography.data.copyWith(color: colors.faint),
            ),
          ],
        ),
        const SizedBox(height: NexusSpacing.s3),
        if (status == MicrophoneStatus.granted)
          Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.s3),
            decoration: BoxDecoration(
              color: colors.rise,
              borderRadius: BorderRadius.circular(NexusRadius.sm),
              border: Border.all(color: colors.rule2),
            ),
            child: Row(
              children: [
                Expanded(child: _MicWaveform(amplitude: amplitude)),
                const SizedBox(width: NexusSpacing.s4),
                Text(
                  context.strings.iHearYou,
                  style: NexusTypography.label.copyWith(color: colors.cyan),
                ),
              ],
            ),
          ),
        const SizedBox(height: NexusSpacing.s2),
        Text(hint, style: NexusTypography.mono.copyWith(color: colors.faint)),
      ],
    );
  }
}

/// Traza en vivo del volumen del micrófono: una cola de las últimas muestras
/// de [AudioFrame.amplitude] que entra por la derecha y se desplaza hacia la
/// izquierda, como un medidor de nivel. No es un osciloscopio real — no hay
/// forma de onda cruda aquí, solo el RMS por bloque que ya calcula
/// [VoiceInputImpl] — pero alcanza para que se note si la voz está llegando.
class _MicWaveform extends StatefulWidget {
  const _MicWaveform({required this.amplitude});

  final double amplitude;

  @override
  State<_MicWaveform> createState() => _MicWaveformState();
}

class _MicWaveformState extends State<_MicWaveform> {
  static const _maxSamples = 40;
  final _samples = <double>[];

  @override
  void didUpdateWidget(covariant _MicWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.amplitude == oldWidget.amplitude) return;
    setState(() {
      _samples.add(widget.amplitude);
      if (_samples.length > _maxSamples) _samples.removeAt(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: CustomPaint(
        size: const Size(double.infinity, 28),
        // Una copia y no `_samples` a pelo: la cola se muta en el sitio, así
        // que el pintor viejo y el nuevo compartirían la misma lista y
        // shouldRepaint no vería jamás una diferencia.
        painter: _WaveformPainter(
          samples: List.of(_samples),
          color: context.colors.cyan,
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({required this.samples, required this.color});

  final List<double> samples;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    if (samples.isEmpty) {
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint..color = color.withValues(alpha: 0.3),
      );
      return;
    }

    final gap = size.width / _MicWaveformState._maxSamples;
    for (var i = 0; i < samples.length; i++) {
      final x = size.width - (samples.length - i) * gap;
      final barHeight = (samples[i].clamp(0.0, 1.0) * size.height).clamp(
        2.0,
        size.height,
      );
      final fade = 0.35 + 0.65 * (i / samples.length);
      canvas.drawLine(
        Offset(x, size.height / 2 - barHeight / 2),
        Offset(x, size.height / 2 + barHeight / 2),
        paint..color = color.withValues(alpha: fade),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      !listEquals(oldDelegate.samples, samples) || oldDelegate.color != color;
}

/// La carpeta donde Nexus va a trabajar, pedida ya en el primer arranque.
///
/// Se pide aquí y no después porque sin ella la app no puede hacer nada: el
/// puente a Claude necesita un directorio, y sin uno heredaría el de la app
/// —la raíz del disco— y respondería sobre todo el Mac. Una carpeta concreta
/// no es una preferencia, es la condición para que exista el trabajo.
class _WorkFolderField extends ConsumerWidget {
  const _WorkFolderField();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final workspace = ref.watch(workspaceControllerProvider);
    final home = ref.watch(homeDirectoryProvider);
    final folder = workspace.folders.firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.strings.workFolder,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s3),
        Row(
          children: [
            _StatusChip(
              text: folder == null
                  ? context.strings.choose
                  : context.strings.chosen,
              color: folder == null ? colors.cyan : colors.ok,
              onTap: ref.read(workspaceControllerProvider.notifier).pairFolder,
            ),
            const SizedBox(width: NexusSpacing.s4),
            Expanded(
              child: Text(
                folder?.displayPath(home) ?? context.strings.workFolderTitle,
                style: NexusTypography.data.copyWith(color: colors.faint),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          context.strings.workFolderExplainer,
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
        Text(
          context.strings.geminiKey,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s3),
        TextField(
          controller: controller,
          onChanged: onChanged,
          obscureText: true,
          style: NexusTypography.mono.copyWith(color: colors.ink),
          decoration: InputDecoration(hintText: context.strings.geminiKeyHint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          context.strings.geminiKeyExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        OutlinedButton(
          onPressed: onGetKey,
          child: Text(context.strings.getFreeKey),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.text, required this.color, this.onTap});

  final String text;
  final Color color;

  /// Si no es nulo, el chip se pinta igual pero se puede tocar — es como
  /// "Solicitar" pide el permiso: un botón con la misma pinta que un chip de
  /// estado, no uno nuevo aparte.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chip = DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(NexusRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NexusSpacing.s3,
          vertical: NexusSpacing.s1,
        ),
        child: Text(text, style: NexusTypography.label.copyWith(color: color)),
      ),
    );

    if (onTap == null) return chip;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(NexusRadius.sm),
      child: chip,
    );
  }
}
