import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/assistant/presentation/providers/assistant_controller.dart';
import 'package:nexus/features/assistant/presentation/providers/conversations_providers.dart';
import 'package:nexus/features/history/presentation/providers/archive_providers.dart';
import 'package:nexus/features/onboarding/presentation/providers/onboarding_providers.dart';
import 'package:nexus/features/remote/presentation/providers/channel_providers.dart';
import 'package:nexus/features/workspace/domain/usecases/que_sale_de_la_maquina.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

/// Si hay llave de Gemini guardada. Solo eso: **el valor no sale del llavero**,
/// que es la misma regla que sigue el token de Notion.
final hayLlaveDeGeminiProvider = FutureProvider<bool>((ref) async {
  final llave = await ref.watch(geminiKeyStoreProvider).read();
  return (llave ?? '').isNotEmpty;
});

/// Qué sale de esta máquina, para la carpeta enfocada y ahora mismo.
///
/// **Las cuatro puertas juntas, y ese es todo el punto.** Cada decisión estaba
/// bien tomada por separado —la modalidad de la carpeta, la frase de escritura,
/// el destino de archivo— y ninguna se toca aquí. Lo que faltaba es poder
/// comprobarlas a la vez: cuatro promesas sueltas no son una promesa.
class SalidasSection extends ConsumerWidget {
  const SalidasSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;

    final carpeta = ref.watch(workspaceControllerProvider).active;
    final canal = ref.watch(channelControllerProvider);
    final archivo = ref.watch(archiveControllerProvider);
    final llave = ref.watch(hayLlaveDeGeminiProvider).value ?? false;

    // La voz de la conversación que se está mirando. Sin ninguna abierta no hay
    // voz que valga, y eso es `false` y no «no se sabe».
    final enfocada = ref.watch(conversationsProvider).focusedId;
    final vozAbierta =
        enfocada != null &&
        ref.watch(assistantControllerProvider(enfocada)).voiceActive;

    final puertas = QueSaleDeLaMaquina.para(
      carpeta: carpeta,
      hayLlaveDeGemini: llave,
      vozAbierta: vozAbierta,
      destinoDeArchivo: archivo.destination,
      destinoListo: archivo.isReady,
      canalEncendido: canal is ChannelOn,
      // Que haya alguien dentro y no solo que esté escuchando: un canal
      // encendido sin teléfono conectado no está sacando nada.
      hayAlguienConectado:
          ref
              .watch(channelControllerProvider.notifier)
              .servidor
              ?.clientes
              .isNotEmpty ??
          false,
      direccionDelCanal: canal is ChannelOn
          ? '${canal.address}:${canal.port}'
          : null,
    );

    return ListView(
      children: [
        Text(
          carpeta == null
              ? strings.exitsNoFolder
              : strings.exitsForFolder(carpeta.path.split('/').last),
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          strings.exitsExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s6),
        for (final puerta in puertas) ...[
          _Puerta(puerta: puerta),
          const SizedBox(height: NexusSpacing.s5),
        ],
      ],
    );
  }
}

class _Puerta extends StatelessWidget {
  const _Puerta({required this.puerta});

  final PuertaDeSalida puerta;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;

    // Cerrada en gris y no en verde: verde diría «esto está bien», y aquí no hay
    // bien ni mal — hay lo que pasa. El que sale ahora es el que se marca.
    final color = switch (puerta.como) {
      ComoEsta.cerrada => colors.faint,
      ComoEsta.disponible => colors.mute,
      ComoEsta.abierta => colors.warn,
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // El punto delante: la fila se lee en vertical y el estado tiene que
        // verse sin leer el texto.
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
        ),
        const SizedBox(width: NexusSpacing.s3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    _nombre(strings),
                    style: NexusTypography.body.copyWith(color: colors.ink),
                  ),
                  const SizedBox(width: NexusSpacing.s3),
                  Text(
                    _estado(strings).toUpperCase(),
                    style: NexusTypography.label.copyWith(color: color),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                _queViaja(strings),
                style: NexusTypography.mono.copyWith(color: colors.faint),
              ),
              if (puerta.dato case final dato? when dato.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  dato,
                  style: NexusTypography.mono.copyWith(color: colors.mute),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _nombre(NexusStrings strings) => switch (puerta.cual) {
    Salida.anthropic => strings.exitAnthropic,
    Salida.gemini => strings.exitGemini,
    Salida.notion => strings.exitNotion,
    Salida.canal => strings.exitChannel,
  };

  /// **Qué viaja, no solo a dónde.** «Gemini: abierta» no dice nada que se pueda
  /// decidir; «tu micrófono y lo que Claude lea» sí.
  String _queViaja(NexusStrings strings) => switch (puerta.cual) {
    Salida.anthropic => strings.exitAnthropicWhat,
    Salida.gemini => strings.exitGeminiWhat,
    Salida.notion => strings.exitNotionWhat,
    Salida.canal => strings.exitChannelWhat,
  };

  String _estado(NexusStrings strings) => switch (puerta.como) {
    ComoEsta.cerrada => strings.exitClosed,
    ComoEsta.disponible => strings.exitAvailable,
    ComoEsta.abierta => strings.exitOpen,
  };
}
