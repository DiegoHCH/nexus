import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/design_system/selector_compacto.dart';
import 'package:nexus/core/i18n/nexus_strings.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/e2e/domain/entities/corrida_de_prueba.dart';
import 'package:nexus/features/e2e/domain/usecases/las_variables_del_proyecto.dart';
import 'package:nexus/features/e2e/domain/usecases/pasos_de_una_prueba.dart';
import 'package:nexus/features/e2e/domain/usecases/por_que_se_cayo.dart';
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

/// Lo que falta para poder correr, o `null` si no falta nada.
///
/// **Fuera de los dos widgets a propósito.** Hay dos sitios que lanzan —la lista
/// del proyecto y el historial, al repetir una corrida— y estas comprobaciones son
/// las que convierten un fallo confuso en una frase: sin dispositivo encendido
/// `--device` falla, y sin la app instalada Maestro falla en el primer `launchApp`
/// **saliendo con código 0**, un fallo disfrazado de éxito. Copiarlas en cada sitio
/// era dejar a uno de los dos sin el aviso, y sin enterarse hasta que fallara ahí.
/// Dónde correr, **esperando a que la búsqueda acabe**.
///
/// Leer el elegido sin esperar es lo que hacía que tocar Correr recién abierto el
/// panel contestara «hace falta un dispositivo encendido» teniendo uno. La búsqueda
/// tarda un instante —`flutter emulators` y `adb devices` son procesos— y en ese
/// instante la respuesta correcta es esperar, no negar.
Future<String?> _dondeCorrer(WidgetRef ref) async {
  try {
    await ref.read(emuladoresProvider.future);
    await ref.read(dispositivosProvider.future);
  } on Object {
    // Si una de las dos vías falla, se sigue: puede haber dispositivo por la otra.
  }
  return ref.read(elDispositivoProvider);
}

Future<String?> _loQueFaltaParaCorrer(
  WidgetRef ref,
  NexusStrings strings, {
  required Prueba prueba,
  required String proyecto,
  required String? donde,
}) async {
  if (ref.read(dondeCorrerProvider).isEmpty) return strings.e2eNoDevice;
  if (donde == null) return strings.e2eDevice;

  final yaml = await File(prueba.ruta).readAsString().catchError((_) => '');

  // **Una variable que falta se dice aquí.** Si no, Maestro escribe el literal
  // `\${G66_EMAIL}` en el campo del correo y la prueba muere tres pasos después, en
  // un sitio que no tiene nada que ver con la causa. Solo los nombres: un mensaje
  // de error no es sitio para un valor.
  final credenciales = await ref.read(credencialesProvider(proyecto).future);
  final faltan = LasVariablesDelProyecto.faltan(
    yaml: yaml,
    tiene: credenciales.claves,
  );
  if (faltan.isNotEmpty) return strings.e2eMissingVars(faltan.join(', '));

  // Solo se para cuando se sabe que **no** está: `null` es «no se pudo
  // comprobar» —un iPhone, sin adb— y ahí no se bloquea nada. Negarse por no
  // saber sería peor que dejar fallar a Maestro.
  if (PasosDeUnaPrueba.appIdDe(yaml) case final appId?) {
    final instalada = await ref
        .read(e2eDataSourceProvider)
        .estaInstalada(deviceId: donde, appId: appId);
    if (instalada == false) return strings.e2eNotInstalled;
  }
  return null;
}

/// El tamaño en algo que se lea.
///
/// Sin decimales por debajo de un mega: antes de borrar, «812 kB» ya dice todo lo
/// que hay que saber y «812,4 kB» no añade nada.
String _tamano(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} kB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Elegir una prueba de este proyecto y lanzarla.
class _Lanzadera extends ConsumerStatefulWidget {
  const _Lanzadera({required this.proyecto});

  final String proyecto;

  @override
  ConsumerState<_Lanzadera> createState() => _LanzaderaState();
}

class _LanzaderaState extends ConsumerState<_Lanzadera> {
  String? _error;
  String? _confirmandoBorrado;
  var _arrancando = false;

  /// Los dispositivos y el elegido salen de sus proveedores —ver
  /// [dondeCorrerProvider]—, no de aquí: el historial también lanza, y con esto
  /// calculado en cada sitio los dos criterios se separan en cuanto uno cambie.
  List<({String id, String nombre})> get _dispositivos =>
      ref.watch(dondeCorrerProvider);

  /// **Un id no sirve para elegir**: `36c56d94` y `00008030-000C390C1AC0C02E` no
  /// dicen cuál es el móvil y cuál el iPhone. El nombre sí —«POCO F6», «iPhone
  /// 11»—. El id se enseña detrás, en pequeño: sigue siendo lo que hay que pasarle
  /// a `--device` y a veces hay dos aparatos con el mismo nombre.
  String _comoSeLlama(String id) {
    for (final d in _dispositivos) {
      if (d.id == id) return d.nombre == id ? id : '${d.nombre} · $id';
    }
    return id;
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
    final donde = await _dondeCorrer(ref);
    if (!mounted) return;
    final falta = await _loQueFaltaParaCorrer(
      ref,
      context.strings,
      prueba: prueba,
      proyecto: widget.proyecto,
      donde: donde,
    );
    if (!mounted) return;
    if (falta != null) {
      setState(() => _error = falta);
      return;
    }
    setState(() => _error = null);

    final error = await ref
        .read(pruebaEnMarchaProvider.notifier)
        .lanzar(
          prueba: prueba,
          proyecto: widget.proyecto,
          deviceId: donde!,
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

    // **Se le pregunta a git por todas, y ahora, no al confirmar.** Preguntando en
    // el toque, el primer fotograma enseña «borra el archivo del repo» y el
    // siguiente lo cambia por «se pierde»: un aviso que cambia de promesa después
    // de que lo hayas leído es exactamente lo que un aviso no puede hacer. Es el
    // mismo fallo del parpadeo gris de los emuladores, con otra cara.
    final enGit = {
      for (final p in pruebas) p.ruta: ref.watch(estaEnGitProvider(p.ruta)).value,
    };

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
        // **Cuántas credenciales hay cargadas, sin enseñar ninguna.** Es la
        // diferencia entre saber que el `.env.local` se leyó y suponerlo: si no se
        // dice, un archivo mal puesto se descubre en el fallo de la prueba.
        if (ref.watch(credencialesProvider(widget.proyecto)).value
            case final credenciales?
            when credenciales.claves.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            strings.e2eVarsLoaded(credenciales.claves.length),
            style: NexusTypography.mono.copyWith(color: colors.faint),
          ),
          if (credenciales.enGit == true)
            Text(
              strings.e2eEnvInGit,
              style: NexusTypography.mono.copyWith(color: colors.warn),
            ),
        ],
        const SizedBox(height: NexusSpacing.s2),

        if (pruebas.isEmpty)
          Text(
            strings.e2eNone,
            style: NexusTypography.mono.copyWith(color: colors.faint),
          )
        else ...[
          // **Buscando no es lo mismo que no haber.** Mientras se busca no se
          // ofrece arrancar un emulador: con uno ya encendido, ese botón es una
          // pregunta absurda que además desaparece medio segundo después.
          if (ref.watch(buscandoDispositivosProvider))
            Padding(
              padding: const EdgeInsets.only(bottom: NexusSpacing.s3),
              child: Row(
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
                    strings.e2eSearchingDevices,
                    style: NexusTypography.mono.copyWith(color: colors.faint),
                  ),
                ],
              ),
            )
          // **Sin nada encendido, se ofrece encenderlo** en vez de decir que
          // falta. Es lo único que separa «no puedo correr» de «dame 30 s».
          else if (dispositivos.isEmpty)
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
              valor: ref.watch(elDispositivoProvider),
              opciones: [for (final d in dispositivos) d.id],
              etiqueta: _comoSeLlama,
              pista: strings.e2eDevice,
              onElegir: (v) =>
                  ref.read(dispositivoElegidoProvider.notifier).elige(v),
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
                    // **El aviso lo decide git, no una suposición.** Antes
                    // prometía «se recupera con git» siempre, y con un flow
                    // recién escrito y sin commitear eso es falso justo cuando
                    // más importa.
                    //
                    // Mientras se comprueba, y cuando no se puede saber —sin git,
                    // o fuera de un repositorio—, el aviso no promete nada en
                    // ninguna dirección: los dos casos llegan aquí como `null` y
                    // eso está bien, porque de los dos la respuesta honesta es la
                    // misma.
                    tooltip: _confirmandoBorrado == prueba.ruta
                        ? switch (enGit[prueba.ruta]) {
                            true => strings.e2eDeleteTestAsk,
                            false => strings.e2eDeleteTestAskLost,
                            // Mientras se comprueba, y cuando no se puede saber
                            // —sin git, o fuera de un repositorio—, no se promete
                            // nada en ninguna dirección: de los dos casos la
                            // respuesta honesta es la misma.
                            null => strings.e2eDeleteTestAskPlain,
                          }
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
class _Historial extends ConsumerStatefulWidget {
  const _Historial();

  @override
  ConsumerState<_Historial> createState() => _HistorialState();
}

class _HistorialState extends ConsumerState<_Historial> {
  /// Qué grupo pidió confirmación. Los dos toques de siempre, y aquí importan más
  /// que en una fila: esto se lleva por delante todas las corridas del proyecto.
  String? _confirmando;

  Future<void> _borrarElProyecto(
    String clave,
    List<CorridaDePrueba> corridas,
  ) async {
    if (_confirmando != clave) {
      setState(() => _confirmando = clave);
      return;
    }
    final ds = ref.read(e2eDataSourceProvider);
    for (final corrida in corridas) {
      await ds.borrar(corrida.carpeta);
    }
    ref.invalidate(corridasDePruebaProvider);
    if (!mounted) return;
    setState(() => _confirmando = null);
  }

  @override
  Widget build(BuildContext context) {
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
      porProyecto.putIfAbsent(corrida.proyecto ?? '', () => []).add(corrida);
    }
    // Lo sin atribuir al final: es lo menos útil, no lo primero que se mira.
    final claves = porProyecto.keys.toList()
      ..sort((a, b) => a.isEmpty ? 1 : (b.isEmpty ? -1 : a.compareTo(b)));

    // Los tamaños se miden en un proveedor y no aquí: `bytesDe` recorre el disco,
    // y hacerlo dentro de `build` era leerlo entero en cada repintado.
    final tamanos = ref.watch(tamanoPorProyectoProvider).value ?? const {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final clave in claves) ...[
          Padding(
            padding: const EdgeInsets.only(top: NexusSpacing.s4, bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    clave.isEmpty
                        ? strings.e2eUnattributed
                        : clave.split('/').last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NexusTypography.label.copyWith(color: colors.faint),
                  ),
                ),
                // **Cuántas y cuánto ocupan**, que es lo que hace falta para
                // decidir si borrarlas. Un grupo de 40 corridas con capturas son
                // decenas de megas y nada lo decía.
                Text(
                  strings.e2eRunsSize(
                    porProyecto[clave]!.length,
                    _tamano(tamanos[clave] ?? 0),
                  ),
                  style: NexusTypography.mono.copyWith(color: colors.faint),
                ),
                IconButton(
                  onPressed: () =>
                      _borrarElProyecto(clave, porProyecto[clave]!),
                  tooltip: _confirmando == clave
                      ? strings.e2eDeleteProjectAsk
                      : strings.e2eDeleteProject,
                  iconSize: 14,
                  splashRadius: 14,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                  color: _confirmando == clave ? colors.err : colors.faint,
                  icon: const Icon(Icons.delete_sweep_outlined),
                ),
              ],
            ),
          ),
          for (final corrida in porProyecto[clave]!)
            _FilaDeCorrida(corrida: corrida),
        ],
      ],
    );
  }
}

class _FilaDeCorrida extends ConsumerStatefulWidget {
  const _FilaDeCorrida({required this.corrida});

  final CorridaDePrueba corrida;

  @override
  ConsumerState<_FilaDeCorrida> createState() => _FilaDeCorridaState();
}

class _FilaDeCorridaState extends ConsumerState<_FilaDeCorrida> {
  String? _error;
  var _repitiendo = false;

  /// Vuelve a correr esa prueba, y si se puede en el mismo sitio.
  Future<void> _repetir() async {
    final corrida = widget.corrida;
    final proyecto = corrida.proyecto;
    if (proyecto == null) return;
    final strings = context.strings;

    setState(() {
      _repitiendo = true;
      _error = null;
    });

    // **La prueba se busca en el repo, no se recompone su ruta.** Un flow puede
    // ser `.yaml` o `.yml`, y sobre todo **puede no estar ya**: repetir una
    // corrida de la semana pasada con el flow borrado tiene que decirlo aquí y no
    // fallar dentro de Maestro con un «file not found».
    final pruebas = await ref.read(pruebasProvider(proyecto).future);
    Prueba? prueba;
    for (final p in pruebas) {
      if (p.nombre == corrida.flow) {
        prueba = p;
        break;
      }
    }
    if (!mounted) return;
    if (prueba == null) {
      setState(() {
        _repitiendo = false;
        _error = strings.e2eFlowGone;
      });
      return;
    }

    // **El mismo dispositivo, pero solo si sigue encendido.** Un `emulator-5554`
    // de hace tres días no es el mismo emulador, así que se comprueba contra lo
    // que hay ahora en vez de pasárselo a Maestro y esperar a que falle.
    final elegido = await _dondeCorrer(ref);
    if (!mounted) return;
    final hay = {for (final d in ref.read(dondeCorrerProvider)) d.id};
    final donde = hay.contains(corrida.dispositivo)
        ? corrida.dispositivo
        : elegido;

    final falta = await _loQueFaltaParaCorrer(
      ref,
      strings,
      prueba: prueba,
      proyecto: proyecto,
      donde: donde,
    );
    if (!mounted) return;
    if (falta != null) {
      setState(() {
        _repitiendo = false;
        _error = falta;
      });
      return;
    }

    final error = await ref
        .read(pruebaEnMarchaProvider.notifier)
        .lanzar(
          prueba: prueba,
          proyecto: proyecto,
          deviceId: donde!,
          perfil: corrida.perfil ?? 'local',
        );
    if (!mounted) return;
    setState(() {
      _repitiendo = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;
    final corrida = widget.corrida;
    final corriendo = ref.watch(pruebaEnMarchaProvider)?.viva ?? false;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
              // **Repetir solo donde se puede.** Sin proyecto atribuido no se sabe
              // en qué repo vive el flow, y ofrecer un botón que solo puede
              // contestar «no sé de dónde salió esto» es peor que no ofrecerlo.
              //
              // Un icono y no una palabra: con «Ver» y «Borrar» escritos, una
              // tercera palabra en esta fila es exactamente cómo desbordó antes.
              if (corrida.atribuida)
                _repitiendo
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: colors.accent,
                          ),
                        ),
                      )
                    : IconButton(
                        onPressed: corriendo ? null : _repetir,
                        tooltip: strings.e2eRepeat,
                        iconSize: 14,
                        splashRadius: 14,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        constraints: const BoxConstraints(),
                        visualDensity: VisualDensity.compact,
                        color: colors.faint,
                        icon: const Icon(Icons.replay),
                      ),
              // **Ver y borrar.** Ver abre su informe en la misma ventana aparte
              // que usa una corrida en marcha: la de una que ya acabó es la misma
              // cosa quieta, y no había motivo para dos formas de mirar lo mismo.
              TextButton(
                style: _apretado,
                onPressed: () => ref
                    .read(e2eDataSourceProvider)
                    .abreElInforme(
                      corrida.carpeta,
                      explica: (por) => switch (por) {
                        PorQueSeCayo.driverNoSeInstala =>
                          strings.e2eDriverBlocked,
                        PorQueSeCayo.sinPermisoParaTocar =>
                          strings.e2eNoTapPermission,
                        PorQueSeCayo.appNoInstalada => strings.e2eAppMissing,
                      },
                    ),
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
          if (_error case final mensaje?)
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 2),
              child: Text(
                mensaje,
                style: NexusTypography.mono.copyWith(color: colors.err),
              ),
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
