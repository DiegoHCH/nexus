import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/run/domain/entities/corrida.dart';
import 'package:nexus/features/run/presentation/providers/corridas_providers.dart';
import 'package:nexus/features/run/presentation/providers/donde_flota_la_botonera.dart';
import 'package:nexus/features/run/domain/usecases/la_consola_de_la_app.dart';
import 'package:nexus/features/run/presentation/providers/la_consola_que_se_abre.dart';
import 'package:nexus/features/run/presentation/providers/la_ventana_del_registro.dart';
import 'package:nexus/features/run/presentation/providers/run_providers.dart';

/// Lo que se le puede pedir a la app que está corriendo, **flotando encima**.
///
/// 🔴 **Los botones vivían dentro del panel de correr**, y el panel es un menú:
/// para recargar había que abrirlo, apuntar a la fila y pulsar, con la lista de
/// entornos y dispositivos delante — tres pasos y una pantalla entera para lo
/// que en cualquier depurador es un botón siempre visible. Y el panel se cierra
/// solo al pulsar fuera, así que gobernar una corrida obligaba a reabrirlo cada
/// vez.
///
/// **Flota, no bloquea.** Es un `Positioned` dentro del mismo `Stack` del HUD,
/// no un diálogo: mientras está delante se puede escribir, hablar y seguir
/// trabajando. Es el mismo criterio que la tarjeta de una versión nueva —una
/// noticia, no una pregunta— y el que ya llevó los registros a su ventana.
///
/// **Se arrastra por su asa y el sitio se recuerda**; ver
/// [DondeFlotaLaBotonera]. Solo por el asa y no por toda la barra: si se
/// arrastra desde cualquier parte, el primer clic torcido sobre «parar» mueve
/// la barra en vez de parar, y lo que se busca es lo contrario.
///
/// De los ocho iconos de la referencia solo hay cuatro **porque solo hay cuatro
/// con plomería**: el daemon expone `app.restart` —con `fullRestart` para el
/// reinicio— y `app.stop`, y nada más. Pausa, pasos e inspector piden hablar
/// con la VM service, que es su propia tarea; poner el icono antes que la
/// tubería sería enseñar un botón que no hace nada.
class LaBotoneraDeCorridas extends ConsumerStatefulWidget {
  const LaBotoneraDeCorridas({super.key});

  /// Ancho fijo y no el del contenido: con el ancho al gusto, la barra cambia
  /// de tamaño al cambiar el texto del progreso —«Running Gradle task…»— y se
  /// mueve sola debajo del ratón.
  static const ancho = 380.0;

  /// La barra en sí, para poder medir **dónde acabó** y no solo el cristal que
  /// la sostiene: lo que hay que comprobar es que caiga dentro de su caja, que
  /// es justo lo que se salía.
  static const laLlave = ValueKey('la-botonera-de-corridas');

  /// Cuánto tiene que quedar dentro de la ventana. Sin esto, arrastrarla al
  /// borde la deja irrecuperable: no hay asa que agarrar para traerla de vuelta.
  static const margen = 120.0;

  /// A qué altura del suelo nace.
  static const alDelSuelo = NexusSpacing.s5;

  /// Donde nace cuando nadie la ha movido: abajo a la derecha, lejos del orbe y
  /// del muelle, que son los otros dos dueños de esta capa.
  ///
  /// 🔴 **La medida es la del HUD, no la de la ventana.** El `Stack` donde
  /// cuelga vive dentro de un `Column`, entre la barra de arriba y el
  /// compositor, así que es bastante más bajo que la ventana — y un `Stack`
  /// recorta lo que se sale. Calculando el sitio con el alto de la ventana, la
  /// botonera caía **fuera** del recorte y no se veía nada: reportado dos veces
  /// mirando la pantalla, «la botonera no apareció».
  ///
  /// 🔴 **Y el sitio se cuenta desde abajo**, no desde arriba. Su alto depende
  /// de cuántas corridas haya —una fila cada una— así que con la posición
  /// contada desde arriba una segunda corrida la asoma por el borde de abajo y
  /// el `Stack` se la come. Anclada al suelo crece hacia arriba, que además es
  /// lo que hace cualquier barra de estado.
  static Offset dondeNace(Size caja) =>
      Offset(caja.width - ancho - NexusSpacing.s6, alDelSuelo);

  /// La deja siempre agarrable, aunque la ventana se haya hecho más pequeña
  /// desde la última vez. `dy` se cuenta **desde el suelo**; ver [dondeNace].
  static Offset dentroDe(Size caja, Offset donde) => Offset(
    donde.dx.clamp(-ancho + margen, caja.width - margen),
    donde.dy.clamp(0, (caja.height - 48).clamp(0, double.infinity)),
  );

  @override
  ConsumerState<LaBotoneraDeCorridas> createState() =>
      _LaBotoneraDeCorridasState();
}

class _LaBotoneraDeCorridasState extends ConsumerState<LaBotoneraDeCorridas> {
  /// Dónde va mientras se arrastra.
  ///
  /// Aparte de lo guardado a propósito: escribir en disco en cada
  /// `onPanUpdate` son cien escrituras por arrastre. Se guarda al soltar.
  Offset? _arrastrando;

  /// 🔴 **Se acumula sobre lo que hay en el estado, no sobre lo que se pintó.**
  /// Un arrastre son muchos avisos seguidos y **no siempre hay un fotograma
  /// entre ellos**: sumando siempre a la posición del último `build`, dos avisos
  /// juntos se pisan y la barra vuelve donde estaba. Lo pescó la prueba del
  /// arrastre, que mueve y suelta sin pintar en medio — y es exactamente lo que
  /// pasa con un tirón rápido.
  /// El eje vertical va al revés que el ratón: `dy` se cuenta desde el suelo,
  /// así que bajar la mano es restar. Ver [LaBotoneraDeCorridas.dondeNace].
  void _mueve(Offset delta, Offset desde) => setState(
    () => _arrastrando = (_arrastrando ?? desde) + Offset(delta.dx, -delta.dy),
  );

  void _suelta(Size caja, Offset desde) {
    final donde = LaBotoneraDeCorridas.dentroDe(caja, _arrastrando ?? desde);
    ref.read(dondeFlotaLaBotoneraProvider.notifier).mover(donde);
    setState(() => _arrastrando = null);
  }

  @override
  Widget build(BuildContext context) {
    final corridas = ref.watch(corridasProvider).values.toList();
    // 🔴 **Vacía es un `Positioned`, no un `SizedBox`.** Este widget cuelga
    // directamente del `Stack` del HUD, y ahí un hijo **sin posicionar** lo
    // estira el `fit` del Stack hasta ocupar la pantalla entera: sin nada
    // corriendo, la botonera invisible se comía las pulsaciones del orbe. Lo
    // pescó la prueba del orbe sin conversaciones, que dejó de crear ninguna.
    if (corridas.isEmpty) {
      return const Positioned(width: 0, height: 0, child: SizedBox.shrink());
    }

    final colors = context.colors;

    // **Se mide la caja del HUD y no la ventana**, que es lo que hacía falta
    // para que no cayera fuera del recorte del `Stack`. Ver [dondeNace].
    //
    // `Positioned.fill` con un `Stack` dentro y no un `LayoutBuilder` a secas:
    // un `Stack` no se queda las pulsaciones donde no tiene hijos, así que el
    // orbe y el muelle siguen respondiendo por debajo de este cristal.
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, caja) {
          final donde = LaBotoneraDeCorridas.dentroDe(
            caja.biggest,
            _arrastrando ??
                ref.watch(dondeFlotaLaBotoneraProvider) ??
                LaBotoneraDeCorridas.dondeNace(caja.biggest),
          );

          return Stack(
            children: [
              Positioned(
                left: donde.dx,
                bottom: donde.dy,
                child: _laBarra(context, colors, caja.biggest, donde),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _laBarra(
    BuildContext context,
    NexusColors colors,
    Size caja,
    Offset donde,
  ) {
    final corridas = ref.watch(corridasProvider).values.toList();

    return Material(
      key: LaBotoneraDeCorridas.laLlave,
      color: Colors.transparent,
      child: Container(
        width: LaBotoneraDeCorridas.ancho,
        decoration: BoxDecoration(
          color: colors.deep,
          border: Border.all(color: colors.rule),
          borderRadius: BorderRadius.circular(NexusRadius.md),
          boxShadow: [
            // Despegada del fondo: es lo único que dice que está encima y no
            // dentro de la pantalla.
            BoxShadow(
              color: colors.void_.withValues(alpha: 0.5),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ElAsa(
              onArrastrar: (delta) => _mueve(delta, donde),
              onSoltar: () => _suelta(caja, donde),
            ),
            for (final corrida in corridas) _Corrida(corrida: corrida),
          ],
        ),
      ),
    );
  }
}

/// El asa, con lo que vale para todas las corridas a la vez.
class _ElAsa extends ConsumerWidget {
  const _ElAsa({required this.onArrastrar, required this.onSoltar});

  final void Function(Offset delta) onArrastrar;
  final VoidCallback onSoltar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;

    return Row(
      children: [
        Expanded(
          child: MouseRegion(
            cursor: SystemMouseCursors.grab,
            child: GestureDetector(
              onPanUpdate: (detalle) => onArrastrar(detalle.delta),
              onPanEnd: (_) => onSoltar(),
              // Sin esto el asa solo agarra donde hay tinta, que son cuatro
              // puntos de un icono de 14 px.
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: NexusSpacing.s3,
                  vertical: NexusSpacing.s2,
                ),
                child: Row(
                  children: [
                    Icon(Icons.drag_indicator, size: 14, color: colors.faint),
                    const SizedBox(width: NexusSpacing.s2),
                    Text(
                      strings.runToolbarDrag,
                      style: NexusTypography.label.copyWith(
                        color: colors.faint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // **Apagado de fábrica.** Recargar la app sin que nadie lo pida es una
        // sorpresa la primera vez, y aquí no se enciende por defecto lo que
        // reinicia algo. Y va en el asa y no en cada fila: es una preferencia de
        // quien mira, no una propiedad de una corrida.
        Padding(
          padding: const EdgeInsets.only(right: NexusSpacing.s2),
          child: BotonMini(
            icono: Icons.bolt,
            titulo: strings.runAuto,
            activo: ref.watch(autoRecargaProvider),
            onPulsar: () => ref.read(autoRecargaProvider.notifier).cambiar(),
          ),
        ),
      ],
    );
  }
}

/// Una corrida: qué es, qué está haciendo y qué se le puede pedir.
///
/// Una fila por corrida y no una barra que apunte a la elegida: el código ya
/// contempla varias a la vez, y con una sola barra el botón de parar es una
/// ruleta salvo que se añada un selector — que es más interfaz para decidir
/// algo que la fila ya dice sola.
class _Corrida extends ConsumerWidget {
  const _Corrida({required this.corrida});

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

    return Container(
      padding: const EdgeInsets.fromLTRB(
        NexusSpacing.s3,
        NexusSpacing.s2,
        NexusSpacing.s2,
        NexusSpacing.s2,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.rule)),
      ),
      child: Row(
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
                  corrida.dispositivo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NexusTypography.data.copyWith(color: colors.ink),
                ),
                // **El progreso en su propia línea.** Detrás del nombre se
                // corta —«Medium Phone API 36.1 · R…», con la R de «Running
                // Gradle task 'assembleCiDebug'…»— y es lo único que dice que
                // algo está pasando mientras compila.
                Text(
                  detalle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NexusTypography.mono.copyWith(
                    color: corrida.estado == EstadoDeCorrida.corriendo
                        ? colors.ok
                        : colors.warn,
                  ),
                ),
              ],
            ),
          ),
          if (corrida.puedeRecargar) ...[
            BotonMini(
              icono: Icons.refresh,
              titulo: strings.runReload,
              onPulsar: () => controller.recargar(deviceId: corrida.deviceId),
            ),
            // En verde, como en la referencia: reiniciar es lo que se pulsa
            // cuando la recarga no bastó, y distinguirlo de un vistazo evita
            // pulsar el de al lado.
            BotonMini(
              icono: Icons.restart_alt,
              titulo: strings.runRestart,
              color: colors.ok,
              onPulsar: () => controller.recargar(
                deviceId: corrida.deviceId,
                completa: true,
              ),
            ),
          ],
          // Solo si esta corrida declaró consola: la mayoría no la traen, y un
          // botón que no lleva a ninguna parte enseña a no pulsarlo. La ventana
          // se abre sola al arrancar —ver [LaConsolaQueSeAbre]—, así que esto es
          // para volver a ella cuando se cerró.
          if (corrida.consola case final puerto?)
            BotonMini(
              icono: Icons.dashboard_customize_outlined,
              titulo: strings.runConsole,
              onPulsar: () => ref.read(abreLaConsolaProvider)(
                url: LaConsolaDeLaApp.urlDe(puerto),
                titulo: '${corrida.configuracion} · ${corrida.dispositivo}',
              ),
            ),
          BotonMini(
            icono: Icons.article_outlined,
            titulo: strings.runLogs,
            activo: abierta(sistema: false),
            onPulsar: () => registros.alterna(corrida, sistema: false),
          ),
          // 🔴 **Aparte del registro de la corrida, y no dentro.** Aquél es lo
          // que imprime la app; este es lo que dice el sistema del teléfono: el
          // crash nativo, el ANR, el `Fatal signal 11`.
          BotonMini(
            icono: Icons.phonelink_ring_outlined,
            titulo: strings.runSystemLog,
            activo: abierta(sistema: true),
            onPulsar: () => registros.alterna(corrida, sistema: true),
          ),
          if (corrida.estado != EstadoDeCorrida.parando)
            BotonMini(
              icono: Icons.stop_rounded,
              titulo: strings.runStop,
              color: colors.err,
              onPulsar: () => controller.parar(corrida.deviceId),
            ),
        ],
      ),
    );
  }
}
