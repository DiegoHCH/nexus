import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/onboarding/presentation/providers/tour_providers.dart';
import 'package:nexus/features/updates/presentation/providers/updates_providers.dart';
/// Ayuda: la guía en frío, el tour otra vez, y la versión con su actualización.

/// Ayuda: por ahora, volver a ver el tour.
///
/// Sección propia y no una fila colgada de otra porque es donde va a vivir la
/// guía —el «qué necesita Nexus y qué hago con él» en frío—, y meterla ahora
/// dentro de Apariencia obligaría a mudarla después.
class HelpSection extends ConsumerWidget {
  const HelpSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;

    // Con su propio scroll: el cuerpo de una sección no lo trae, y esto es lo
    // más largo de todos los ajustes — la guía no cabe en una pantalla y no
    // debería tener que caber.
    return ListView(
      children: [
        Text(
          strings.helpTourTitle,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          strings.helpTourExplainer,
          style: NexusTypography.mono.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s5),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: () {
              ref.read(tourControllerProvider.notifier).replay();
              Navigator.of(context).maybePop();
            },
            child: Text(strings.helpTourAction),
          ),
        ),
        const SizedBox(height: NexusSpacing.s7),
        Divider(color: colors.rule, height: 1),
        const SizedBox(height: NexusSpacing.s6),

        // La versión y, si hay una nueva, el enlace. Aquí y no en un diálogo:
        // un aviso modal por una actualización interrumpe justo a quien está
        // trabajando, y esto no es urgente — es información.
        const _VersionRow(),
        const SizedBox(height: NexusSpacing.s7),

        // La guía en frío. Cuatro bloques y en este orden: qué hace falta, qué
        // sale de tu Mac, qué hace cada pieza y qué hacer cuando algo falla.
        //
        // El segundo va tan arriba a propósito: es lo único de aquí que **no se
        // puede deducir mirando la app**, y decidirlo mal tiene consecuencias
        // fuera de ella.
        _GuideBlock(
          title: strings.guideNeedsTitle,
          body: strings.guideNeedsBody,
        ),
        _GuideBlock(
          title: strings.guidePrivacyTitle,
          body: strings.guidePrivacyBody,
        ),
        _GuideBlock(
          title: strings.guidePiecesTitle,
          body: strings.guidePiecesBody,
        ),
        _GuideBlock(
          title: strings.guideTroubleTitle,
          body: strings.guideTroubleBody,
        ),
      ],
    );
  }
}

/// La versión que corre y, si la hay, la que está publicada.
///
/// Ya descarga e instala: el motor es Sparkle y la modal es la de la app. Lo que
/// **no** hace es reiniciarse por su cuenta —eso mataría un `claude -p` a media
/// escritura—, así que el último paso siempre lo confirma quien está delante.
class _VersionRow extends ConsumerWidget {
  const _VersionRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final aviso = ref.watch(updatesControllerProvider).notice;
    final actual =
        aviso?.current ?? ref.watch(currentVersionProvider).value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.versionLabel,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        Text(
          actual ?? '—',
          style: NexusTypography.data.copyWith(color: colors.ink),
        ),
        const SizedBox(height: NexusSpacing.s3),
        Align(
          alignment: Alignment.centerLeft,
          // Dos botones distintos y no uno que cambia de texto: «comprobar» es
          // algo que se pulsa sin saber si hay nada, y «actualizar» solo aparece
          // cuando ya se sabe que sí. Con un solo botón habría que decidir qué
          // dice mientras no se sabe, y ahí es donde se acaba mintiendo.
          // Un solo botón, y lo que cambia es lo que dice. Antes eran dos porque
          // uno abría la modal y el otro preguntaba; ahora los dos hacen lo
          // mismo —preguntar— y el aviso sale arriba a la derecha por su cuenta,
          // incluso estando en esta pantalla.
          child: OutlinedButton(
            onPressed: ref.read(updatesControllerProvider.notifier).comprobarAhora,
            child: Text(
              aviso != null && aviso.isNewer
                  ? strings.updateAvailable(aviso.latest ?? '')
                  : strings.updateCheckNow,
            ),
          ),
        ),
      ],
    );
  }
}

/// Un bloque de la guía: un título y su texto.
///
/// El cuerpo llega como un solo texto con saltos dobles y se parte aquí. Es a
/// propósito: un bloque por párrafo multiplicaría por cuatro los textos que hay
/// que traducir sin añadir nada, y lo que se traduce es prosa, no maquetación.
class _GuideBlock extends StatelessWidget {
  const _GuideBlock({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: NexusSpacing.s7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: NexusTypography.lead.copyWith(color: colors.ink),
          ),
          const SizedBox(height: NexusSpacing.s4),
          for (final parrafo in body.split('\n\n'))
            Padding(
              padding: const EdgeInsets.only(bottom: NexusSpacing.s3),
              child: Text(
                parrafo,
                style: NexusTypography.body.copyWith(color: colors.mute),
              ),
            ),
        ],
      ),
    );
  }
}
