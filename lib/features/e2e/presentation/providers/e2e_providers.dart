import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/features/artifacts/presentation/providers/artifacts_providers.dart';
import 'package:nexus/features/e2e/data/datasources/e2e_data_source.dart';
import 'package:nexus/features/e2e/domain/entities/corrida_de_prueba.dart';
import 'package:nexus/features/e2e/domain/usecases/donde_viven_las_corridas.dart';
import 'package:nexus/features/e2e/domain/usecases/la_corrida_como_html.dart';
import 'package:nexus/features/e2e/domain/usecases/las_variables_del_proyecto.dart';
import 'package:nexus/features/e2e/domain/usecases/pasos_de_una_prueba.dart';
import 'package:nexus/features/e2e/domain/usecases/por_que_se_cayo.dart';
import 'package:nexus/core/i18n/language_preference.dart';
import 'package:nexus/features/emulators/presentation/providers/emuladores_providers.dart';
import 'package:nexus/features/e2e/presentation/providers/raiz_de_los_flows_provider.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

final e2eDataSourceProvider = Provider<E2eDataSource>(
  (ref) => const E2eDataSource(),
);

/// Dónde guarda Nexus las corridas.
///
/// **En la carpeta de documentos del usuario, en `test/`.** Antes iban a
/// Application Support, donde nadie las ve; ahí van al lado de lo que escribe
/// Claude y se pueden abrir y borrar sin la app.
///
/// Si todavía no hay carpeta de documentos elegida se cae a la de soporte, por lo
/// mismo que la lista de documentos empieza vacía: **escribir en el disco del
/// usuario en un sitio que él no ha elegido es exactamente lo que no se hace
/// aquí.**
final raizDePruebasProvider = FutureProvider<String>((ref) async {
  final documentos = ref.watch(artifactsFolderProvider);
  if (documentos != null && documentos.isNotEmpty) {
    return '$documentos/${DondeVivenLasCorridas.carpeta}';
  }
  return E2eDataSource.raiz();
});

/// Dónde viven las pruebas de un proyecto.
///
/// Lo que declare su carpeta emparejada, y si no declara nada, la convención de Maestro.
/// **La separación entre proyectos vive aquí**: cada uno apunta a lo suyo, así que no hay
/// un filtro que pueda equivocarse — Nexus lista una carpeta y las demás no existen.
final carpetaDePruebasProvider = Provider.family<String, String>((
  ref,
  proyecto,
) {
  final home = Platform.environment['HOME'] ?? '';
  final raiz = ref.watch(raizDeLosFlowsProvider);
  final emparejadas = ref.watch(workspaceControllerProvider).folders;
  // Por el directorio de trabajo **y** por la ruta emparejada: con una raíz de varios
  // repos, quien pide las pruebas manda el repo elegido y no la raíz.
  for (final carpeta in emparejadas) {
    if (carpeta.workingDirectory == proyecto || carpeta.path == proyecto) {
      return carpeta.pruebasEn(home, raiz: raiz);
    }
  }
  return '$proyecto/.maestro';
});

/// Las pruebas de un proyecto. Familia por carpeta: las de un proyecto son suyas
/// y de ninguno más.
final pruebasProvider = FutureProvider.family<List<Prueba>, String>(
  (ref, proyecto) => ref
      .watch(e2eDataSourceProvider)
      .pruebasDe(ref.watch(carpetaDePruebasProvider(proyecto))),
);

/// Todas las corridas: las que lanzó Nexus y las que no.
///
/// **Las dos fuentes en una sola lista, con su procedencia marcada.** Un panel
/// con dos secciones «las mías» y «las otras» le pasaría al usuario un problema
/// nuestro: a él le da igual quién lanzó, quiere ver qué pasó.
///
/// Sin `autoDispose` y refrescando al abrir, por lo aprendido con los
/// dispositivos: guardar el valor **y** volver a preguntar. Con una sola de las
/// dos cosas se elige entre mentir y parpadear.
final corridasDePruebaProvider = FutureProvider<List<CorridaDePrueba>>((
  ref,
) async {
  final ds = ref.watch(e2eDataSourceProvider);
  final raiz = await ref.watch(raizDePruebasProvider.future);

  // Las pruebas de cada carpeta emparejada, que es lo que permite atribuir las
  // corridas ajenas por nombre de flow.
  final carpetas = ref
      .watch(workspaceControllerProvider)
      .folders
      .map((f) => f.workingDirectory)
      .toSet();
  final pruebasPorProyecto = <String, List<String>>{};
  for (final carpeta in carpetas) {
    final pruebas = await ds.pruebasDe(carpeta);
    if (pruebas.isNotEmpty) {
      pruebasPorProyecto[carpeta] = [for (final p in pruebas) p.nombre];
    }
  }

  final propias = await ds.propias(raiz);
  final ajenas = await ds.ajenas(pruebasPorProyecto);

  // Lo último arriba: lo que acabas de correr es lo que vas a querer mirar.
  return [...propias, ...ajenas]..sort((a, b) => b.cuando.compareTo(a.cuando));
});

/// Si un flow está en git, que es lo que decide si borrarlo se puede deshacer.
///
/// Familia por ruta: se pregunta una vez por archivo y no en cada repintado.
final estaEnGitProvider = FutureProvider.family<bool?, String>(
  (ref, ruta) => ref.watch(e2eDataSourceProvider).estaEnGit(ruta),
);

/// Qué credenciales tiene un proyecto — **los nombres, no los valores**.
///
/// La app necesita saber cuántas hay, cómo se llaman y si el archivo está en git.
/// Nada de eso necesita el valor, así que el valor no entra: se lee en el momento
/// de lanzar y se va con el proceso. Un secreto que no está en el estado de la app
/// no puede acabar en un volcado, en un mensaje de error ni en una captura.
final credencialesProvider =
    FutureProvider.family<({Set<String> claves, bool? enGit}), String>((
      ref,
      proyecto,
    ) async {
      final ds = ref.watch(e2eDataSourceProvider);
      final claves = ds
          .variablesDe(
            proyecto,
            carpetaDePruebas: ref.watch(carpetaDePruebasProvider(proyecto)),
          )
          .keys
          .toSet();
      // **Si está en git, hay que decirlo.** Un archivo de credenciales dentro de un
      // repositorio es una fuga, y en un repo compartido lo es para todo el equipo.
      final enGit = claves.isEmpty
          ? null
          : await ds.estaEnGit('$proyecto/${LasVariablesDelProyecto.archivo}');
      return (claves: claves, enGit: enGit);
    });

/// Lo que ocupan las corridas de cada proyecto.
///
/// **En un proveedor y no en el widget** porque medirlo recorre el disco, y
/// hacerlo dentro de un `build` era volver a recorrerlo en cada repintado.
final tamanoPorProyectoProvider = FutureProvider<Map<String, int>>((ref) async {
  final ds = ref.watch(e2eDataSourceProvider);
  final corridas = await ref.watch(corridasDePruebaProvider.future);

  final total = <String, int>{};
  for (final corrida in corridas) {
    final clave = corrida.proyecto ?? '';
    total[clave] = (total[clave] ?? 0) + ds.bytesDe(corrida.carpeta);
  }
  return total;
});

/// Sobre qué se puede correr: **lo encendido y nada más**.
///
/// Un `maestro test --device` contra un emulador apagado falla, así que ofrecerlo
/// sería ofrecer ese fallo.
///
/// **Vive en un proveedor y no dentro del panel** porque hay dos sitios que
/// lanzan: la lista de pruebas del proyecto y el historial, cuando se repite una
/// corrida. Con la lista de dispositivos calculada en cada uno, lo que pasa a
/// continuación está escrito: uno de los dos se queda sin un criterio que el otro
/// sí tiene, y nadie se entera hasta que falla en el sitio raro.
final dondeCorrerProvider = Provider<List<({String id, String nombre})>>((ref) {
  return [
    for (final e in ref.watch(emuladoresProvider).value?.emuladores ?? const [])
      if (e.corriendo && e.deviceId != null)
        (id: e.deviceId!, nombre: e.nombre),
    for (final d in ref.watch(dispositivosProvider).value ?? const [])
      (id: d.id, nombre: d.nombre),
  ];
});

/// Si todavía se están buscando.
///
/// **No es lo mismo que no haya ninguno**, y [dondeCorrerProvider] no puede
/// distinguirlo: devuelve una lista, y una lista vacía dice «no hay». Colapsar las
/// dos cosas se veía así al abrir el panel, con un emulador encendido: salía el
/// botón de arrancar uno, no salía el selector de dónde correr, y si tocabas Correr
/// en ese medio segundo se te contestaba que hacía falta un dispositivo encendido.
/// Las tres cosas falsas, y las tres por no tener este booleano.
final buscandoDispositivosProvider = Provider<bool>(
  (ref) =>
      !ref.watch(emuladoresProvider).hasValue ||
      !ref.watch(dispositivosProvider).hasValue,
);

/// El que eligió el usuario, si eligió.
class DispositivoElegido extends Notifier<String?> {
  @override
  String? build() => null;

  void elige(String? id) => state = id;
}

final dispositivoElegidoProvider =
    NotifierProvider<DispositivoElegido, String?>(DispositivoElegido.new);

/// El que se va a usar de verdad: el elegido, o el único que haya.
///
/// **Con uno solo no se pregunta**, que sería una pregunta con una sola
/// respuesta; con dos, elegir hace falta de verdad y coger el primero sería
/// decidir por el usuario en silencio.
///
/// Y el elegido se comprueba contra lo que hay ahora: un emulador que se apagó
/// sigue guardado en el estado y lanzar ahí es un fallo con el aviso puesto.
final elDispositivoProvider = Provider<String?>((ref) {
  final hay = [for (final d in ref.watch(dondeCorrerProvider)) d.id];
  final elegido = ref.watch(dispositivoElegidoProvider);
  if (elegido != null && hay.contains(elegido)) return elegido;
  return hay.length == 1 ? hay.single : null;
});

/// Una prueba corriendo ahora mismo.
class PruebaEnMarcha {
  const PruebaEnMarcha({
    required this.flow,
    required this.delFlow,
    this.salida = '',
    this.ruido = const [],
    this.viva = true,
    this.salioMal = false,
    this.error,
  });

  final String flow;

  /// Los pasos del `.yaml`. **Solo para saber lo que falta** y para estimar el
  /// total: lo que de verdad se ejecutó lo dice [salida].
  final List<PasoDelFlow> delFlow;

  /// La salida de Maestro **tal cual, sin trocear**.
  ///
  /// Se guarda el texto entero y se vuelve a leer en cada trozo. No es pereza: el
  /// anuncio de un paso llega **sin salto de línea** y su resultado viene pegado al
  /// anuncio del siguiente, así que procesar trozo a trozo pedía un estado
  /// incremental que se desincroniza. Releer es idempotente.
  final String salida;

  /// El `stderr`, aparte. Ahí sale lo del driver cuando no se puede instalar, y
  /// **no puede entrar en el parseo de pasos**: una línea suya que acabara en tres
  /// puntos se pintaría como un paso que nunca existió.
  final List<String> ruido;

  final bool viva;

  /// Que el proceso **salió con código distinto de cero**. Va aparte y no se
  /// deduce de la salida: Maestro puede fallar sin que ningún paso lo diga —y al
  /// revés, sale con 0 cuando la app no está instalada—, así que las dos señales
  /// son necesarias y ninguna sustituye a la otra.
  final bool salioMal;

  final String? error;

  /// Lo que se pinta: lo ejecutado en prosa, lo que falta como está escrito.
  List<PasoParaPintar> get pasos =>
      PasosDeUnaPrueba.paraPintar(salida: salida, delFlow: delFlow);

  int get terminados => pasos
      .where(
        (p) =>
            p.estado == EstadoDePaso.hecho || p.estado == EstadoDePaso.fallado,
      )
      .length;

  /// Si esto acabó mal, por cualquiera de las dos vías.
  bool get fallo =>
      salioMal || pasos.any((p) => p.estado == EstadoDePaso.fallado);

  /// Las líneas para el panel de salida cruda: lo de Maestro y lo del driver.
  List<String> get lineas => [
    for (final l in salida.split('\n'))
      if (l.trim().isNotEmpty) l.trimRight(),
    ...ruido,
  ];
}

/// Lanzar una prueba y seguirla.
///
/// **Una a la vez**, y no por simplificar: dos corridas de Maestro sobre el mismo
/// dispositivo se pelean por su driver, y sobre dispositivos distintos ya está
/// bien pero nadie lo ha pedido. Cuando haga falta, esto pasa a ser un mapa como
/// el de las corridas de la app.
class PruebaEnMarchaController extends Notifier<PruebaEnMarcha?> {
  Process? _proceso;

  /// Si la ventana de esta corrida ya está abierta.
  var _ventanaAbierta = false;

  /// Las capturas que dejó, ya embebidas, **y solo cuando ha terminado**.
  ///
  /// Embebidas pesan: una pantalla de móvil son unos 90 kB de PNG y en base64
  /// crece un tercio. La página se reescribe en cada trozo de salida —decenas de
  /// veces por corrida— y meterlas ahí sería escribir eso decenas de veces para
  /// enseñar una imagen que solo se mira al acabar.
  Map<String, String> _capturas = const {};

  /// Con qué se lanzó, para poder anotarlo al terminar.
  ({
    String raiz,
    String perfil,
    String proyecto,
    String dispositivo,
    DateTime cuando,
  })?
  _contexto;

  /// Dónde dejó Maestro los artefactos, para poder guardarlo en el registro y que
  /// el informe de mañana encuentre las mismas capturas.
  String? _artefactos;

  @override
  PruebaEnMarcha? build() {
    // **El botón de detener de la ventana llega por aquí.** La página es estática
    // y su botón un enlace `nexus://parar`; el visor lo intercepta y lo reenvía a
    // este canal. Se escucha una sola vez, al construirse el controlador.
    _visor.setMethodCallHandler((llamada) async {
      if (llamada.method != 'desdeLaPagina') return null;
      final que = (llamada.arguments as Map?)?['que'];
      if (que == 'parar') parar();
      return null;
    });
    return null;
  }

  /// El mismo canal del visor: es su ventana la que habla.
  static const _visor = MethodChannel('com.katanalabs.nexus/artifacts');

  /// Lanza [prueba] en [deviceId]. `null` si arrancó.
  Future<String?> lanzar({
    required Prueba prueba,
    required String proyecto,
    required String deviceId,
    required String perfil,
  }) async {
    if (state?.viva ?? false) return 'Ya hay una prueba corriendo';

    final raiz = await ref.read(raizDePruebasProvider.future);
    // Maestro escribe su propio ruido en `.maestro/tests` dentro de esta carpeta,
    // que empieza por punto y no estorba a lo que sí se mira.
    final salida = DondeVivenLasCorridas.de(raiz: raiz, proyecto: proyecto);

    // El YAML se lee ahora: es lo que se pinta, y leerlo después sería pintar los
    // pasos de una versión que igual ya cambió.
    final yaml = await _leer(prueba.ruta);
    _ventanaAbierta = false;
    _capturas = const {};
    _contexto = (
      raiz: raiz,
      perfil: perfil,
      proyecto: proyecto,
      dispositivo: deviceId,
      cuando: DateTime.now(),
    );
    state = PruebaEnMarcha(
      flow: prueba.nombre,
      delFlow: PasosDeUnaPrueba.leer(yaml),
    );
    await _pinta();

    // Las credenciales se leen aquí, en el último momento, y solo las que este
    // flow nombra. No pasan por el estado de la app ni por el prompt.
    final ds = ref.read(e2eDataSourceProvider);
    final proceso = await ds.lanzar(
      flow: prueba.ruta,
      proyecto: proyecto,
      deviceId: deviceId,
      salida: salida,
      variables: LasVariablesDelProyecto.paraElFlow(
        yaml: yaml,
        variables: ds.variablesDe(
          proyecto,
          carpetaDePruebas: ref.read(carpetaDePruebasProvider(proyecto)),
        ),
      ),
    );
    if (proceso == null) {
      state = null;
      return 'No se encontró Maestro, o no se pudo lanzar';
    }
    _proceso = proceso;

    // **Se acumula tal cual y no se espera un salto de línea.** Aquí estaba el
    // fallo: Maestro anuncia el paso al empezarlo y lo hace **sin `\n`** —medido,
    // quince segundos antes de su resultado—, así que un lector que corte por
    // líneas se guarda ese anuncio en el buffer y solo lo ve cuando el paso ya
    // terminó. El paso en curso no se podía enseñar porque no se estaba leyendo.
    proceso.stdout.transform(utf8.decoder).listen(_masSalida);
    // `stderr` aparte: ahí sale lo del driver cuando no se puede instalar, y
    // mezclarlo rompería el parseo de pasos —una línea suya que acabe en tres
    // puntos se pintaría como un paso que nunca existió—.
    proceso.stderr.transform(utf8.decoder).listen(_masRuido);

    unawaited(
      proceso.exitCode.then((codigo) {
        _proceso = null;
        final actual = state;
        if (actual == null) return;
        state = PruebaEnMarcha(
          flow: actual.flow,
          delFlow: actual.delFlow,
          salida: actual.salida,
          ruido: actual.ruido,
          viva: false,
          salioMal: codigo != 0,
        );
        // Las capturas, ahora que la corrida acabó y existen en disco.
        final ds = ref.read(e2eDataSourceProvider);
        _artefactos = ds.carpetaDeArtefactos(salida: salida, flow: actual.flow);
        _capturas = ds.capturasDe(_artefactos);

        unawaited(_pinta());
        unawaited(_dejaConstancia());
      }),
    );
    return null;
  }

  /// Cortar una prueba a medias.
  void parar() {
    _proceso?.kill();
    _proceso = null;
  }

  /// Más salida de Maestro. Se pega al final y se repinta.
  void _masSalida(String trozo) {
    final actual = state;
    if (actual == null || trozo.isEmpty) return;

    state = PruebaEnMarcha(
      flow: actual.flow,
      delFlow: actual.delFlow,
      salida: actual.salida + trozo,
      ruido: actual.ruido,
      salioMal: actual.salioMal,
    );
    unawaited(_pinta());
  }

  /// Más `stderr`. Va a su lista, no a la salida que se parsea.
  void _masRuido(String trozo) {
    final actual = state;
    if (actual == null) return;
    final limpio = trozo.trimRight();
    if (limpio.isEmpty) return;

    state = PruebaEnMarcha(
      flow: actual.flow,
      delFlow: actual.delFlow,
      salida: actual.salida,
      ruido: [...actual.ruido, limpio],
      salioMal: actual.salioMal,
    );
    unawaited(_pinta());
  }

  /// Reescribe la página de la corrida. La ventana se recarga sola al verla
  /// cambiar, así que esto es todo lo que hace falta para que siga en vivo.
  Future<void> _pinta() async {
    final actual = state;
    if (actual == null) return;

    await ref
        .read(e2eDataSourceProvider)
        .pintaLaCorrida(
          flow: actual.flow,
          html: LaCorridaComoHtml.escribe(
            flow: actual.flow,
            pasos: actual.pasos,
            lineas: actual.lineas,
            terminados: actual.terminados,
            total: actual.delFlow.length,
            viva: actual.viva,
            fallo: actual.fallo,
            capturas: _capturas,
            // **El motivo, traducido.** El resto de la página está en español a
            // pelo —deuda que viene de antes— pero esto no se suma a ella: el
            // controlador sí puede leer `stringsProvider`, así que se lee.
            diagnostico: _diagnostico(actual),
          ),
          primeraVez: !_ventanaAbierta,
          raizDeLaVentana:
              _contexto?.raiz ?? await ref.read(raizDePruebasProvider.future),
        );
    _ventanaAbierta = true;
  }

  /// Deja constancia de lo que pasó, y refresca el historial.
  ///
  /// Se anota lo que Nexus leyó de la salida y no lo que escriba Maestro: su
  /// carpeta del flow no siempre llega —medido— y sin esto una corrida que pasó
  /// entera desaparecía del historial.
  Future<void> _dejaConstancia() async {
    final actual = state;
    final ctx = _contexto;
    if (actual == null || ctx == null) return;

    await ref
        .read(e2eDataSourceProvider)
        .anotaLaCorrida(
          raiz: ctx.raiz,
          perfil: ctx.perfil,
          proyecto: ctx.proyecto,
          corrida: {
            'flow': actual.flow,
            'cuando': ctx.cuando.toIso8601String(),
            // El total estimado del archivo, para el denominador del informe.
            'pasos': actual.delFlow.length,
            'terminados': actual.terminados,
            'fallo': actual.fallo,
            'dispositivo': ctx.dispositivo,
            // **La salida entera y no una lista de pasos.** De ella salen los
            // pasos con su frase y su estado, igual que en vivo, así que el
            // informe guardado y la vista en marcha leen exactamente lo mismo.
            // Antes se guardaban los pasos del YAML ya masticados, y eso
            // significaba que el informe podía enseñar algo distinto de lo que se
            // vio correr.
            'salida': _acotada(actual.salida),
            'artefactos': _artefactos,
            'ruido': actual.ruido.length > 50
                ? actual.ruido.sublist(actual.ruido.length - 50)
                : actual.ruido,
          },
        );
    ref.invalidate(corridasDePruebaProvider);
  }

  /// Qué frase explica este fallo, si es de los reconocibles.
  ///
  /// Solo cuando la corrida **ya acabó y acabó mal**: en marcha no hay nada que
  /// explicar todavía, y en una que va bien el texto sería ruido rojo.
  String? _diagnostico(PruebaEnMarcha prueba) {
    if (prueba.viva || !prueba.fallo) return null;

    final strings = ref.read(stringsProvider);
    return switch (PorQueSeCayoLaCorrida.de(
      [prueba.salida, ...prueba.ruido].join('\n'),
    )) {
      PorQueSeCayo.driverNoSeInstala => strings.e2eDriverBlocked,
      PorQueSeCayo.sinPermisoParaTocar => strings.e2eNoTapPermission,
      PorQueSeCayo.appNoInstalada => strings.e2eAppMissing,
      null => null,
    };
  }

  /// Volver a traer la ventana al frente, para el botón «Ver».
  Future<void> traeLaVentana() async {
    _ventanaAbierta = false;
    await _pinta();
  }

  /// La salida, acotada por la cola: lo que se lee cuando algo falla es el final.
  ///
  /// Se corta en el primer salto de línea después del recorte para no dejar media
  /// línea al principio, que el parseo leería como un paso con el nombre partido.
  static String _acotada(String salida, {int tope = 40000}) {
    if (salida.length <= tope) return salida;
    final cola = salida.substring(salida.length - tope);
    final corte = cola.indexOf('\n');
    return corte < 0 ? cola : cola.substring(corte + 1);
  }

  Future<String> _leer(String ruta) async {
    try {
      return await File(ruta).readAsString();
    } on FileSystemException {
      return '';
    }
  }
}

final pruebaEnMarchaProvider =
    NotifierProvider<PruebaEnMarchaController, PruebaEnMarcha?>(
      PruebaEnMarchaController.new,
    );
