import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/assistant/domain/entities/audio_frame.dart';
import 'package:nexus/features/assistant/presentation/providers/voice_input_providers.dart';

/// El permiso del micrófono y la prueba de sonido en vivo.
///
/// Es el mismo trazo que la pantalla de primer arranque, y por eso vive aquí y
/// no allí dentro: hace falta en dos sitios y son la misma pregunta —«¿me
/// oyes?»—. Sin él, en Ajustes solo se podía cambiar la voz con la que Nexus
/// habla, no comprobar la que él escucha.
///
/// Abre el micrófono de verdad mientras se ve, y lo cierra al salir: es una
/// prueba, no un estado.
class MicrophoneTester extends ConsumerStatefulWidget {
  const MicrophoneTester({super.key});

  @override
  ConsumerState<MicrophoneTester> createState() => _MicrophoneTesterState();
}

class _MicrophoneTesterState extends ConsumerState<MicrophoneTester> {
  StreamSubscription<AudioFrame>? _subscription;
  bool? _granted;
  double _amplitude = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    final voiceInput = ref.read(voiceInputProvider);
    final granted = await voiceInput.hasPermission();
    if (!mounted) return;
    setState(() => _granted = granted);
    if (!granted) return;

    _subscription = voiceInput.listen().listen(
      (frame) {
        if (mounted) setState(() => _amplitude = frame.amplitude);
      },
      onError: (Object _) {
        if (mounted) setState(() => _granted = false);
      },
    );
  }

  @override
  void dispose() {
    // Se cierra al salir de la sección. Dejarlo abierto sería exactamente lo
    // que el proyecto lleva evitando desde 2.5: el micrófono encendido sin que
    // nadie esté hablando.
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;
    final granted = _granted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              strings.microphone,
              style: NexusTypography.label.copyWith(color: colors.faint),
            ),
            const SizedBox(width: NexusSpacing.s3),
            Text(
              switch (granted) {
                null => '…',
                true => strings.micGranted,
                false => strings.micDenied,
              },
              style: NexusTypography.label.copyWith(
                color: granted == true ? colors.ok : colors.warn,
              ),
            ),
          ],
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          granted == false
              ? strings.micDeniedExplainer
              : strings.micGrantedExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s4),
        if (granted == true)
          SizedBox(
            height: 48,
            child: CustomPaint(
              painter: _TracePainter(amplitude: _amplitude, color: colors.accent),
              child: const SizedBox.expand(),
            ),
          ),
      ],
    );
  }
}

/// El trazo: una línea que responde al volumen. No dibuja la onda real —para
/// saber si te oye basta con que se mueva cuando hablas— y con eso se distingue
/// «no llega audio» de «llega silencio», que desde fuera se ven igual.
class _TracePainter extends CustomPainter {
  const _TracePainter({required this.amplitude, required this.color});

  final double amplitude;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final middle = size.height / 2;
    final pen = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    const bars = 48;
    final step = size.width / bars;
    for (var i = 0; i < bars; i++) {
      // Una envolvente para que el centro se mueva más que los extremos: sin
      // ella la línea sube y baja como un bloque y parece un medidor, no una
      // voz.
      final distance = (i / bars - 0.5).abs() * 2;
      final envelope = 1 - distance * distance;
      final height = (amplitude * envelope * size.height).clamp(
        1.0,
        size.height,
      );
      final x = step * i + step / 2;
      canvas.drawLine(
        Offset(x, middle - height / 2),
        Offset(x, middle + height / 2),
        pen,
      );
    }
  }

  @override
  bool shouldRepaint(_TracePainter oldDelegate) =>
      oldDelegate.amplitude != amplitude || oldDelegate.color != color;
}
