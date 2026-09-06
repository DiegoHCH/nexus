import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/design_system/selector_compacto.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/emulators/domain/entities/emulador.dart';
import 'package:nexus/features/emulators/presentation/providers/emuladores_providers.dart';
import 'package:nexus/features/run/domain/entities/config_de_arranque.dart';
import 'package:nexus/features/run/domain/entities/corrida.dart';
import 'package:nexus/features/run/domain/usecases/lector_de_configs.dart';
import 'package:nexus/features/run/presentation/providers/corridas_providers.dart';
import 'package:nexus/features/run/presentation/providers/la_ventana_del_registro.dart';
import 'package:nexus/features/run/presentation/providers/run_providers.dart';

/// Correr la app: elegir entorno y dispositivo, y gobernarla.
///
/// **En el compositor y no en Ajustes**, por lo mismo que los dispositivos: una
/// app corriendo es estado vivo, no configuración. Y aquí es donde se mira
/// mientras se trabaja.
///
/// El icono cambia de significado según lo que haya: sin nada corriendo es
/// «correr», y con algo corriendo es «esto está pasando» — con su punto, como el
/// de los dispositivos.
class CorrerMenu extends ConsumerWidget {
  const CorrerMenu({super.key, required this.proyecto});

  /// La carpeta de trabajo de esta conversación. `null` si no hay proyecto.
  ///
  /// Las configuraciones son **de este proyecto**: van por aquí y no por una
  /// lista global, porque la de un repo no significa nada en otro.
  final String? proyecto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final corridas = ref.watch(corridasProvider);
    final mia = proyecto == null
        ? <Corrida>[]
        : corridas.values.where((c) => c.proyecto == proyecto).toList();

    return PopupMenuButton<void>(
      color: colors.deep,
      tooltip: '',
      // **Sin esto el panel no puede pasar de 280 px.** Es el
      // `_kMenuMaxWidth` de Material —cinco pasos de 56— y recorta en silencio
      // lo que se le pida: un `SizedBox` de 620 se quedaba en 280 y salía un
      // desplegable con «Global66…» y otro con «E». Y explica los desbordes de 9
      // y 71 px de antes: eran contra 280, no contra el ancho que yo creía.
      constraints: const BoxConstraints(minWidth: 620, maxWidth: 620),
      onOpened: () {
        if (proyecto case final p?) ref.invalidate(configsProvider(p));
        ref.invalidate(emuladoresProvider);
        ref.invalidate(dispositivosProvider);
      },
      itemBuilder: (context) => [
        PopupMenuItem<void>(
          enabled: false,
          // Relleno propio en vez del de fábrica: el del `PopupMenuItem` son 16
          // a cada lado que no se descuentan del ancho que se le pide, y el panel
          // desbordaba por menos de un píxel — suficiente para pintar la franja
          // amarilla de aviso encima de la barra.
          padding: const EdgeInsets.symmetric(
            horizontal: NexusSpacing.s3,
            vertical: NexusSpacing.s2,
          ),
          child: SizedBox(
            // **Ancho y bajo, no cuadrado.** Con 380 los dos desplegables y el
            // botón se apilaban y el panel salía casi cuadrado, que en una barra
            // de compositor se ve como una caja pegada encima. A 620 caben en una
            // sola línea y el panel se lee como lo que es: una barra.
            width: 620,
            child: _Panel(proyecto: proyecto),
          ),
        ),
      ],
      child: Semantics(
        label: strings.runTitle,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.play_arrow_rounded,
                size: 17,
                color: mia.isEmpty ? colors.faint : colors.accent,
              ),
            ),
            if (mia.isNotEmpty)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.void_, width: 1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Panel extends ConsumerStatefulWidget {
  const _Panel({required this.proyecto});

  final String? proyecto;

  @override
  ConsumerState<_Panel> createState() => _PanelState();
}

class _PanelState extends ConsumerState<_Panel> {
  String? _config;
  String? _dispositivo;
  var _ocupado = false;
  String? _error;

  Future<void> _correr() async {
    final proyecto = widget.proyecto;
    final configs = ref.read(configsProvider(proyecto ?? '')).value ?? const [];
    final nombre = _elegida(configs);
    final deviceId = _dispositivo;
    if (proyecto == null || nombre == null || deviceId == null) return;

    final elegida = configs.where((c) => c.nombre == nombre).firstOrNull;
    if (elegida == null) return;

    final (:dispositivo, :plataforma) = _datosDelDispositivo(deviceId);
    if (plataforma == null) return;

    setState(() {
      _ocupado = true;
      _error = null;
    });
    final error = await ref
        .read(corridasProvider.notifier)
        .correr(
          proyecto: proyecto,
          configuracion: nombre,
          args: LectorDeConfigs.argumentos(elegida, proyecto: proyecto),
          deviceId: deviceId,
          dispositivo: dispositivo,
          plataforma: plataforma,
        );
    if (!mounted) return;
    setState(() {
      _ocupado = false;
      _error = error;
    });
  }

  /// De dónde sale el nombre y la plataforma de un dispositivo elegido.
  ///
  /// De las dos listas que ya existen: los emuladores arrancados y los teléfonos
  /// enchufados. No hay una tercera fuente porque no debe haberla — sería otra
  /// verdad que mantener.
  ({String dispositivo, PlataformaEmulador? plataforma}) _datosDelDispositivo(
    String deviceId,
  ) {
    for (final e
        in ref.read(emuladoresProvider).value?.emuladores ?? const []) {
      if (e.deviceId == deviceId) {
        return (dispositivo: e.nombre, plataforma: e.plataforma);
      }
    }
    for (final d in ref.read(dispositivosProvider).value ?? const []) {
      if (d.id == deviceId) {
        return (dispositivo: d.nombre, plataforma: d.plataforma);
      }
    }
    return (dispositivo: deviceId, plataforma: null);
  }

  /// Cuál va puesta: lo elegido en esta sesión, o lo recordado de este proyecto.
  String? _elegida(List<ConfigDeArranque> configs) {
    final nombres = {for (final c in configs) c.nombre};
    if (_config case final elegido? when nombres.contains(elegido)) {
      return elegido;
    }
    final recordado = ref.watch(
      configsPorDefectoProvider,
    )[widget.proyecto ?? ''];
    return recordado != null && nombres.contains(recordado) ? recordado : null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;
    final proyecto = widget.proyecto;

    if (proyecto == null) {
      return Text(
        strings.runNoProject,
        style: NexusTypography.mono.copyWith(color: colors.faint),
      );
    }

    final configs = ref.watch(configsProvider(proyecto)).value ?? const [];
    final dispositivos = _losDispositivos();
    final corridas = ref
        .watch(corridasProvider)
        .values
        .where((c) => c.proyecto == proyecto)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                strings.runTitle,
                style: NexusTypography.label.copyWith(color: colors.faint),
              ),
            ),
            // **Apagado de fábrica.** Recargar la app sin que nadie lo pida es
            // una sorpresa la primera vez, y aquí no se enciende por defecto lo
            // que reinicia algo.
            _BotonMini(
              icono: Icons.bolt,
              titulo: strings.runAuto,
              activo: ref.watch(autoRecargaProvider),
              onPulsar: () => ref.read(autoRecargaProvider.notifier).cambiar(),
            ),
          ],
        ),
        const SizedBox(height: NexusSpacing.s3),

        for (final corrida in corridas) _FilaDeCorrida(corrida: corrida),
        if (corridas.isNotEmpty) const SizedBox(height: NexusSpacing.s4),

        if (configs.isEmpty)
          Text(
            strings.runNoConfigs,
            style: NexusTypography.mono.copyWith(color: colors.faint),
          )
        else ...[
          // Los dos desplegables y el botón **en una línea**. Apilados hacían
          // del panel un cuadrado; en fila se lee como una barra, que es lo que
          // es. El de la configuración pesa el doble porque sus nombres son
          // largos —«Global66 (ci + mock PayIn Colombia)»— y el del dispositivo
          // cabe en un identificador.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 2,
                child: SelectorCompacto(
                  // **La recordada, si sigue existiendo.** Se guarda el nombre y
                  // no un índice: los índices bailan al añadir una configuración
                  // al `launch.json`, y ese día estarías corriendo otro entorno
                  // sin enterarte. Si el nombre ya no está, no se ofrece.
                  valor: _elegida(configs),
                  opciones: [for (final c in configs) c.nombre],
                  pista: strings.runTitle,
                  onElegir: (v) {
                    setState(() => _config = v);
                    ref
                        .read(configsPorDefectoProvider.notifier)
                        .elegir(proyecto, v);
                  },
                ),
              ),
              const SizedBox(width: NexusSpacing.s2),
              Expanded(
                child: SelectorCompacto(
                  valor: _dispositivo,
                  opciones: dispositivos.ids,
                  // El nombre delante y el id detrás, por lo mismo que en el
                  // panel de pruebas: un id no dice cuál es cuál.
                  etiqueta: _comoSeLlama,
                  // Tres estados donde había uno: buscando, ninguno, y elige.
                  pista: dispositivos.buscando
                      ? strings.runSearchingDevices
                      : dispositivos.ids.isEmpty
                      ? strings.runNoDevices
                      : strings.runChooseDevice,
                  cargando: dispositivos.buscando,
                  onElegir: (v) => setState(() => _dispositivo = v),
                ),
              ),
              const SizedBox(width: NexusSpacing.s3),
              if (_ocupado)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: colors.accent,
                  ),
                )
              else
                OutlinedButton(
                  onPressed: _elegida(configs) != null && _dispositivo != null
                      ? _correr
                      : null,
                  child: Text(strings.runStart),
                ),
            ],
          ),
        ],

        if (_error case final mensaje?) ...[
          const SizedBox(height: NexusSpacing.s3),
          Text(
            mensaje,
            style: NexusTypography.mono.copyWith(color: colors.err),
          ),
        ],
      ],
    );
  }

  /// Cómo se llama un dispositivo, para poder elegirlo.
  ///
  /// El nombre sale de las mismas dos listas que dan los ids, así que no hay una
  /// tercera fuente que pueda contradecirlas.
  String _comoSeLlama(String id) {
    for (final e
        in ref.read(emuladoresProvider).value?.emuladores ?? const []) {
      if (e.deviceId == id) return '${e.nombre} · $id';
    }
    for (final d in ref.read(dispositivosProvider).value ?? const []) {
      if (d.id == id) return '${d.nombre} · $id';
    }
    return id;
  }

  /// Lo que hay para correr: emuladores **arrancados** y teléfonos enchufados.
  ///
  /// Un emulador apagado no aparece a propósito: `flutter run -d` sobre algo que
  /// no está encendido falla, y ofrecerlo sería ofrecer ese fallo. Para
  /// arrancarlo está el icono de al lado.
  /// Y **si todavía se están buscando**, que es la mitad que faltaba.
  ///
  /// 🔴 Los dos estados iban aplanados a uno con un `?? const []`, así que
  /// «todavía no sé» y «no hay ninguno» se pintaban igual: un selector vacío que
  /// al pulsarlo no abre nada. Reportado mirando la pantalla —«parece que se
  /// quedó pegada la interfaz»— y no lo parecía: estaba buscando. Y como el
  /// botón de correr solo se enciende con un dispositivo elegido, el bloque
  /// entero se veía muerto.
  ///
  /// `adb devices` cuesta 14 ms medidos —está aquí al lado—, pero arrancar su
  /// daemon la primera vez, o un `devicectl` en frío, se van a segundos: justo
  /// el rato en que vas a correr la app.
  ///
  /// Se mira `isLoading` **junto con** `hasValue` a propósito: al refrescar ya
  /// hay una respuesta anterior que enseñar, y vaciarla para volver a llenarla
  /// sería parpadear por nada.
  ({bool buscando, List<String> ids}) _losDispositivos() {
    final emuladores = ref.watch(emuladoresProvider);
    final conectados = ref.watch(dispositivosProvider);

    return (
      buscando:
          (emuladores.isLoading && !emuladores.hasValue) ||
          (conectados.isLoading && !conectados.hasValue),
      ids: [
        for (final e in emuladores.value?.emuladores ?? const <Emulador>[])
          if (e.corriendo && e.deviceId != null) e.deviceId!,
        for (final d in conectados.value ?? const <DispositivoConectado>[])
          d.id,
      ],
    );
  }
}

/// Una app corriendo, con lo que se le puede pedir.
///
/// **La estructura viene de mirar la barra de La Oficina**, y no antes: se
/// implementó primero por lo que tenía que mostrar, se enseñó, y lo que faltaba
/// era exactamente lo que allí ya está resuelto. Dos cosas se traen de ahí:
///
/// - **El progreso tiene su propio sitio y no comparte línea con nada.** Metido
///   detrás del nombre del dispositivo se corta: «Medium Phone API 36.1 · R…»,
///   con la R de «Running Gradle task 'assembleCiDebug'…». Reportado tal cual:
///   «no veo dónde dice lo de corriendo».
/// - **El registro se abre desde aquí**, con un botón que se queda marcado. Se
///   recogía y no se enseñaba en ningún sitio, que es tenerlo y no tenerlo.
///
/// Lo que **no** se trae es el interruptor de recarga automática. Allí tiene
/// sentido; aquí quien guarda los archivos es Claude, a ráfagas de veinte
/// ediciones por encargo, y eso es un bucle de recompilaciones. Sigue siendo una
/// pregunta abierta y no una tarea.
class _FilaDeCorrida extends ConsumerWidget {
  const _FilaDeCorrida({required this.corrida});

  final Corrida corrida;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final controller = ref.read(corridasProvider.notifier);
    final ventanas = ref.watch(lasVentanasDelRegistroProvider);
    final registros = ref.read(lasVentanasDelRegistroProvider.notifier);
    bool abierta({required bool sistema}) => ventanas.contains(
      LasVentanasDelRegistro.nombreDe(corrida.deviceId, sistema: sistema),
    );

    final detalle = switch (corrida.estado) {
      EstadoDeCorrida.arrancando => corrida.progreso ?? strings.runCompiling,
      EstadoDeCorrida.corriendo => strings.runRunning,
      EstadoDeCorrida.parando => strings.runStopping,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.only(right: NexusSpacing.s3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: corrida.estado == EstadoDeCorrida.corriendo
                    ? colors.ok
                    : colors.warn,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    corrida.configuracion,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NexusTypography.data.copyWith(color: colors.ink),
                  ),
                  Text(
                    corrida.dispositivo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NexusTypography.mono.copyWith(color: colors.faint),
                  ),
                ],
              ),
            ),
            if (corrida.puedeRecargar) ...[
              _BotonMini(
                icono: Icons.refresh,
                titulo: strings.runReload,
                onPulsar: () => controller.recargar(deviceId: corrida.deviceId),
              ),
              _BotonMini(
                icono: Icons.restart_alt,
                titulo: strings.runRestart,
                onPulsar: () => controller.recargar(
                  deviceId: corrida.deviceId,
                  completa: true,
                ),
              ),
            ],
            _BotonMini(
              icono: Icons.article_outlined,
              titulo: strings.runLogs,
              activo: abierta(sistema: false),
              onPulsar: () => registros.alterna(corrida, sistema: false),
            ),
            // 🔴 **Aparte del registro de la corrida, y no dentro.** Aquél es lo
            // que imprime la app —y ya se reenvía por el daemon—; este es lo que
            // dice el sistema del teléfono: el crash nativo, el ANR, el `Fatal
            // signal 11`. Juntarlos parece ahorrar un botón y lo que hace es que
            // no se pueda mirar solo lo que hace falta.
            _BotonMini(
              icono: Icons.phonelink_ring_outlined,
              titulo: strings.runSystemLog,
              activo: abierta(sistema: true),
              onPulsar: () => registros.alterna(corrida, sistema: true),
            ),
            if (corrida.estado != EstadoDeCorrida.parando)
              _BotonMini(
                icono: Icons.stop_rounded,
                titulo: strings.runStop,
                onPulsar: () => controller.parar(corrida.deviceId),
              ),
          ],
        ),

        // **El progreso, en su propia línea y a todo lo ancho.** Es lo que cambia
        // cada pocos segundos mientras compila y lo único que dice que algo pasa;
        // compartir sitio con el nombre del dispositivo lo dejaba en una letra.
        Padding(
          padding: const EdgeInsets.only(left: 19, top: 2),
          child: Text(
            detalle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: NexusTypography.mono.copyWith(
              color: corrida.estado == EstadoDeCorrida.corriendo
                  ? colors.ok
                  : colors.warn,
            ),
          ),
        ),
      ],
    );
  }
}

/// Una acción sobre la corrida: icono con su nombre en el tooltip.
///
/// **Iconos y no palabras, y eso lo decidió una prueba**: «Recargar»,
/// «Reiniciar» y «Parar» en la misma fila desbordaban por 71 px, con el nombre
/// del entorno al lado.
///
/// Aquel «no hay ancho que alcance» era falso y conviene dejarlo escrito: el
/// panel medía **280** porque Material recorta ahí cualquier menú sin
/// `constraints`, no los 380 que yo creía. Con el ancho de verdad las palabras
/// caben. Se quedan los iconos porque son cuatro acciones —recargar, reiniciar,
/// registro, parar— y cuatro palabras en una fila con el nombre del entorno
/// convierten la fila en un párrafo; además es lo que hace la barra de la que se
/// copia esto.
///
/// El nombre no se pierde, se mueve al tooltip — y ahí sigue estando para quien
/// use un lector de pantalla, porque `IconButton` lo anuncia.
class _BotonMini extends StatelessWidget {
  const _BotonMini({
    required this.icono,
    required this.titulo,
    required this.onPulsar,
    this.activo = false,
  });

  final IconData icono;
  final String titulo;
  final VoidCallback onPulsar;

  /// Marcado. Lo usa el del registro: un botón que abre algo tiene que decir si
  /// está abierto, o se pulsa dos veces buscando lo que ya estaba.
  final bool activo;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPulsar,
    tooltip: titulo,
    iconSize: 15,
    splashRadius: 14,
    padding: const EdgeInsets.symmetric(horizontal: 4),
    constraints: const BoxConstraints(),
    visualDensity: VisualDensity.compact,
    color: activo ? context.colors.accent : context.colors.faint,
    icon: Icon(icono),
  );
}
