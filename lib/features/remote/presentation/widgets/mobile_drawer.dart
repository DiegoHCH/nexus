import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/nexus_colors.dart';
import 'package:nexus/core/design_system/nexus_spacing.dart';
import 'package:nexus/core/design_system/nexus_typography.dart';
import 'package:nexus/features/remote/presentation/providers/pairing_providers.dart';

/// El menú: lo que **no** es la conversación.
///
/// **Sin orbe, y es el punto.** El orbe es la presencia del asistente: una lista de
/// archivos o un selector de carpetas no es el asistente haciendo algo, y ponerle uno
/// lo convierte en decoración — deja de significar «está pasando algo» y pasa a ser
/// un adorno que gira.
///
/// Por eso estas tres pantallas viven detrás de un menú y no en la principal: la
/// principal es la conversación, y esto son utilidades. El panel deja ver la
/// conversación detrás porque **el menú es un desvío, no un sitio donde uno se queda**.
///
/// Tres de sus cuatro entradas son lecturas. La única que cambia algo —abrir una
/// conversación— lo hace sobre una carpeta que el Mac ya tenía: elegir entre las
/// emparejadas no es emparejar.
class MobileDrawer extends ConsumerWidget {
  const MobileDrawer({
    super.key,
    required this.alAbrirNueva,
    required this.alAbrirArchivo,
    required this.alAbrirArtifacts,
  });

  final VoidCallback alAbrirNueva;
  final VoidCallback alAbrirArchivo;
  final VoidCallback alAbrirArtifacts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final pareja = ref.watch(pairingControllerProvider).value;

    return Drawer(
      backgroundColor: colors.deep,
      // 78 % del ancho, como el mockup: el resto deja ver la conversación, que es lo
      // que dice que esto se cierra enseguida. Un menú a pantalla completa se siente
      // como haber navegado a otra parte.
      width: MediaQuery.of(context).size.width * 0.78,
      shape: Border(right: BorderSide(color: colors.rule)),
      child: SafeArea(
        // **Desplazable, y no por gusto.** Con cuatro entradas y el pie, esto se
        // desborda en una pantalla corta —lo destapó una prueba a 800×600, que es
        // también un teléfono pequeño de lado o con la letra grande del sistema—. Un
        // menú que se corta esconde precisamente la entrada de abajo.
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  NexusSpacing.s4,
                  NexusSpacing.s5,
                  NexusSpacing.s4,
                  NexusSpacing.s3,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ESTE MAC',
                      style: NexusTypography.label.copyWith(
                        color: colors.faint,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      // La dirección y **no la huella del token**: lo que identifica al
                      // Mac aquí es dónde está, y el token no se enseña ni en trozos.
                      pareja?.comoSeVe ?? 'sin emparejar',
                      style: NexusTypography.data.copyWith(color: colors.mute),
                    ),
                  ],
                ),
              ),
              _Entrada(
                key: const ValueKey('menu-nueva'),
                titulo: 'Conversación nueva',
                pie: 'Sobre una carpeta ya emparejada',
                alTocar: alAbrirNueva,
              ),
              _Entrada(
                key: const ValueKey('menu-archivo'),
                titulo: 'El archivo',
                pie: 'Retomar una de antes',
                alTocar: alAbrirArchivo,
              ),
              _Entrada(
                key: const ValueKey('menu-artifacts'),
                titulo: 'Los artifacts',
                pie: 'Lo que produjo Claude',
                alTocar: alAbrirArtifacts,
              ),
              _Entrada(
                key: const ValueKey('menu-olvidar'),
                titulo: 'Olvidar este Mac',
                pie: 'Hay que volver a emparejar',
                // La única destructiva, y va **al final y sin acento**: el sitio donde
                // no se toca por error al buscar otra cosa.
                peligrosa: true,
                alTocar: () =>
                    ref.read(pairingControllerProvider.notifier).olvidar(),
              ),
              // Sin `Spacer` aquí si algún día se añade algo debajo: es un
              // `Expanded`, y un `Expanded` dentro de algo que hace scroll es una
              // contradicción. Es el mismo fallo que ya rompió Ajustes y la pantalla de
              // emparejar — tercera vez, y por eso queda escrito aunque ahora no haya
              // nada al final.
              const SizedBox(height: NexusSpacing.s4),
            ],
          ),
        ),
      ),
    );
  }
}

class _Entrada extends StatelessWidget {
  const _Entrada({
    super.key,
    required this.titulo,
    required this.pie,
    required this.alTocar,
    this.peligrosa = false,
  });

  final String titulo;
  final String pie;
  final VoidCallback alTocar;
  final bool peligrosa;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return InkWell(
      onTap: alTocar,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: NexusSpacing.s4,
          vertical: NexusSpacing.s3,
        ),
        decoration: BoxDecoration(
          // Hairline arriba, como los bloques de la conversación: es el mismo sistema,
          // y una lista con separadores propios se leería como otra app.
          border: Border(top: BorderSide(color: colors.rule)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: NexusTypography.lead.copyWith(
                color: peligrosa ? colors.mute : colors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              pie,
              style: NexusTypography.mono.copyWith(color: colors.faint),
            ),
          ],
        ),
      ),
    );
  }
}
