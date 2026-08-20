import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/remote/presentation/providers/channel_providers.dart';
import 'package:nexus/features/remote/presentation/providers/channel_token_providers.dart';

/// El canal del teléfono: encenderlo, ver dónde escucha, y rotar el token.
///
/// Esta sección estaba **listada y apagada** desde el principio, como recordatorio
/// de una fase que no existía. Ya existe la mitad: el canal se enciende y acepta
/// conexiones. Lo que no existe es la app del teléfono, y eso se dice aquí en vez
/// de dejarlo adivinar — una sección que promete un móvil que no hay es peor que
/// una apagada.
class MobileSection extends ConsumerWidget {
  const MobileSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final estado = ref.watch(channelControllerProvider);
    final control = ref.read(channelControllerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.channelTitle,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          strings.channelExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s5),
        Row(
          children: [
            Expanded(
              child: Text(
                strings.channelSwitch,
                style: NexusTypography.data.copyWith(color: colors.ink),
              ),
            ),
            Switch(
              key: const ValueKey('interruptor-del-canal'),
              value: estado is ChannelOn || estado is ChannelStarting,
              onChanged: (encender) =>
                  encender ? control.encender() : control.apagar(),
            ),
          ],
        ),
        const SizedBox(height: NexusSpacing.s5),
        switch (estado) {
          ChannelOff() => const SizedBox.shrink(),
          ChannelStarting() => _Nota(strings.channelStarting),
          final ChannelOn on => _Encendido(url: on.url),
          final ChannelUnavailable no => _Problema(no.reason),
        },
        const SizedBox(height: NexusSpacing.s7),
        // Dicho sin rodeos y no en letra pequeña al final: quien enciende esto hoy
        // no tiene con qué conectarse.
        Container(
          decoration: BoxDecoration(
            color: colors.deep,
            border: Border.all(color: colors.rule),
            borderRadius: BorderRadius.circular(NexusRadius.sm),
          ),
          padding: const EdgeInsets.all(NexusSpacing.s5),
          child: Text(
            strings.channelNoPhoneYet,
            style: NexusTypography.mono.copyWith(color: colors.faint),
          ),
        ),
      ],
    );
  }
}

/// Dónde escucha, y el token para llegar.
class _Encendido extends ConsumerWidget {
  const _Encendido({required this.url});

  final String url;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final token = ref.watch(channelTokenControllerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.channelListeningAt,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        SelectableText(
          url,
          key: const ValueKey('direccion-del-canal'),
          style: NexusTypography.mono.copyWith(color: colors.accent),
        ),
        const SizedBox(height: NexusSpacing.s5),
        Text(
          strings.channelToken,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        // **La huella y no el token.** Se enseña entero solo al copiarlo, porque
        // esta pantalla se comparte en capturas y en pantallas compartidas más de
        // lo que parece — y un secreto de 43 caracteres a la vista es un secreto
        // que ya viajó.
        Row(
          children: [
            Text(
              token.value?.fingerprint ?? '—',
              style: NexusTypography.mono.copyWith(color: colors.mute),
            ),
            const SizedBox(width: NexusSpacing.s4),
            if (token.value case final actual?)
              TextButton(
                key: const ValueKey('copiar-el-token'),
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: actual.value)),
                child: Text(strings.channelCopyToken),
              ),
            TextButton(
              key: const ValueKey('rotar-el-token'),
              onPressed: ref.read(channelControllerProvider.notifier).rotarToken,
              child: Text(strings.channelRotateToken),
            ),
          ],
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          strings.channelRotateWarning,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
      ],
    );
  }
}

class _Problema extends StatelessWidget {
  const _Problema(this.reason);

  final ChannelProblem reason;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;
    return Container(
      key: const ValueKey('problema-del-canal'),
      decoration: BoxDecoration(
        color: colors.deep,
        border: Border.all(color: colors.warn),
        borderRadius: BorderRadius.circular(NexusRadius.sm),
      ),
      padding: const EdgeInsets.all(NexusSpacing.s5),
      child: Text(
        // Cada problema con **lo que hay que hacer**, no solo con lo que pasó.
        switch (reason) {
          ChannelProblem.noTailscale => strings.channelNeedsTailscale,
          ChannelProblem.portBusy => strings.channelPortBusy,
          ChannelProblem.unknown => strings.channelUnknownProblem,
        },
        style: NexusTypography.body.copyWith(color: colors.mute),
      ),
    );
  }
}

class _Nota extends StatelessWidget {
  const _Nota(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Text(
    texto,
    style: NexusTypography.mono.copyWith(color: context.colors.faint),
  );
}
