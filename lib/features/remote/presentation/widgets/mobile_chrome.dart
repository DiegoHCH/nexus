import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/nexus_colors.dart';
import 'package:nexus/core/design_system/nexus_spacing.dart';
import 'package:nexus/core/design_system/nexus_typography.dart';
import 'package:nexus/features/remote/data/channel_link.dart';
import 'package:nexus/features/remote/presentation/providers/pairing_providers.dart';

/// La cabecera del teléfono: el wordmark y en qué anda.
///
/// **Sale de los mockups y no de Material**, y ese fue el error de la primera versión
/// de estas pantallas: se construyeron con `Theme.of(context).textTheme` y widgets de
/// Material —`Card`, `AppBar`, burbujas redondeadas— cuando el proyecto ya tenía su
/// propio sistema con los tokens exactos. El resultado no se parecía en nada a lo
/// dibujado, y la regla del repositorio dice justamente que los mockups se revisan
/// **antes** de implementar la UI.
///
/// `N E X U S` es el wordmark con su tracking de .42em, y el estado va a la derecha
/// como un chip: mayúsculas, mono, con borde. No es un adorno — es la única forma que
/// tiene el teléfono de decir que lo que enseña es un reflejo y no autonomía.
class MobileChrome extends ConsumerWidget {
  const MobileChrome({super.key, this.alFinal});

  /// Lo que va a la derecha del chip, si hace falta algo más.
  final Widget? alFinal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final estado = ref.watch(linkStateProvider).value ?? LinkState.sinConexion;
    final (texto, vivo) = _decir(estado);

    return Row(
      children: [
        Text(
          'N E X U S',
          style: NexusTypography.brand.copyWith(color: colors.mute),
        ),
        const Spacer(),
        StateChip(
          key: const ValueKey('estado-del-enlace'),
          texto: texto,
          // El acento **solo cuando está conectado**. Un chip siempre encendido no
          // dice nada; el color es la información.
          vivo: vivo,
        ),
        if (alFinal != null) ...[
          const SizedBox(width: NexusSpacing.s3),
          alFinal!,
        ],
      ],
    );
  }

  /// Los estados, con las palabras del mockup donde las hay.
  ///
  /// «Reconectando» y «sin conexión» siguen siendo distintos aunque las dos digan que
  /// ahora no hay Mac: una es «el teléfono está en ello» y la otra «mira si está
  /// encendido». Y los dos que salieron de la primera prueba real —no llego, no
  /// acepta el token— piden cosas distintas: instalar Tailscale o volver a emparejar.
  (String, bool) _decir(LinkState estado) => switch (estado) {
    LinkState.conectado => ('Conectado', true),
    LinkState.conectando => ('Conectando', false),
    LinkState.reconectando => ('Reconectando', false),
    LinkState.resincronizando => ('Al día en un momento', false),
    LinkState.sinConexion => ('Sin conexión', false),
    LinkState.noSeLlega => ('No llego · ¿Tailscale?', false),
    LinkState.rechazado => ('Token rechazado', false),
    LinkState.hayQueActualizar => ('Hay que actualizar', false),
  };
}

/// El chip del mockup: mono, mayúsculas, con borde y tracking.
///
/// Existe como pieza suya porque se usa para más cosas que el estado —«Interrumpido»
/// en una respuesta cortada, «Esperando» en un encargo sin salir— y esas tres cosas
/// tienen que verse iguales o el ojo las lee como niveles distintos.
class StateChip extends StatelessWidget {
  const StateChip({super.key, required this.texto, this.vivo = false});

  final String texto;

  /// En acento. Se reserva para lo que está pasando ahora.
  final bool vivo;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = vivo ? colors.accent : colors.faint;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.s2,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        // 2px y no un pill: el sistema de esta app es de esquinas casi rectas, y un
        // radio grande lo delata como venido de otro sitio.
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: vivo ? color.withValues(alpha: 0.4) : colors.rule,
        ),
      ),
      child: Text(
        texto.toUpperCase(),
        style: NexusTypography.label.copyWith(color: color),
      ),
    );
  }
}

/// El permiso, como el control segmentado del mockup.
///
/// **Es un eje de dos posiciones y no un interruptor**: «solo leer» y «puede editar»
/// se ven a la vez, y cuál está activo se lee de un vistazo. Un `Switch` obligaría a
/// recordar qué significa encendido — y aquí lo que está en juego es si algo va a
/// escribir en tus archivos.
class PermissionToggle extends StatelessWidget {
  const PermissionToggle({
    super.key,
    required this.puedeEditar,
    required this.alTocar,
  });

  final bool puedeEditar;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      constraints: const BoxConstraints(minHeight: 32),
      decoration: BoxDecoration(
        border: Border.all(color: colors.rule2),
        borderRadius: BorderRadius.circular(2),
      ),
      clipBehavior: Clip.hardEdge,
      child: Row(
        children: [
          _Lado(
            key: const ValueKey('solo-leer'),
            texto: 'Solo leer',
            activo: !puedeEditar,
            // Bajar a solo lectura no necesita frase: **quitarse permiso siempre se
            // puede**. Subir es lo que la pide.
            alTocar: puedeEditar ? alTocar : null,
          ),
          _Lado(
            key: const ValueKey('puede-editar'),
            texto: 'Puede editar',
            activo: puedeEditar,
            alTocar: puedeEditar ? null : alTocar,
            enAcento: true,
          ),
        ],
      ),
    );
  }
}

class _Lado extends StatelessWidget {
  const _Lado({
    super.key,
    required this.texto,
    required this.activo,
    required this.alTocar,
    this.enAcento = false,
  });

  final String texto;
  final bool activo;
  final VoidCallback? alTocar;
  final bool enAcento;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = activo
        ? (enAcento ? colors.accent : colors.ink)
        : colors.faint;

    return Expanded(
      child: InkWell(
        onTap: alTocar,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: NexusSpacing.s2),
          // El activo se marca con fondo y no con negrita: cambiar el peso de la
          // letra mueve el texto un pelo y el ojo lo nota como un salto.
          color: activo ? colors.rise : Colors.transparent,
          child: Text(
            texto.toUpperCase(),
            style: NexusTypography.label.copyWith(color: color),
          ),
        ),
      ),
    );
  }
}
