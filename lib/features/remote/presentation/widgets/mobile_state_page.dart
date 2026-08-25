import 'package:flutter/material.dart';
import 'package:nexus/core/design_system/nexus_colors.dart';
import 'package:nexus/core/design_system/nexus_spacing.dart';
import 'package:nexus/core/design_system/nexus_typography.dart';
import 'package:nexus/features/assistant/presentation/orb/nexus_orb.dart';
import 'package:nexus/features/assistant/presentation/state/orb_state.dart';
import 'package:nexus/features/remote/presentation/widgets/mobile_chrome.dart';

/// El molde de las pantallas de estado del teléfono.
///
/// Los mockups dedican una sección entera a esto y empiezan diciendo lo que hacía
/// falta oír: **«no son opcionales y no se resuelven con un spinner centrado. Cada uno
/// dice qué pasó y qué se puede hacer; ninguno se disculpa.»**
///
/// La primera versión de estas pantallas los resolvía con un texto gris en el centro
/// —o con nada—, que es exactamente lo que esa frase descarta. Así que el molde
/// **obliga** a las tres partes: qué pasó, por qué, y qué se puede hacer. Un estado
/// sin acciones tiene que decidirlo quien lo escribe, no aparecer por descuido.
///
/// El orbe va con su estado y no como ilustración: es el único elemento vivo del
/// sistema, y en un estado de error tiene que estar dormido — un orbe girando mientras
/// la pantalla dice «se perdió el enlace» promete trabajo que no está pasando.
///
/// Y va **en el flujo**, con el mismo reparto que `ConnectingPage`: orbe centrado entre
/// dos espaciadores y el texto abajo. Estaba como capa de fondo fijada al 46 % del alto,
/// y el resultado era que el orbe quedaba pegado arriba y el texto centrado, con el
/// tercio inferior de la pantalla vacío — se veía **de otra app** al lado de las demás.
/// El reparto no es un detalle estético aquí: estas pantallas y las de conexión se ven
/// una detrás de otra, y un salto de composición entre ellas se lee como un fallo.
class MobileStatePage extends StatelessWidget {
  const MobileStatePage({
    super.key,
    required this.titulo,
    required this.cuerpo,
    this.orbe = NexusOrbState.sleep,
    this.detalle,
    this.pieDeAyuda,
    this.acciones = const [],
    this.abajo,
  });

  /// Qué pasó, en una frase corta y sin disculparse.
  final String titulo;

  /// Por qué, y qué implica.
  final String cuerpo;

  final NexusOrbState orbe;

  /// Un dato en mono: la dirección, el modelo, la ruta. Lo que hace que el mensaje
  /// sea de **este** caso y no genérico.
  final Widget? detalle;

  /// La línea de abajo, más apagada: lo que conviene comprobar.
  final String? pieDeAyuda;

  final List<Widget> acciones;

  /// Lo que va pegado al fondo, como el control de permiso.
  final Widget? abajo;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.void_,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            NexusSpacing.s5,
            NexusSpacing.s4,
            NexusSpacing.s5,
            NexusSpacing.s5,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MobileChrome(),
              const Spacer(),
              // Sin horizonte, al contrario que en la de conectar: el horizonte es lo
              // que dice «trabajando», y aquí no se está trabajando.
              const SizedBox(
                height: 260,
                child: IgnorePointer(
                  child: NexusOrb(
                    state: NexusOrbState.sleep,
                    showHorizon: false,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                titulo,
                key: const ValueKey('titulo-del-estado'),
                style: NexusTypography.subtitleMobile.copyWith(
                  color: colors.ink,
                ),
              ),
              const SizedBox(height: NexusSpacing.s3),
              Text(
                cuerpo,
                style: NexusTypography.body.copyWith(color: colors.mute),
              ),
              if (detalle != null) ...[
                const SizedBox(height: NexusSpacing.s4),
                detalle!,
              ],
              if (acciones.isNotEmpty) ...[
                const SizedBox(height: NexusSpacing.s6),
                Wrap(
                  spacing: NexusSpacing.s3,
                  runSpacing: NexusSpacing.s2,
                  children: acciones,
                ),
              ],
              if (pieDeAyuda != null) ...[
                const SizedBox(height: NexusSpacing.s5),
                Text(
                  pieDeAyuda!,
                  style: NexusTypography.mono.copyWith(color: colors.faint),
                ),
              ],
              // Sin espaciador aquí: el bloque de texto queda **abajo**, como en la de
              // conectar. Con uno, el texto se centraba y el tercio inferior quedaba
              // vacío — que es justo lo que se veía mal.
              ?abajo,
            ],
          ),
        ),
      ),
    );
  }
}

/// Un botón del sistema: borde fino, mono, mayúsculas.
///
/// No un `FilledButton` de Material: el mockup no tiene ninguno relleno salvo la
/// acción principal de emparejar, y el resto son bordes de 1px. Un botón relleno de
/// Material en esta pantalla se ve como de otra app.
class MobileAction extends StatelessWidget {
  const MobileAction({
    super.key,
    required this.texto,
    required this.alTocar,
    this.principal = false,
  });

  final String texto;
  final VoidCallback? alTocar;
  final bool principal;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = principal ? colors.accent : colors.mute;

    return InkWell(
      onTap: alTocar,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: NexusSpacing.s4,
          vertical: NexusSpacing.s3,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: principal
                ? colors.accent.withValues(alpha: 0.5)
                : colors.rule2,
          ),
        ),
        child: Text(
          texto.toUpperCase(),
          style: NexusTypography.label.copyWith(color: color),
        ),
      ),
    );
  }
}

/// Un dato en mono, para el `detalle` de un estado.
class MobileDetail extends StatelessWidget {
  const MobileDetail({super.key, required this.partes});

  /// Se separan con un punto medio, como en los mockups: `macbook-diego · red local`.
  final List<String> partes;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Text(
      partes.join('  ·  '),
      style: NexusTypography.data.copyWith(color: colors.mute),
    );
  }
}
