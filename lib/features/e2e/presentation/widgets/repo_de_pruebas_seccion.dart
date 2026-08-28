import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/e2e/data/datasources/repo_de_pruebas_data_source.dart';
import 'package:nexus/features/e2e/domain/entities/pasada_de_prueba.dart';
import 'package:nexus/features/e2e/presentation/providers/e2e_providers.dart';
import 'package:nexus/features/e2e/presentation/providers/repo_de_pruebas_providers.dart';
import 'package:nexus/features/e2e/presentation/widgets/cuentas_de_prueba_sheet.dart';

/// Los flows que viven en el repo de pruebas del equipo.
///
/// **Separado de la lanzadera del proyecto y no mezclado con ella.** Son dos
/// orígenes con reglas distintas: los del proyecto salen de una carpeta que eliges
/// tú y corren con el `.env.local` del repo; éstos vienen de un remoto compartido y
/// corren con una cuenta configurada. Mezclarlos en una sola lista dejaría dos
/// filas idénticas que hacen cosas distintas, que es lo que hace que alguien lance
/// la que no era.
class RepoDePruebasSeccion extends ConsumerWidget {
  const RepoDePruebasSeccion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final sync = ref.watch(clonDelRepoProvider);
    final slug = ref.watch(slugDelRepoDePruebasProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              strings.e2eRepoTitle,
              style: NexusTypography.label.copyWith(color: colors.faint),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => CuentasDePruebaSheet.open(context),
              child: Text(strings.e2eAccounts),
            ),
          ],
        ),
        Text(slug, style: NexusTypography.data.copyWith(color: colors.mute)),
        const SizedBox(height: NexusSpacing.s2),

        sync.when(
          // **Mientras clona no se enseña una lista vacía.** Un «no hay flows» que
          // dura tres segundos y luego se llena es indistinguible de un repo vacío,
          // y quien lo lea ya se fue a mirar por qué.
          loading: () => Text(
            strings.e2eRepoUpdating,
            style: NexusTypography.body.copyWith(color: colors.mute),
          ),
          error: (e, _) => _Problema(mensaje: '$e'),
          data: (resultado) => _Estado(resultado: resultado),
        ),
      ],
    );
  }
}

/// El estado del clon y, si se pide, la lista de flows.
///
/// **Plegada de partida.** El repo trae 75 flows y esta sección vive entre la
/// lanzadera y el historial: desplegada por defecto, el historial queda a setenta
/// filas de scroll de distancia y deja de existir para quien abre el sheet. Lo que
/// se necesita siempre es el estado y el número; la lista es lo que se pide.
class _Estado extends ConsumerStatefulWidget {
  const _Estado({required this.resultado});

  final ResultadoDeSync resultado;

  @override
  ConsumerState<_Estado> createState() => _EstadoState();
}

class _EstadoState extends ConsumerState<_Estado> {
  bool _abierta = false;

  @override
  Widget build(BuildContext context) {
    final resultado = widget.resultado;
    final colors = context.colors;
    final strings = context.strings;

    final (texto, color) = switch (resultado.como) {
      ComoFueLaSync.clonado => (strings.e2eRepoCloned, colors.ok),
      ComoFueLaSync.aldia => (strings.e2eRepoUpToDate, colors.ok),
      ComoFueLaSync.sucio => (strings.e2eRepoDirty, colors.warn),
      ComoFueLaSync.fallo => (strings.e2eRepoFailed, colors.err),
    };

    if (!resultado.sirve) {
      return _Problema(mensaje: resultado.detalle, cabecera: texto);
    }

    final flows = ref.watch(flowsDelRepoProvider).value ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: flows.isEmpty
              ? null
              : () => setState(() => _abierta = !_abierta),
          child: Row(
            children: [
              Text(texto, style: NexusTypography.label.copyWith(color: color)),
              const SizedBox(width: NexusSpacing.s2),
              Text(
                strings.e2eRepoFlows(flows.length),
                style: NexusTypography.label.copyWith(color: colors.faint),
              ),
              if (flows.isNotEmpty)
                Icon(
                  _abierta ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: colors.faint,
                ),
            ],
          ),
        ),
        if (flows.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: NexusSpacing.s2),
            child: Text(
              strings.e2eRepoNoFlows,
              style: NexusTypography.body.copyWith(color: colors.mute),
            ),
          )
        else if (_abierta) ...[
          const SizedBox(height: NexusSpacing.s3),
          for (final ruta in flows)
            _FilaDeFlow(clon: resultado.clon!, ruta: ruta),
        ],
      ],
    );
  }
}

class _Problema extends ConsumerWidget {
  const _Problema({required this.mensaje, this.cabecera});

  final String mensaje;
  final String? cabecera;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          cabecera ?? strings.e2eRepoFailed,
          style: NexusTypography.label.copyWith(color: colors.err),
        ),
        if (mensaje.isNotEmpty)
          Text(
            mensaje,
            style: NexusTypography.body.copyWith(color: colors.mute),
          ),
        TextButton(
          // Invalidar y no reintentar dentro: así el estado de carga vuelve a
          // pasar por el mismo sitio y la UI no tiene dos caminos para lo mismo.
          onPressed: () => ref.invalidate(clonDelRepoProvider),
          child: Text(strings.e2eRepoRetry),
        ),
      ],
    );
  }
}

/// Un flow del repo: cómo se llama, con qué cuenta corre y el botón de correrlo.
class _FilaDeFlow extends ConsumerWidget {
  const _FilaDeFlow({required this.clon, required this.ruta});

  final String clon;
  final String ruta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;

    final leToca = ref.watch(cuentaDelFlowProvider(ruta)).value;
    final dispositivo = ref.watch(elDispositivoProvider);
    final corriendo = ref.watch(pruebaEnMarchaProvider)?.viva ?? false;

    // **El botón no ofrece lo que no puede pasar**, misma regla que la lanzadera
    // del proyecto: sin dispositivo, sin cuenta o con otra corriendo, se apaga y
    // el motivo se lee debajo en vez de llegar después de tocarlo.
    final cuenta = leToca?.cuenta;
    final sePuede = !corriendo && dispositivo != null && cuenta != null;
    final porQueNo = leToca?.porQueNo;

    return Padding(
      padding: const EdgeInsets.only(bottom: NexusSpacing.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // Sin `flows/` delante: es el prefijo de todas y no distingue
                  // ninguna, así que solo gasta ancho.
                  ruta.startsWith('flows/') ? ruta.substring(6) : ruta,
                  style: NexusTypography.data.copyWith(color: colors.ink),
                ),
                if (cuenta != null)
                  Text(
                    'acct-${(cuenta.tags.toList()..sort()).join(' · acct-')}',
                    style: NexusTypography.label.copyWith(color: colors.faint),
                  )
                else if (porQueNo != null)
                  Text(
                    porQueNo,
                    style: NexusTypography.label.copyWith(color: colors.warn),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: sePuede
                ? () => ref
                      .read(pruebaEnMarchaProvider.notifier)
                      .lanzar(
                        prueba: Prueba(
                          ruta: '$clon/$ruta',
                          nombre: ruta
                              .split('/')
                              .last
                              .replaceAll(RegExp(r'\.ya?ml$'), ''),
                        ),
                        // El proyecto es el clon: así la pasada queda atribuida al
                        // repo de pruebas y no al que tengas emparejado, que no
                        // tiene nada que ver con este flow.
                        proyecto: clon,
                        deviceId: dispositivo,
                        perfil: cuenta.clave,
                        credenciales: cuenta.variables,
                      )
                : null,
            child: Text(strings.e2eRun),
          ),
        ],
      ),
    );
  }
}
