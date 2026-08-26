import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/design_system/selector_compacto.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/e2e/domain/entities/corrida_de_prueba.dart';
import 'package:nexus/features/e2e/domain/usecases/pasos_de_una_prueba.dart';
import 'package:nexus/features/e2e/presentation/providers/e2e_providers.dart';
import 'package:nexus/features/emulators/presentation/providers/emuladores_providers.dart';

/// Las pruebas de la app: las que hay, las que corrieron, y una corriendo.
///
/// **Un sheet y no una sección de Ajustes**, al contrario que los emuladores. La
/// diferencia es la misma que separa el visor de documentos de una preferencia:
/// esto trae algo que acabas de pedir —una prueba que corre ahora— y por eso
/// interrumpe. Un emulador se consulta antes de trabajar; una prueba se mira
/// mientras pasa.
class PruebasSheet extends ConsumerWidget {
  const PruebasSheet({super.key, required this.proyecto});

  final String? proyecto;

  /// Se abre así, como el de documentos.
  static Future<void> open(BuildContext context, {String? proyecto}) =>
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => PruebasSheet(proyecto: proyecto),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final enMarcha = ref.watch(pruebaEnMarchaProvider);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      decoration: BoxDecoration(
        color: colors.deep,
        border: Border(top: BorderSide(color: colors.rule)),
      ),
      padding: const EdgeInsets.all(NexusSpacing.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            strings.e2eTitle,
            style: NexusTypography.label.copyWith(color: colors.faint),
          ),
          const SizedBox(height: NexusSpacing.s4),

          // **Lo que corre no se pinta aquí, se avisa.** La vista de una prueba
          // en marcha es su propia pantalla —ver [PruebaEnMarchaPage]— porque se
          // mira mientras avanza y compartir sitio con una lista que no cambia la
          // dejaba en un rincón. Aquí solo queda la puerta.
          // **Solo mientras corre.** Al acabar, la corrida ya está en el
          // historial de abajo con sus dos botones, y tenerla arriba además era
          // enseñar lo mismo dos veces con acciones distintas en cada sitio.
          if (enMarcha != null && enMarcha.viva) ...[
            _AvisoDeQueCorre(prueba: enMarcha),
            const SizedBox(height: NexusSpacing.s4),
          ],

          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (proyecto case final p?) _Lanzadera(proyecto: p),
                  const SizedBox(height: NexusSpacing.s5),
                  const _Historial(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Que hay una corriendo, y por dónde va.
///
/// **La vista de verdad está en una ventana del sistema aparte**, no en una
/// pantalla encima de esta: una pantalla encima impide seguir trabajando, que es
/// justo lo que se reportó. Se hace reusando el visor de documentos —una
/// `NSWindow` con `WKWebView` que vigila su archivo— así que se actualiza sola,
/// se puede dejar al lado y se cierra cuando estorbe.
class _AvisoDeQueCorre extends ConsumerWidget {
  const _AvisoDeQueCorre({required this.prueba});

  final PruebaEnMarcha prueba;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.s4,
        vertical: NexusSpacing.s3,
      ),
      decoration: BoxDecoration(
        color: colors.void_.withValues(alpha: 0.5),
        border: Border.all(color: prueba.viva ? colors.accent : colors.rule),
        borderRadius: BorderRadius.circular(NexusRadius.sm),
      ),
      child: Row(
        children: [
          if (prueba.viva)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: colors.accent,
              ),
            )
          else
            Icon(
              prueba.fallo ? Icons.close : Icons.check,
              size: 14,
              color: prueba.fallo ? colors.err : colors.ok,
            ),
          const SizedBox(width: NexusSpacing.s3),
          Expanded(
            child: Text(
              '${prueba.flow} · ${prueba.terminados}/${prueba.pasos.length}',
              style: NexusTypography.data.copyWith(color: colors.ink),
            ),
          ),
          TextButton(
            style: _apretado,
            onPressed: ref.read(pruebaEnMarchaProvider.notifier).traeLaVentana,
            child: Text(strings.e2eSee),
          ),
        ],
      ),
    );
  }
}

final _apretado = TextButton.styleFrom(
  padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.s2),
  minimumSize: Size.zero,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  visualDensity: VisualDensity.compact,
);

/// Elegir una prueba de este proyecto y lanzarla.
class _Lanzadera extends ConsumerStatefulWidget {
  const _Lanzadera({required this.proyecto});

  final String proyecto;

  @override
  ConsumerState<_Lanzadera> createState() => _LanzaderaState();
}

class _LanzaderaState extends ConsumerState<_Lanzadera> {
  String? _dispositivo;
  String? _error;
  String? _confirmandoBorrado;
  var _arrancando = false;

  /// Los dispositivos sobre los que se puede correr: **encendidos y nada más**.
  ///
  /// Un `maestro test --device` contra un emulador apagado falla, así que
  /// ofrecerlo sería ofrecer ese fallo — el mismo criterio que el panel de correr
  /// la app. Para encenderlo está el icono de los dispositivos.
  List<String> get _dispositivos => [
    for (final e in ref.watch(emuladoresProvider).value?.emuladores ?? const [])
      if (e.corriendo && e.deviceId != null) e.deviceId!,
    for (final d in ref.watch(dispositivosProvider).value ?? const []) d.id,
  ];

  /// Cuál se usa: el elegido, o el único que haya.
  ///
  /// **Elegir hace falta de verdad**: con el Redmi enchufado y un emulador
  /// arriba hay dos, y coger el primero era decidir por el usuario en silencio —
  /// exactamente lo que reportó al no poder elegir. Con uno solo no se pregunta,
  /// que sería una pregunta con una sola respuesta.
  String? get _elegido {
    final hay = _dispositivos;
    if (_dispositivo case final elegido? when hay.contains(elegido)) {
      return elegido;
    }
    return hay.length == 1 ? hay.single : null;
  }

  /// Arranca un emulador y espera a que exista.
  ///
  /// **Maestro no arranca nada**: sin dispositivo encendido, `--device` falla. Y
  /// arrancarlo es algo que Nexus ya sabe hacer —incluido esperar a que aparezca,
  /// que el comando vuelve antes que el aparato—, así que en vez de decir «hace
  /// falta un dispositivo» se ofrece encenderlo.
  Future<void> _arrancarUno() async {
    final apagados = ref
        .read(emuladoresProvider)
        .value
        ?.emuladores
        .where((e) => !e.corriendo)
        .toList();
    if (apagados == null || apagados.isEmpty) return;

    setState(() {
      _arrancando = true;
      _error = null;
    });
    final error = await ref
        .read(emuladoresDataSourceProvider)
        .lanzar(apagados.first);
    ref.invalidate(emuladoresProvider);
    if (!mounted) return;
    setState(() {
      _arrancando = false;
      _error = error;
    });
  }

  Future<void> _lanzar(Prueba prueba) async {
    final dispositivos = _dispositivos;
    if (dispositivos.isEmpty) {
      setState(() => _error = context.strings.e2eNoDevice);
      return;
    }
    final donde = _elegido;
    if (donde == null) {
      setState(() => _error = context.strings.e2eDevice);
      return;
    }
    setState(() => _error = null);

    // **Antes de correr: ¿está la app ahí?** Maestro no la instala, y sin ella la
    // prueba falla en el primer `launchApp` con «Package … is not installed»
    // **saliendo con código 0** — un fallo disfrazado de éxito. Decirlo antes
    // cuesta 70 ms y ahorra leer un informe engañoso.
    //
    // Solo se para cuando se sabe que **no** está: `null` es «no se pudo
    // comprobar» —un iPhone, sin adb— y ahí no se bloquea nada.
    final yaml = await File(prueba.ruta).readAsString().catchError((_) => '');
    if (PasosDeUnaPrueba.appIdDe(yaml) case final appId?) {
      final instalada = await ref
          .read(e2eDataSourceProvider)
          .estaInstalada(deviceId: donde, appId: appId);
      if (instalada == false) {
        if (!mounted) return;
        setState(() => _error = context.strings.e2eNotInstalled);
        return;
      }
    }
    if (!mounted) return;

    final error = await ref
        .read(pruebaEnMarchaProvider.notifier)
        .lanzar(
          prueba: prueba,
          proyecto: widget.proyecto,
          deviceId: donde,
          perfil: 'local',
        );
    if (!mounted) return;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    // Su ventana se abre sola al lanzar: es lo que se va a mirar durante el
    // próximo medio minuto. Y al ser una ventana aparte, la app sigue usable.
  }

  Future<void> _borrar(Prueba prueba) async {
    // Dos toques y no una modal: el primero pide confirmación en la propia fila,
    // el segundo borra. Una modal para un archivo que git recupera es más
    // ceremonia que riesgo.
    if (_confirmandoBorrado != prueba.ruta) {
      setState(() => _confirmandoBorrado = prueba.ruta);
      return;
    }
    await ref.read(e2eDataSourceProvider).borrarPrueba(prueba.ruta);
    ref.invalidate(pruebasProvider(widget.proyecto));
    if (!mounted) return;
    setState(() => _confirmandoBorrado = null);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;
    final pruebas = ref.watch(pruebasProvider(widget.proyecto)).value ?? const [];
    final corriendo = ref.watch(pruebaEnMarchaProvider)?.viva ?? false;
    final dispositivos = _dispositivos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // **De qué proyecto son estas pruebas.** El historial ya lo decía y la
        // lista no, así que se leía como si fueran de nadie. Un `.maestro/` es de
        // su repo y de ninguno más.
        Text(
          widget.proyecto.split('/').last,
          style: NexusTypography.label.copyWith(color: colors.faint),
        ),
        const SizedBox(height: NexusSpacing.s2),

        if (pruebas.isEmpty)
          Text(
            strings.e2eNone,
            style: NexusTypography.mono.copyWith(color: colors.faint),
          )
        else ...[
          // **Sin nada encendido, se ofrece encenderlo** en vez de decir que
          // falta. Es lo único que separa «no puedo correr» de «dame 30 s».
          if (dispositivos.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: NexusSpacing.s3),
              child: _arrancando
                  ? Row(
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: colors.accent,
                          ),
                        ),
                        const SizedBox(width: NexusSpacing.s3),
                        Text(
                          strings.e2eStarting,
                          style: NexusTypography.mono.copyWith(
                            color: colors.faint,
                          ),
                        ),
                      ],
                    )
                  : OutlinedButton(
                      onPressed: _arrancarUno,
                      child: Text(strings.e2eStartDevice),
                    ),
            ),
          // El dispositivo, y solo cuando hay más de uno que elegir.
          if (dispositivos.length > 1) ...[
            SelectorCompacto(
              valor: _elegido,
              opciones: dispositivos,
              pista: strings.e2eDevice,
              onElegir: (v) => setState(() => _dispositivo = v),
            ),
            const SizedBox(height: NexusSpacing.s3),
          ],

          for (final prueba in pruebas)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 13,
                    color: colors.faint,
                  ),
                  const SizedBox(width: NexusSpacing.s3),
                  Expanded(
                    child: Text(
                      prueba.nombre,
                      style: NexusTypography.data.copyWith(color: colors.ink),
                    ),
                  ),
                  // **Un icono y no dos palabras**, con la advertencia en su
                  // tooltip. Con «Borrar la prueba» escrito y la frase del aviso
                  // al lado, la fila desbordaba 235 px y el botón se salía de la
                  // hoja: el toque no llegaba a ningún sitio. Lo destapó una
                  // prueba de widget, porque a ojo el botón simplemente no estaba.
                  //
                  // Al pedir confirmación se pone rojo y cambia el tooltip: el
                  // mismo botón dice qué va a hacer sin ocupar una línea.
                  IconButton(
                    onPressed: () => _borrar(prueba),
                    tooltip: _confirmandoBorrado == prueba.ruta
                        ? strings.e2eDeleteTestAsk
                        : strings.e2eDeleteTest,
                    iconSize: 14,
                    splashRadius: 14,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                    color: _confirmandoBorrado == prueba.ruta
                        ? colors.err
                        : colors.faint,
                    icon: const Icon(Icons.delete_outline),
                  ),
                  TextButton(
                    style: _apretado,
                    onPressed: corriendo ? null : () => _lanzar(prueba),
                    child: Text(strings.e2eRun),
                  ),
                ],
              ),
            ),
        ],

        if (_error case final mensaje?) ...[
          const SizedBox(height: NexusSpacing.s2),
          Text(
            mensaje,
            style: NexusTypography.mono.copyWith(color: colors.err),
          ),
        ],
      ],
    );
  }
}

/// Lo que ya corrió, agrupado por proyecto.
///
/// Las que no se pudieron atribuir van en su propio grupo y **no se esconden**:
/// no saber de qué proyecto salió una corrida es un problema nuestro, y taparla
/// se lo pasaría al usuario en forma de historial incompleto.
class _Historial extends ConsumerWidget {
  const _Historial();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final corridas = ref.watch(corridasDePruebaProvider);

    final lista = corridas.value;
    if (lista == null) {
      return Text(
        strings.e2eTitle,
        style: NexusTypography.mono.copyWith(color: colors.faint),
      );
    }
    if (lista.isEmpty) {
      return Text(
        strings.e2eNoRuns,
        style: NexusTypography.mono.copyWith(color: colors.faint),
      );
    }

    final porProyecto = <String, List<CorridaDePrueba>>{};
    for (final corrida in lista) {
      porProyecto
          .putIfAbsent(corrida.proyecto ?? '', () => [])
          .add(corrida);
    }
    // Lo sin atribuir al final: es lo menos útil, no lo primero que se mira.
    final claves = porProyecto.keys.toList()
      ..sort((a, b) => a.isEmpty ? 1 : (b.isEmpty ? -1 : a.compareTo(b)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final clave in claves) ...[
          Padding(
            padding: const EdgeInsets.only(top: NexusSpacing.s4, bottom: 4),
            child: Text(
              clave.isEmpty
                  ? strings.e2eUnattributed
                  : clave.split('/').last,
              style: NexusTypography.label.copyWith(color: colors.faint),
            ),
          ),
          for (final corrida in porProyecto[clave]!)
            _FilaDeCorrida(corrida: corrida),
        ],
      ],
    );
  }
}

class _FilaDeCorrida extends ConsumerWidget {
  const _FilaDeCorrida({required this.corrida});

  final CorridaDePrueba corrida;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;

    final (icono, color, etiqueta) = switch (corrida.comoAcabo) {
      ComoAcabo.bien => (Icons.check, colors.ok, strings.e2ePassed),
      ComoAcabo.mal => (Icons.close, colors.err, strings.e2eFailed),
      ComoAcabo.enMarcha => (
        Icons.autorenew,
        colors.accent,
        strings.e2eRunningNow,
      ),
      ComoAcabo.vayaUstedASaber => (
        Icons.help_outline,
        colors.warn,
        strings.e2eUnknown,
      ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icono, size: 12, color: color),
          const SizedBox(width: NexusSpacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  corrida.flow,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NexusTypography.data.copyWith(color: colors.ink),
                ),
                Text(
                  // Cuándo, cómo acabó y cuántos pasos llegaron: «2 de 8» dice
                  // dónde se rompió sin abrir nada.
                  '${_cuando(corrida.cuando)} · $etiqueta · '
                  '${corrida.pasosBien}/${corrida.pasos}',
                  style: NexusTypography.mono.copyWith(color: colors.faint),
                ),
              ],
            ),
          ),
          // **Ver y borrar.** Ver abre su informe en la misma ventana aparte que
          // usa una corrida en marcha: la de una que ya acabó es la misma cosa
          // quieta, y no había motivo para dos formas de mirar lo mismo.
          TextButton(
            style: _apretado,
            onPressed: () => ref
                .read(e2eDataSourceProvider)
                .abreElInforme(corrida.carpeta),
            child: Text(strings.e2eSee),
          ),
          TextButton(
            style: _apretado,
            onPressed: () async {
              await ref.read(e2eDataSourceProvider).borrar(corrida.carpeta);
              ref.invalidate(corridasDePruebaProvider);
            },
            child: Text(strings.e2eDelete),
          ),
        ],
      ),
    );
  }

  /// La hora si es de hoy, la fecha si no. Un historial de una tarde con la fecha
  /// repetida en cada fila es ruido.
  String _cuando(DateTime cuando) {
    final ahora = DateTime.now();
    final hoy =
        cuando.year == ahora.year &&
        cuando.month == ahora.month &&
        cuando.day == ahora.day;
    final hh = cuando.hour.toString().padLeft(2, '0');
    final mm = cuando.minute.toString().padLeft(2, '0');
    return hoy ? '$hh:$mm' : '${cuando.day}/${cuando.month} $hh:$mm';
  }
}
