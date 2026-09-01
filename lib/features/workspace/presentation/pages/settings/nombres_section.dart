import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/workspace/domain/entities/los_nombres.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

/// Cómo se llama quien contesta y cómo te llama a ti.
///
/// 🔴 **La app sigue llamándose Nexus, y eso se dice aquí.** El nombre del
/// producto está compilado dentro —Dock, ventana, identificador de los canales
/// nativos y del llavero— así que no es un ajuste. Lo que se elige es quién te
/// contesta, y quien abra esta pantalla esperando renombrar la app tiene que
/// salir sabiendo la diferencia sin haber probado nada.
class NombresSection extends ConsumerWidget {
  const NombresSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final nombres = ref.watch(losNombresProvider);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.nombresExplainer,
            style: NexusTypography.mono.copyWith(color: colors.faint),
          ),
          const SizedBox(height: NexusSpacing.s5),
          _UnNombre(
            etiqueta: strings.comoSeLlamaElAgente,
            pista: strings.comoSeLlamaElAgentePista,
            valor: nombres.agente,
            onGuardar: (valor) =>
                ref.read(losNombresProvider.notifier).cambiar(agente: valor),
          ),
          const SizedBox(height: NexusSpacing.s6),
          _UnNombre(
            etiqueta: strings.comoTeLlamas,
            pista: strings.comoTeLlamasPista,
            valor: nombres.tuyo,
            onGuardar: (valor) =>
                ref.read(losNombresProvider.notifier).cambiar(tuyo: valor),
          ),
          const SizedBox(height: NexusSpacing.s6),
          // La vista previa: es lo único que convierte «te llamas Patricia» en
          // algo comprobable sin cerrar Ajustes y mandar un encargo.
          Text(
            strings.asiSeVera,
            style: NexusTypography.label.copyWith(color: colors.faint),
          ),
          const SizedBox(height: NexusSpacing.s2),
          _ComoSeVera(nombres: nombres),
          const SizedBox(height: NexusSpacing.s5),
          Text(
            strings.sinPalabraDeActivacion,
            style: NexusTypography.mono.copyWith(color: colors.warn),
          ),
        ],
      ),
    );
  }
}

/// Un campo que **guarda al salir del foco**, no con un botón.
///
/// Dos campos con dos botones de guardar son cuatro clics para decir dos
/// palabras. Y guardar en cada tecla escribiría en preferencias una vez por
/// letra, que es ruido en el disco por nada.
class _UnNombre extends StatefulWidget {
  const _UnNombre({
    required this.etiqueta,
    required this.pista,
    required this.valor,
    required this.onGuardar,
  });

  final String etiqueta;
  final String pista;
  final String? valor;

  /// Recibe `null` cuando el campo se deja vacío, que es cómo se borra.
  final void Function(Object? valor) onGuardar;

  @override
  State<_UnNombre> createState() => _UnNombreState();
}

class _UnNombreState extends State<_UnNombre> {
  late final _controller = TextEditingController(text: widget.valor ?? '');
  final _foco = FocusNode();

  @override
  void initState() {
    super.initState();
    _foco.addListener(() {
      if (!_foco.hasFocus) _guardar();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _foco.dispose();
    super.dispose();
  }

  void _guardar() {
    final escrito = _controller.text.trim();
    // Un `null` explícito borra el nombre; el centinela del `copyWith` es lo que
    // permite distinguirlo de «no lo toques».
    widget.onGuardar(escrito.isEmpty ? null : escrito);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.etiqueta,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),
        TextField(
          controller: _controller,
          focusNode: _foco,
          style: NexusTypography.body.copyWith(color: colors.ink),
          onSubmitted: (_) => _guardar(),
          decoration: InputDecoration(
            hintText: widget.pista,
            hintStyle: NexusTypography.body.copyWith(color: colors.faint),
            filled: true,
            fillColor: colors.void_.withValues(alpha: 0.5),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(NexusRadius.sm),
              borderSide: BorderSide(color: colors.rule),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(NexusRadius.sm),
              borderSide: BorderSide(color: colors.rule),
            ),
          ),
        ),
      ],
    );
  }
}

/// Un turno de mentira con los nombres puestos.
class _ComoSeVera extends StatelessWidget {
  const _ComoSeVera({required this.nombres});

  final LosNombres nombres;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(NexusSpacing.s3),
      decoration: BoxDecoration(
        color: colors.void_.withValues(alpha: 0.5),
        border: Border.all(color: colors.rule),
        borderRadius: BorderRadius.circular(NexusRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.you,
            style: NexusTypography.label.copyWith(color: colors.faint),
          ),
          const SizedBox(height: 2),
          Text(
            strings.ejemploDeLoQuePides(nombres.agente ?? strings.nexus),
            style: NexusTypography.body.copyWith(color: colors.ink),
          ),
          const SizedBox(height: NexusSpacing.s3),
          Text(
            nombres.etiqueta(strings.nexus),
            style: NexusTypography.label.copyWith(color: colors.accent),
          ),
          const SizedBox(height: 2),
          Text(
            strings.ejemploDeLoQueContesta(nombres.vocativo),
            style: NexusTypography.body.copyWith(color: colors.mute),
          ),
        ],
      ),
    );
  }
}
