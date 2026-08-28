import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/e2e/data/datasources/repo_de_pruebas_data_source.dart';
import 'package:nexus/features/e2e/domain/entities/pasada_de_prueba.dart';
import 'package:nexus/features/e2e/domain/usecases/como_se_agrupan_los_flows.dart';
import 'package:nexus/features/e2e/presentation/providers/e2e_providers.dart';
import 'package:nexus/features/e2e/presentation/providers/repo_de_pruebas_providers.dart';

/// Los flows que viven en el repo de pruebas del equipo.
///
/// **Separado de la lanzadera del proyecto y no mezclado con ella.** Son dos
/// orígenes con reglas distintas: los del proyecto salen de una carpeta que eliges
/// tú y corren con el `.env.local` del repo; éstos vienen de un remoto compartido y
/// corren con una cuenta configurada. Mezclarlos en una sola lista dejaría dos
/// filas idénticas que hacen cosas distintas, que es lo que hace que alguien lance
/// la que no era.
class RepoDePruebasSeccion extends ConsumerWidget {
  const RepoDePruebasSeccion({super.key, required this.proyecto});

  /// El repo emparejado. **Las cuentas cuelgan de él y no de este repo de
  /// pruebas**: estos flows son las pruebas de ese proyecto, así que corren con
  /// sus credenciales. Configurarlas dos veces —una para sus pruebas locales y
  /// otra para éstas— es el duplicado que acaba con las dos copias distintas.
  final String proyecto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final sync = ref.watch(clonDelRepoProvider);
    final slug = ref.watch(slugDelRepoDePruebasProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.e2eRepoTitle,
          style: NexusTypography.label.copyWith(color: colors.faint),
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
          data: (resultado) =>
              _Estado(resultado: resultado, proyecto: proyecto),
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
  const _Estado({required this.resultado, required this.proyecto});

  final ResultadoDeSync resultado;
  final String proyecto;

  @override
  ConsumerState<_Estado> createState() => _EstadoState();
}

class _EstadoState extends ConsumerState<_Estado> {
  /// Qué grupos están abiertos. **Solo «Pruebas» de partida**: es a lo que viene
  /// todo el mundo, y abrir los cinco deja la misma tira de la que se venía.
  final _abiertos = <ClaseDeGrupo>{ClaseDeGrupo.pruebas};
  final _carpetasAbiertas = <String>{};
  final _buscar = TextEditingController();

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  bool _estaAbierto(GrupoDeFlows g, bool buscando) =>
      // Buscando se abre todo lo que tenga algo: esconder una coincidencia
      // detrás de un triángulo es no haberla encontrado.
      (buscando && g.rutas.isNotEmpty) ||
      (g.clase == ClaseDeGrupo.carpeta
          ? _carpetasAbiertas.contains(g.carpeta)
          : _abiertos.contains(g.clase));

  void _alterna(GrupoDeFlows g) => setState(() {
    if (g.clase == ClaseDeGrupo.carpeta) {
      _carpetasAbiertas.contains(g.carpeta)
          ? _carpetasAbiertas.remove(g.carpeta)
          : _carpetasAbiertas.add(g.carpeta);
      return;
    }
    _abiertos.contains(g.clase)
        ? _abiertos.remove(g.clase)
        : _abiertos.add(g.clase);
  });

  String _titulo(GrupoDeFlows g, NexusStrings strings) => switch (g.clase) {
    ClaseDeGrupo.pruebas => strings.e2eRepoGroupTests,
    ClaseDeGrupo.piezas => strings.e2eRepoGroupPieces,
    ClaseDeGrupo.carpeta => g.carpeta,
  };

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
    final piezas = ref.watch(piezasDelRepoProvider).value ?? const <String>{};
    final sinCuentas = ref
        .watch(cuentasDePruebaProvider(widget.proyecto))
        .isEmpty;
    final buscando = ref.watch(buscandoDispositivosProvider);
    final sinDispositivo = !buscando && ref.watch(elDispositivoProvider) == null;
    final hayDestinos = ref.watch(dondeCorrerProvider).isNotEmpty;

    final filtro = _buscar.text.trim();
    final grupos = ComoSeAgrupanLosFlows.repartir(
      rutas: flows,
      piezas: piezas,
      filtro: filtro,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(texto, style: NexusTypography.label.copyWith(color: color)),
            const SizedBox(width: NexusSpacing.s2),
            Text(
              strings.e2eRepoFlows(flows.length),
              style: NexusTypography.label.copyWith(color: colors.faint),
            ),
          ],
        ),

        if (sinCuentas)
          Padding(
            padding: const EdgeInsets.only(top: NexusSpacing.s2),
            child: Text(
              strings.e2eAccountsNoneHere,
              style: NexusTypography.body.copyWith(color: colors.warn),
            ),
          ),
        if (sinDispositivo)
          Padding(
            padding: const EdgeInsets.only(top: NexusSpacing.s2),
            child: Text(
              hayDestinos ? strings.e2eRepoNeedsDevice : strings.e2eNoDevice,
              style: NexusTypography.body.copyWith(color: colors.warn),
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
        else ...[
          const SizedBox(height: NexusSpacing.s3),
          TextField(
            key: const ValueKey('buscar-una-prueba'),
            controller: _buscar,
            style: NexusTypography.mono.copyWith(color: colors.ink),
            decoration: InputDecoration(
              isDense: true,
              hintText: strings.e2eRepoSearch,
              hintStyle: NexusTypography.mono.copyWith(color: colors.rule2),
              prefixIcon: Icon(Icons.search, size: 16, color: colors.faint),
              prefixIconConstraints: const BoxConstraints(minWidth: 28),
              suffixIcon: filtro.isEmpty
                  ? null
                  : IconButton(
                      icon: Icon(Icons.close, size: 14, color: colors.faint),
                      onPressed: () => setState(_buscar.clear),
                    ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: NexusSpacing.s3),

          for (final grupo in grupos) ...[
            InkWell(
              onTap: grupo.rutas.isEmpty ? null : () => _alterna(grupo),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: NexusSpacing.s1,
                ),
                child: Row(
                  children: [
                    Icon(
                      _estaAbierto(grupo, filtro.isNotEmpty)
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 16,
                      color: grupo.rutas.isEmpty ? colors.rule2 : colors.faint,
                    ),
                    const SizedBox(width: NexusSpacing.s1),
                    Text(
                      _titulo(grupo, strings),
                      style: NexusTypography.label.copyWith(
                        color: grupo.rutas.isEmpty ? colors.rule2 : colors.mute,
                      ),
                    ),
                    const SizedBox(width: NexusSpacing.s2),
                    Text(
                      strings.e2eRepoMatches(grupo.rutas.length, grupo.total),
                      style: NexusTypography.label.copyWith(color: colors.faint),
                    ),
                  ],
                ),
              ),
            ),
            if (_estaAbierto(grupo, filtro.isNotEmpty))
              Padding(
                padding: const EdgeInsets.only(
                  left: NexusSpacing.s4,
                  bottom: NexusSpacing.s2,
                ),
                child: Column(
                  children: [
                    for (final ruta in grupo.rutas)
                      _FilaDeFlow(
                        clon: resultado.clon!,
                        ruta: ruta,
                        proyecto: widget.proyecto,
                        sinCuentas: sinCuentas,
                      ),
                  ],
                ),
              ),
          ],
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
  const _FilaDeFlow({
    required this.clon,
    required this.ruta,
    required this.proyecto,
    required this.sinCuentas,
  });

  final String clon;
  final String ruta;
  final String proyecto;

  /// Si no hay ninguna cuenta configurada. La fila entonces se calla el motivo:
  /// ya lo dice la sección, una vez y con el botón para resolverlo.
  final bool sinCuentas;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;

    final leToca = ref
        .watch(cuentaDelFlowProvider((proyecto: proyecto, ruta: ruta)))
        .value;
    final dispositivo = ref.watch(elDispositivoProvider);
    final corriendo = ref.watch(pruebaEnMarchaProvider)?.viva ?? false;

    // **El botón no ofrece lo que no puede pasar**, misma regla que la lanzadera
    // del proyecto: sin dispositivo, sin cuenta o con otra corriendo, se apaga y
    // el motivo se lee debajo en vez de llegar después de tocarlo.
    final cuenta = leToca?.cuenta;
    // `sePuede` de la cuenta, no `cuenta != null`: tener cuenta no basta si le
    // faltan variables que el flow nombra. Dejar lanzar ahí cuesta la pasada
    // entera y manda a buscar al sitio equivocado.
    final sePuede =
        !corriendo && dispositivo != null && (leToca?.sePuede ?? false);
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
                // El motivo manda sobre la etiqueta: si no se puede correr, lo
                // que hace falta saber es por qué, no con qué cuenta iba a ir.
                if (porQueNo != null && !(sinCuentas && cuenta == null))
                  Text(
                    porQueNo,
                    style: NexusTypography.label.copyWith(color: colors.warn),
                  )
                else if (cuenta != null)
                  Text(
                    'acct-${(cuenta.tags.toList()..sort()).join(' · acct-')}',
                    style: NexusTypography.label.copyWith(color: colors.faint),
                  ),
              ],
            ),
          ),
          TextButton(
            // `sePuede` ya garantiza que hay cuenta y dispositivo, pero el
            // compilador no lo deduce a través de un booleano: se comprueba aquí
            // para que el día que `sePuede` cambie, esto no lance en tiempo de
            // ejecución.
            onPressed: sePuede && cuenta != null
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
