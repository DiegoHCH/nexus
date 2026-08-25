import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/core/platform/updates_channel.dart';
import 'package:nexus/features/updates/domain/entities/update_stage.dart';
import 'package:nexus/features/updates/presentation/providers/updates_providers.dart';

/// El aviso de actualización, arriba a la derecha.
///
/// Antes era una modal en el centro con su velo, y era demasiado: una versión
/// nueva es una **noticia**, no una pregunta que haya que contestar antes de
/// seguir. Interrumpir a alguien a media conversación con Claude para anunciarle
/// que hay 23 MB disponibles es cobrar demasiado por lo que se cuenta.
///
/// Del toast de La Oficina se conserva el registro —aparece, se lee de un vistazo
/// y se va— y se cambian dos cosas por necesidad: va arriba a la derecha, y **sí
/// se puede pulsar**, porque aquí hay algo que decidir. Allí el toast lleva
/// `pointer-events: none` justo porque nunca lo hay.
///
/// **No se va solo cuando hay algo pendiente.** Un cartel que se desvanece con
/// una pregunta dentro es peor que una modal: la modal al menos se deja
/// contestar. Solo se retira solo el «estás al día», que no pregunta nada.
class UpdateToast extends ConsumerStatefulWidget {
  const UpdateToast({super.key});

  /// Cuánto tarda en irse lo que no pregunta nada.
  static const seVaSolo = Duration(seconds: 5);

  @override
  ConsumerState<UpdateToast> createState() => _UpdateToastState();
}

class _UpdateToastState extends ConsumerState<UpdateToast> {
  /// Empieza fuera y entra en el primer fotograma: sin esto aparecería de golpe,
  /// que es justo lo que hace que un aviso se sienta como una interrupción.
  bool _dentro = false;

  /// El que retira el «estás al día».
  ///
  /// Vive aquí y **no se programa dentro de `build`**, que es donde estaba: build
  /// corre muchas veces —cada fotograma de la animación de entrada, por ejemplo—
  /// así que encolaba un temporizador por reconstrucción. Lo delató una prueba,
  /// que acabó con temporizadores pendientes.
  Timer? _reloj;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _dentro = true);
    });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(updatesControllerProvider);
    final colors = context.colors;

    // El «estás al día» se retira solo: no pregunta nada, y dejarlo puesto
    // obligaría a cerrar un cartel que solo dice que no pasa nada. Lo demás se
    // queda hasta que alguien lo cierre.
    ref.listen(updatesControllerProvider.select((s) => s.stage), (_, fase) {
      _reloj?.cancel();
      if (fase is! UpdateUpToDate) return;
      _reloj = Timer(UpdateToast.seVaSolo, () {
        if (!mounted) return;
        if (ref.read(updatesControllerProvider).stage is UpdateUpToDate) {
          ref.read(updatesControllerProvider.notifier).descartar();
        }
      });
    });

    if (estado.stage is UpdateIdle) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        // Deja libre la barra de título fundida: pegado arriba del todo se
        // solaparía con los botones de la ventana.
        padding: const EdgeInsets.only(top: 44, right: NexusSpacing.s5),
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          offset: _dentro ? Offset.zero : const Offset(0.25, 0),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: _dentro ? 1 : 0,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 340,
                decoration: BoxDecoration(
                  color: colors.rise,
                  border: Border.all(color: colors.rule2),
                  borderRadius: BorderRadius.circular(NexusRadius.md),
                  boxShadow: [
                    BoxShadow(
                      color: colors.shadow,
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(NexusSpacing.s4),
                child: _Cuerpo(estado: estado),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Cuerpo extends ConsumerWidget {
  const _Cuerpo({required this.estado});

  final UpdatesState estado;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final control = ref.read(updatesControllerProvider.notifier);
    final corriendo = estado.notice?.current;

    // `cerrable` en falso solo mientras instala: ahí ya no hay nada que
    // descartar —la app está a punto de reiniciarse— y una cruz que no deshace
    // nada promete algo que no puede cumplir.
    Widget titulo(String texto, {bool cerrable = true}) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            texto,
            style: NexusTypography.body.copyWith(
              color: colors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (cerrable) _Cerrar(onTap: control.descartar),
      ],
    );

    Widget linea(String texto) => Padding(
      padding: const EdgeInsets.only(top: NexusSpacing.s2),
      child: Text(
        texto,
        style: NexusTypography.label.copyWith(color: colors.mute),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: switch (estado.stage) {
        // Nunca se ve: el toast entero no se monta en reposo. Está por el
        // `switch`, que es exhaustivo a propósito.
        UpdateIdle() => const [SizedBox.shrink()],

        UpdateChecking() => [
          titulo(strings.updateChecking),
          const Padding(
            padding: EdgeInsets.only(top: NexusSpacing.s3),
            child: _Barra(fraction: null),
          ),
        ],

        UpdateUpToDate() => [
          titulo(strings.updateUpToDate),
          linea(strings.updateUpToDateBody(corriendo ?? '—')),
        ],

        // Se anuncia, pero no se ofrece lo que no se puede cumplir: desde una
        // copia traslocada no hay nada que reemplazar.
        final UpdateFound encontrada
            when !(ref.watch(installabilityProvider).value ??
                    Installability.unknown)
                .canInstall =>
          [
            titulo(strings.updateMoveTitle),
            _Salto(desde: corriendo ?? '—', hasta: encontrada.version),
            linea(strings.updateMoveBody),
          ],

        final UpdateFound encontrada => [
          titulo(strings.updateFoundTitle),
          _Salto(desde: corriendo ?? '—', hasta: encontrada.version),
          if (encontrada.notes case final texto? when texto.trim().isNotEmpty)
            _Notas(texto),
          if (encontrada.bytes case final peso?
              when !encontrada.alreadyDownloaded)
            linea(strings.updateWeight(_enMegas(peso))),
          _Acciones(
            secundaria: (strings.updateLater, control.descartar),
            principal: (
              encontrada.alreadyDownloaded
                  ? strings.updateRestart
                  : strings.updateInstall,
              control.instalar,
            ),
          ),
        ],

        final UpdateDownloading bajando => [
          titulo(strings.updateDownloading),
          Padding(
            padding: const EdgeInsets.only(top: NexusSpacing.s3),
            child: _Barra(fraction: bajando.fraction),
          ),
          linea(switch (bajando.total) {
            final peso? => strings.updateDownloadedOf(
              _enMegas(bajando.received),
              _enMegas(peso),
            ),
            _ => _enMegas(bajando.received),
          }),
          _Acciones(secundaria: (strings.cancel, control.cancelar)),
        ],

        final UpdateExtracting sacando => [
          titulo(strings.updateExtracting),
          Padding(
            padding: const EdgeInsets.only(top: NexusSpacing.s3),
            child: _Barra(fraction: sacando.progress),
          ),
        ],

        UpdateReady() => [
          titulo(strings.updateReadyTitle),
          // El aviso se queda aunque el sitio sea pequeño: reiniciar puede cortar
          // un encargo a media escritura, y eso no se decide sin leerlo.
          linea(strings.updateReadyBody),
          _Acciones(
            secundaria: (strings.updateLater, control.descartar),
            principal: (strings.updateRestart, control.instalar),
          ),
        ],

        UpdateInstalling() => [
          titulo(strings.updateInstalling, cerrable: false),
          const Padding(
            padding: EdgeInsets.only(top: NexusSpacing.s3),
            child: _Barra(fraction: null),
          ),
          linea(strings.updateInstallingBody),
        ],

        final UpdateFailed fallo => [
          titulo(strings.updateFailedTitle),
          linea(
            fallo.message.isEmpty ? strings.updateFailedBody : fallo.message,
          ),
          _Acciones(principal: (strings.updateRetry, control.comprobarAhora)),
        ],
      },
    );
  }

  static String _enMegas(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// De qué versión a qué versión.
class _Salto extends StatelessWidget {
  const _Salto({required this.desde, required this.hasta});

  final String desde;
  final String hasta;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: NexusSpacing.s2),
      child: Row(
        children: [
          Text(
            desde,
            style: NexusTypography.data.copyWith(color: colors.faint),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.s2),
            child: Icon(Icons.arrow_forward, size: 12, color: colors.faint),
          ),
          Text(
            hasta,
            style: NexusTypography.data.copyWith(color: colors.accent),
          ),
        ],
      ),
    );
  }
}

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
        minHeight: 3,
        backgroundColor: colors.rule,
        valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
      ),
    );
  }
}

/// Los botones, pequeños y a la derecha.
///
/// Compactos a propósito: en 320 px de ancho los botones de una modal ocupan la
/// mitad del cartel y lo convierten otra vez en algo que reclama atención.
class _Acciones extends StatelessWidget {
  const _Acciones({this.secundaria, this.principal});

  final (String, VoidCallback)? secundaria;
  final (String, VoidCallback)? principal;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: NexusSpacing.s4),
    // `Wrap` y no `Row`: en 320 px «Más tarde» junto a «Reiniciar e instalar»
    // desbordaba 120 px, y con otro idioma o un rótulo más largo volvería a
    // pasar. Así se apilan en vez de romperse — medido con una prueba que sacó
    // la franja amarilla.
    child: Wrap(
      alignment: WrapAlignment.end,
      spacing: NexusSpacing.s2,
      runSpacing: NexusSpacing.s2,
      children: [
        if (secundaria case (final texto, final accion)?)
          TextButton(
            onPressed: accion,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.s3),
              minimumSize: const Size(0, 30),
              visualDensity: VisualDensity.compact,
            ),
            child: Text(texto, style: NexusTypography.label),
          ),
        if (principal case (final texto, final accion)?)
          FilledButton(
            onPressed: accion,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.s4),
              minimumSize: const Size(0, 30),
              visualDensity: VisualDensity.compact,
            ),
            child: Text(texto, style: NexusTypography.label),
          ),
      ],
    ),
  );
}

class _Cerrar extends StatelessWidget {
  const _Cerrar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: context.strings.close,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(NexusRadius.sm),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(Icons.close, size: 14, color: colors.faint),
        ),
      ),
    );
  }
}

/// Qué trae la versión, en pequeño.
///
/// Con tope de alto y desplazable: las notas las escribe quien publica y pueden
/// ser tres líneas o cien. Sin el tope, una release charlatana estiraría el aviso
/// hasta sacar los botones de la pantalla.
///
/// Estuvieron a punto de quedarse fuera «por sutileza», y era un error: «qué
/// trae» es justo la razón por la que alguien diría que sí, y al quitar la modal
/// este es el único sitio donde se puede leer.
class _Notas extends StatelessWidget {
  const _Notas(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      margin: const EdgeInsets.only(top: NexusSpacing.s3),
      constraints: const BoxConstraints(maxHeight: 84),
      decoration: BoxDecoration(
        color: colors.deep,
        borderRadius: BorderRadius.circular(NexusRadius.sm),
      ),
      padding: const EdgeInsets.all(NexusSpacing.s3),
      width: double.infinity,
      child: SingleChildScrollView(
        child: Text(
          texto.trim(),
          style: NexusTypography.label.copyWith(color: colors.mute),
        ),
      ),
    );
  }
}
