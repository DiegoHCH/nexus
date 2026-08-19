import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/core/platform/updates_channel.dart';
import 'package:nexus/features/updates/domain/entities/update_stage.dart';
import 'package:nexus/features/updates/presentation/providers/updates_providers.dart';

/// La modal de la actualización: qué hay, qué pesa y cómo va.
///
/// Es nuestra y no la de Sparkle a propósito. El motor sí es de Sparkle —la parte
/// que reemplaza el paquete de la app— pero su diálogo viene en inglés, con el
/// aspecto de AppKit y hablando de «release notes»; dentro de un HUD sobre el
/// vacío eso se lee como si lo hubiera puesto otra aplicación.
///
/// Se abre sola cuando aparece algo, y también desde Ajustes.
class UpdateModal extends ConsumerWidget {
  const UpdateModal({super.key});

  static Future<void> open(BuildContext context) => showDialog<void>(
    context: context,
    // No se cierra tocando fuera: durante la descarga eso dejaría el proceso
    // corriendo sin nada que lo cuente, y quien lo hiciera pensaría que canceló.
    barrierDismissible: false,
    builder: (_) => const UpdateModal(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final estado = ref.watch(updatesControllerProvider);

    // Cuando el proceso vuelve a reposo, la modal se va. Así no hace falta que
    // cada botón se acuerde de cerrarla: se cierra porque ya no hay nada que
    // contar.
    ref.listen(updatesControllerProvider.select((s) => s.stage), (_, fase) {
      if (fase is UpdateIdle && Navigator.canPop(context)) Navigator.pop(context);
    });

    return Dialog(
      backgroundColor: colors.rise,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.rule2),
        borderRadius: BorderRadius.circular(NexusRadius.md),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(NexusSpacing.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            // `min` y no el máximo por defecto: con `max` la tarjeta se estira
            // hasta el alto de la pantalla y el contenido queda flotando arriba.
            // Ya pasó con la tarjeta del tour.
            mainAxisSize: MainAxisSize.min,
            children: _cuerpo(context, ref, estado),
          ),
        ),
      ),
    );
  }

  List<Widget> _cuerpo(BuildContext context, WidgetRef ref, UpdatesState estado) {
    final strings = context.strings;
    final colors = context.colors;
    final control = ref.read(updatesControllerProvider.notifier);
    final corriendo = estado.notice?.current;

    Widget titulo(String texto) => Text(
      texto,
      style: NexusTypography.subtitle.copyWith(color: colors.ink),
    );

    Widget nota(String texto) => Padding(
      padding: const EdgeInsets.only(top: NexusSpacing.s3),
      child: Text(
        texto,
        style: NexusTypography.body.copyWith(color: colors.mute),
      ),
    );

    return switch (estado.stage) {
      UpdateIdle() || UpdateChecking() => [
        titulo(strings.updateChecking),
        const SizedBox(height: NexusSpacing.s4),
        const _Barra(fraction: null),
      ],

      UpdateUpToDate() => [
        titulo(strings.updateUpToDate),
        nota(strings.updateUpToDateBody(corriendo ?? '—')),
        _Botones(
          derecha: (strings.close, () => Navigator.pop(context)),
        ),
      ],

      // Hay versión nueva pero esta copia no puede reemplazarse: se dice **eso**
      // y no se ofrece instalar. Ofrecerlo sería mandar a alguien a esperar una
      // descarga de 23 MB para chocarse con el mismo muro al final.
      final UpdateFound encontrada
          when !(ref.watch(installabilityProvider).value ?? Installability.unknown)
              .canInstall =>
        [
          titulo(strings.updateMoveTitle),
          const SizedBox(height: NexusSpacing.s3),
          _Salto(desde: corriendo ?? '—', hasta: encontrada.version),
          nota(strings.updateMoveBody),
          _Botones(derecha: (strings.close, () => Navigator.pop(context))),
        ],

      final UpdateFound encontrada => [
        titulo(strings.updateFoundTitle),
        const SizedBox(height: NexusSpacing.s3),
        _Salto(desde: corriendo ?? '—', hasta: encontrada.version),
        if (encontrada.notes case final texto? when texto.trim().isNotEmpty)
          _Notas(texto),
        // El peso se dice **antes** de empezar: 23 MB en una conexión mala es una
        // decisión, y se toma con el dato delante.
        if (encontrada.bytes case final peso? when !encontrada.alreadyDownloaded)
          nota(strings.updateWeight(_enMegas(peso))),
        _Botones(
          izquierda: (strings.updateLater, control.masTarde),
          derecha: (
            encontrada.alreadyDownloaded
                ? strings.updateRestart
                : strings.updateInstall,
            control.instalar,
          ),
        ),
      ],

      final UpdateDownloading bajando => [
        titulo(strings.updateDownloading),
        const SizedBox(height: NexusSpacing.s4),
        _Barra(fraction: bajando.fraction),
        nota(
          switch (bajando.total) {
            // Con el total se dice «12,1 de 23,4 MB»; sin él, solo lo bajado.
            final peso? => strings.updateDownloadedOf(
              _enMegas(bajando.received),
              _enMegas(peso),
            ),
            _ => _enMegas(bajando.received),
          },
        ),
        _Botones(izquierda: (strings.cancel, control.cancelar)),
      ],

      final UpdateExtracting sacando => [
        titulo(strings.updateExtracting),
        const SizedBox(height: NexusSpacing.s4),
        _Barra(fraction: sacando.progress),
      ],

      UpdateReady() => [
        titulo(strings.updateReadyTitle),
        // El aviso importa: puede haber un encargo a medio escribir archivos, y
        // reiniciar lo corta. Quien lo lee decide con eso delante.
        nota(strings.updateReadyBody),
        _Botones(
          izquierda: (strings.updateLater, control.masTarde),
          derecha: (strings.updateRestart, control.instalar),
        ),
      ],

      UpdateInstalling() => [
        titulo(strings.updateInstalling),
        const SizedBox(height: NexusSpacing.s4),
        const _Barra(fraction: null),
        nota(strings.updateInstallingBody),
      ],

      final UpdateFailed fallo => [
        titulo(strings.updateFailedTitle),
        nota(fallo.message.isEmpty ? strings.updateFailedBody : fallo.message),
        _Botones(
          izquierda: (strings.close, control.masTarde),
          derecha: (strings.updateRetry, control.comprobarAhora),
        ),
      ],
    };
  }

  /// Con una decimal y no en bytes crudos: «23,4 MB» se lee, «24518656» no.
  static String _enMegas(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// De qué versión a qué versión, que es la información principal.
class _Salto extends StatelessWidget {
  const _Salto({required this.desde, required this.hasta});

  final String desde;
  final String hasta;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Text(desde, style: NexusTypography.data.copyWith(color: colors.faint)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.s3),
          child: Icon(Icons.arrow_forward, size: 14, color: colors.faint),
        ),
        Text(hasta, style: NexusTypography.data.copyWith(color: colors.cyan)),
      ],
    );
  }
}

/// Lo que trae la versión, con tope de alto.
///
/// Con tope porque las notas las escribe quien publica y pueden ser diez líneas
/// o cien: sin esto, una release charlatana empuja los botones fuera de la
/// pantalla y la modal deja de poder cerrarse.
class _Notas extends StatelessWidget {
  const _Notas(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      margin: const EdgeInsets.only(top: NexusSpacing.s4),
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: BoxDecoration(
        color: colors.deep,
        border: Border.all(color: colors.rule),
        borderRadius: BorderRadius.circular(NexusRadius.sm),
      ),
      padding: const EdgeInsets.all(NexusSpacing.s4),
      child: SingleChildScrollView(
        child: Text(
          texto.trim(),
          style: NexusTypography.body.copyWith(color: colors.mute),
        ),
      ),
    );
  }
}

/// La barra de progreso. `null` en [fraction] es indeterminada.
class _Barra extends StatelessWidget {
  const _Barra({required this.fraction});

  final double? fraction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(NexusRadius.sm),
      child: LinearProgressIndicator(
        value: fraction,
        minHeight: 4,
        backgroundColor: colors.rule,
        valueColor: AlwaysStoppedAnimation<Color>(colors.cyan),
      ),
    );
  }
}

/// La fila de botones, con el que confirma a la derecha.
///
/// A la derecha porque es donde macOS pone el botón por defecto, y porque esa
/// misma corrección se pidió en la cabecera de Ajustes: alinear a la derecha lo
/// que cierra o confirma.
class _Botones extends StatelessWidget {
  const _Botones({this.izquierda, this.derecha});

  final (String, VoidCallback)? izquierda;
  final (String, VoidCallback)? derecha;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: NexusSpacing.s6),
    child: Row(
      children: [
        if (izquierda case (final texto, final accion)?)
          TextButton(onPressed: accion, child: Text(texto)),
        const Spacer(),
        if (derecha case (final texto, final accion)?)
          FilledButton(onPressed: accion, child: Text(texto)),
      ],
    ),
  );
}
