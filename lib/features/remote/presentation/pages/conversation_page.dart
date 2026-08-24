import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/nexus_colors.dart';
import 'package:nexus/features/remote/domain/remote_mirror.dart';
import 'package:nexus/features/remote/presentation/providers/mirror_providers.dart';
import 'package:nexus/features/remote/presentation/providers/outbox_providers.dart';
import 'package:nexus/features/remote/presentation/widgets/link_badge.dart';
import 'package:nexus/features/remote/presentation/widgets/write_phrase_sheet.dart';
import 'package:nexus/core/design_system/nexus_spacing.dart';
import 'package:nexus/core/design_system/nexus_typography.dart';
import 'package:nexus/features/remote/presentation/widgets/turn_block.dart';
import 'package:nexus/features/remote/presentation/widgets/mobile_chrome.dart';
import 'package:nexus/features/remote/presentation/widgets/mobile_state_page.dart';
import 'package:nexus/features/assistant/presentation/orb/nexus_orb.dart';

/// Una conversación: lo que está haciendo, lo que respondió, y el compositor.
class ConversationPage extends ConsumerStatefulWidget {
  const ConversationPage({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends ConsumerState<ConversationPage> {
  final _campo = TextEditingController();
  final _scroll = ScrollController();
  var _mandando = false;

  @override
  void initState() {
    super.initState();
    // El permiso se pregunta al abrir. No se hereda de otra conversación: la
    // carpeta de cada una concede lo suyo, así que un valor compartido diría que
    // puedes escribir en una donde no.
    Future.microtask(() async {
      final notifier = ref.read(mirrorProvider.notifier);
      await ref
          .read(writePermissionProvider.notifier)
          .consultar(widget.conversationId);
      // El historial se pide al abrir, no antes: la lista de conversaciones no lo
      // trae, y traerlo con la lista sería mandar por 4G el pasado de tres
      // conversaciones para leer el de una.
      await notifier.masHistorial(widget.conversationId);
    });
  }

  @override
  void dispose() {
    _campo.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _mandar() async {
    final texto = _campo.text.trim();
    if (texto.isEmpty) return;
    setState(() => _mandando = true);

    // Todo va por la cola, con red y sin ella. **El campo se vacía en cuanto se
    // encola**, no cuando el Mac contesta: lo que el usuario acaba de escribir ya
    // está guardado, y dejarlo en el campo invita a mandarlo otra vez.
    final cupo = await ref
        .read(mirrorProvider.notifier)
        .mandar(widget.conversationId, texto);

    if (!mounted) return;
    setState(() => _mandando = false);
    if (cupo) {
      _campo.clear();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Hay demasiados encargos esperando. Espera a que se manden.',
        ),
      ),
    );
  }

  /// Si no hay **nada** que leer todavía.
  ///
  /// Las tres cosas, no solo el historial: una conversación recién abierta desde el
  /// teléfono no tiene turnos pero puede estar ya contestando —el primer encargo va por
  /// `reply` antes de aterrizar en el historial—, y con solo mirar `history` el orbe
  /// grande se quedaría encima del texto que empieza a llegar.
  bool _vacia(MirroredConversation conv) =>
      conv.history.isEmpty && conv.reply.isEmpty && conv.steps.isEmpty;

  /// Ponerle nombre o cerrarla.
  ///
  /// En una hoja y no en un menú de Material: es el mismo lenguaje que la hoja de la
  /// frase de escritura, y un `PopupMenuButton` traería sus propias esquinas y su
  /// sombra a una pantalla que no tiene ninguna de las dos.
  ///
  /// El contenido es un widget aparte porque **el campo tiene que ser suyo**: creado y
  /// liberado aquí, se liberaba mientras la hoja seguía cerrándose —la animación aún lo
  /// usaba— y eso revienta con «un TextEditingController se usó después de liberarlo».
  Future<void> _acciones(
    MirroredConversation conv,
  ) => showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.colors.deep,
    shape: const RoundedRectangleBorder(),
    builder: (hoja) => _HojaDeAcciones(
      nombreDeAhora: conv.nombre,
      alGuardar: (nombre) async {
        Navigator.of(hoja).pop();
        await ref
            .read(mirrorProvider.notifier)
            .renombrar(widget.conversationId, nombre);
      },
      alCerrar: () async {
        Navigator.of(hoja).pop();
        final fallo = await ref
            .read(mirrorProvider.notifier)
            .cerrar(widget.conversationId);
        // Se sale **solo si se cerró**: quedarse en una pantalla que ya no refleja
        // nada es peor que no haber salido.
        if (fallo == null && mounted) Navigator.of(context).pop();
      },
    ),
  );
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final conv = ref.watch(conversationProvider(widget.conversationId));

    // Se cerró en el Mac mientras estaba abierta aquí. Pasa: el teléfono guarda ids
    // y el Mac vive su vida. Se dice y se sale, en vez de dejar una pantalla que ya
    // no refleja nada.
    if (conv == null) {
      // Un estado, con el molde de la pieza 7 —que estaba construido y sin estrenar—.
      // Antes era un texto gris centrado, que es justo lo que ese molde existe para no
      // volver a tener: decía qué pasó y no por qué ni qué hacer.
      return MobileStatePage(
        titulo: 'Esta conversación ya no está abierta',
        cuerpo:
            'El teléfono guarda los identificadores y el Mac sigue su vida: alguien '
            'la cerró allí mientras la tenías en pantalla.',
        pieDeAyuda: 'Lo que se dijo sigue en el archivo.',
        acciones: [
          WideAction(
            texto: 'Volver',
            principal: true,
            alTocar: () => Navigator.of(context).pop(),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: colors.void_,
      appBar: AppBar(
        backgroundColor: colors.void_,
        title: Text(
          conv.nombre.split('/').last,
          style: NexusTypography.lead.copyWith(color: colors.ink),
        ),
        actions: [
          // Las dos acciones sobre la conversación **detrás de un toque**, no a la
          // vista: cerrar al lado de la insignia de conexión es un botón destructivo
          // pegado a algo que se mira todo el rato.
          IconButton(
            key: const ValueKey('acciones-de-la-conversacion'),
            onPressed: () => _acciones(conv),
            // Tres puntos dibujados con el sistema, no `Icons.more_vert`: el idioma de
            // estas pantallas son hairlines y glifos.
            icon: Text(
              '···',
              style: NexusTypography.lead.copyWith(color: colors.mute),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(right: 16),
            child: LinkBadge(),
          ),
        ],
      ),
      // **El orbe va detrás, no dentro.** Es la otra mitad de esta pieza: puesto entre
      // el contenido sería una ilustración —una cosa más que mirar en una lista— y lo
      // que es es la presencia del asistente. Detrás y a media pantalla, cuenta en qué
      // anda el Mac sin robarle sitio a lo que se lee.
      //
      // `IgnorePointer` porque no se toca, y arriba porque es donde queda libre: los
      // turnos crecen hacia abajo y el compositor vive pegado al fondo.
      body: SafeArea(
        child: Column(
          children: [
            if (conv.percent != null) _Medidor(conversacion: conv),
            // **El orbe, fijo arriba: no se desplaza.** Estuvo de fondo y el texto se
            // le montaba encima; y como cabecera de la lista se iba de la pantalla al
            // leer. Aquí no hace ninguna de las dos: los mensajes se desplazan por
            // debajo de él y el orbe se queda, que es lo que corresponde a la
            // presencia del asistente — no es contenido, es quien te atiende.
            //
            // Vacía se lleva media pantalla, porque no hay nada que leer y es lo único
            // que hay que ver. Con turnos, una banda corta: lo justo para saber en qué
            // anda el Mac sin quitarle sitio a lo que se lee.
            SizedBox(
              height: _vacia(conv)
                  ? MediaQuery.of(context).size.height * 0.46
                  : 132,
              child: IgnorePointer(
                child: NexusOrb(
                  // Con la regla puesta: sin enlace no gira, diga lo que diga el
                  // último estado que llegó del Mac.
                  state: ref.watch(orbeProvider(widget.conversationId)),
                  showHorizon: false,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.all(20),
                children: [
                  // Más arriba lo más viejo: se lee hacia abajo, como una
                  // conversación.
                  if (conv.masHistorial != null)
                    Center(
                      child: TextButton(
                        key: const ValueKey('mas-historial'),
                        onPressed: () => ref
                            .read(mirrorProvider.notifier)
                            .masHistorial(widget.conversationId),
                        child: const Text('Ver lo anterior'),
                      ),
                    ),
                  for (final mensaje in conv.history)
                    _Mensaje(mensaje: mensaje),
                  if (conv.history.isNotEmpty) const SizedBox(height: 8),
                  if (conv.steps.isNotEmpty) _Pasos(pasos: conv.steps),
                  // La respuesta en curso, **y solo si no está ya abajo en el
                  // historial**: al terminar el turno el mismo texto salía por los
                  // dos sitios y con dos estilos distintos, que se lee como si el
                  // asistente hubiera contestado dos veces.
                  if (conv.reply.isNotEmpty && !conv.respuestaYaEnHistorial)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: TurnBlock(
                        key: const ValueKey('respuesta'),
                        mine: false,
                        text: conv.reply,
                      ),
                    ),
                  if (conv.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        conv.error!,
                        style: TextStyle(color: colors.err),
                      ),
                    ),
                  // Lo que está esperando salir. Se enseña **aquí y no en un cajón
                  // aparte**: un encargo escrito sin cobertura que no se ve por
                  // ninguna parte se da por perdido y se vuelve a escribir.
                  _Esperando(conversationId: widget.conversationId),
                ],
              ),
            ),
            _Compositor(
              campo: _campo,
              conversacion: conv,
              mandando: _mandando,
              alMandar: _mandar,
              alDetener: () => ref
                  .read(mirrorProvider.notifier)
                  .detener(widget.conversationId),
            ),
          ],
        ),
      ),
    );
  }
}

/// Un mensaje de lo dicho antes.
class _Mensaje extends StatelessWidget {
  const _Mensaje({required this.mensaje});

  final MirroredMessage mensaje;

  @override
  Widget build(BuildContext context) {
    // Lo tuyo no se interpreta como markdown, igual que en el escritorio: un
    // asterisco que escribiste tú se queda como asterisco. Eso lo hace `TurnBlock`.
    // **Un bloque y no una burbuja.** Lo que había eran `Container` redondeados
    // alineados a un lado y a otro —la convención de una app de mensajería— y esto no
    // lo es: el teléfono no ejecuta nada, refleja. `TurnBlock` ya dibuja la pila de
    // bloques con hairline y la etiqueta arriba, que es lo que dibuja el mockup, así
    // que aquí no se repite: se usa.
    return TurnBlock(mine: mensaje.mine, text: mensaje.text);
  }
}

/// Los encargos que todavía no salieron.
class _Esperando extends ConsumerWidget {
  const _Esperando({required this.conversationId});

  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final esperando = ref.watch(pendingForProvider(conversationId));
    if (esperando.isEmpty) return const SizedBox.shrink();
    final colors = context.colors;

    return Column(
      key: const ValueKey('esperando'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final encargo in esperando)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3, right: 10),
                  child: _Marca(color: colors.rule2),
                ),
                Expanded(
                  child: Text(
                    encargo.text,
                    // En mono y no en cursiva: la cursiva era la forma de decir «esto
                    // todavía no es real», y aquí eso ya lo dice la marca apagada.
                    style: NexusTypography.mono.copyWith(color: colors.mute),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// La marca de un paso: un punto de 7 px, y nada más.
///
/// Es lo que dibuja el mockup —`.act .mk::before`— y no un icono de Material. La
/// diferencia importa porque un icono trae su propio idioma: un ✓ de Material dice
/// «tarea completada en una lista de tareas», y un punto que cambia de color dice «esto
/// pasó, esto está pasando», que es lo que un registro cuenta.
///
/// Tres colores y un halo: `rule2` lo que no ha llegado, `ok` lo hecho, y el acento con
/// resplandor lo que está ocurriendo ahora — el único elemento que brilla, igual que el
/// orbe.
class _Marca extends StatelessWidget {
  const _Marca({required this.color, this.brilla = false});

  final Color color;
  final bool brilla;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 14,
    height: 14,
    child: Center(
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: brilla
              ? [BoxShadow(color: color.withValues(alpha: 0.8), blurRadius: 12)]
              : null,
        ),
      ),
    ),
  );
}

class _Medidor extends StatelessWidget {
  const _Medidor({required this.conversacion});

  final MirroredConversation conversacion;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final porcentaje = conversacion.percent!;
    // El color por tramos, igual que en el escritorio: un número solo no dice si
    // hay que preocuparse.
    final color = porcentaje >= 85
        ? colors.err
        : porcentaje >= 60
        ? colors.warn
        : colors.accent;

    // Dos cajas y no un `LinearProgressIndicator`: el de Material redondea las
    // puntas y anima al cambiar de valor, y una barra que se desliza sola parece que
    // está midiendo algo en vivo — esto es una cifra que llegó del Mac. Cuadrada y
    // quieta, como la del mockup.
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.s5,
        vertical: NexusSpacing.s2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 4,
              color: colors.rule,
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: (porcentaje / 100).clamp(0.0, 1.0),
                child: Container(color: color),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            // El porcentaje **como lo mandó el Mac**. Recalcularlo aquí con una
            // ventana asumida es el error que ya se cometió en el escritorio.
            '$porcentaje %',
            key: const ValueKey('medidor'),
            style: NexusTypography.label.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _Pasos extends StatelessWidget {
  const _Pasos({required this.pasos});

  final List<MirroredStep> pasos;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final paso in pasos)
          Container(
            // Hairline entre pasos, como los bloques de arriba: es el mismo sistema, y
            // una lista con separadores propios se leería como otra app.
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.rule)),
            ),
            padding: const EdgeInsets.symmetric(vertical: NexusSpacing.s3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: _Marca(
                    // El que escribe manda sobre lo demás: es la única forma que tiene
                    // el teléfono de decir que algo está tocando archivos, y eso
                    // importa más que si ya terminó.
                    color: paso.writes
                        ? colors.warn
                        : paso.done
                        ? colors.ok
                        : colors.accent,
                    brilla: !paso.done,
                  ),
                ),
                Expanded(
                  child: Text(
                    paso.text,
                    style: NexusTypography.mono.copyWith(
                      color: paso.writes
                          ? colors.warn
                          : paso.done
                          ? colors.faint
                          : colors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Compositor extends ConsumerWidget {
  const _Compositor({
    required this.campo,
    required this.conversacion,
    required this.mandando,
    required this.alMandar,
    required this.alDetener,
  });

  final TextEditingController campo;
  final MirroredConversation conversacion;
  final bool mandando;
  final VoidCallback alMandar;
  final VoidCallback alDetener;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final hasta = ref.watch(writePermissionProvider).value;
    final puedeEscribir = hasta != null && DateTime.now().isBefore(hasta);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: colors.deep,
        border: Border(top: BorderSide(color: colors.rule)),
      ),
      child: Column(
        children: [
          // El permiso se dice **antes de escribir el encargo**, no al mandarlo.
          // Enterarse de que era solo lectura después de teclear tres frases es
          // hacer trabajo para tirarlo.
          //
          // Y es el interruptor del mockup, no una línea con un candado: se ven **los
          // dos estados a la vez**, así que se lee en qué está sin recordar qué
          // significaba el icono. `PermissionToggle` ya lo dibuja —existía y esta
          // pantalla no lo usaba— y sabe que bajar a solo lectura no pide frase y
          // subir sí.
          Align(
            alignment: Alignment.centerLeft,
            child: PermissionToggle(
              key: const ValueKey('permiso'),
              puedeEditar: puedeEscribir,
              alTocar: () => mostrarFraseDeEscritura(context, ref),
            ),
          ),
          if (puedeEscribir) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                // La hora, que es lo que el interruptor no puede decir: «puede
                // editar» sin hasta cuándo invita a confiar en que sigue abierto.
                'hasta las ${_hora(hasta)}',
                style: NexusTypography.label.copyWith(color: colors.faint),
              ),
            ),
          ],
          const SizedBox(height: NexusSpacing.s3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  // La caja del mockup: `rise`, un hairline y radio 2 — y 44 de alto
                  // mínimo, que es la medida de algo que se toca con el pulgar.
                  constraints: const BoxConstraints(minHeight: 44),
                  decoration: BoxDecoration(
                    color: colors.rise,
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(color: colors.rule),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: NexusSpacing.s3,
                    vertical: 2,
                  ),
                  child: TextField(
                    key: const ValueKey('encargo'),
                    controller: campo,
                    minLines: 1,
                    maxLines: 4,
                    style: NexusTypography.body.copyWith(color: colors.ink),
                    decoration: InputDecoration(
                      hintText: 'Qué hay que hacer',
                      hintStyle: NexusTypography.body.copyWith(
                        color: colors.faint,
                      ),
                      // Sin las líneas de Material: la caja ya es el borde, y dos
                      // bordes dibujan un campo dentro de otro.
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: NexusSpacing.s2),
              // **El mismo sitio es mandar o detener**, nunca los dos: mandar otro
              // encima es lo que en el escritorio pone el segundo encargo en cola, y
              // en un teléfono eso se hace sin darse cuenta.
              //
              // Un cuadro con un glifo y no un `IconButton`: el botón de Material
              // trae su salpicadura circular y su área de 48, que en una fila de
              // hairlines se ve como una pieza prestada de otra app.
              if (conversacion.streaming)
                _Cuadro(
                  key: const ValueKey('detener'),
                  glifo: '■',
                  color: colors.err,
                  alTocar: alDetener,
                )
              else
                _Cuadro(
                  key: const ValueKey('mandar'),
                  glifo: '↑',
                  color: colors.accent,
                  alTocar: mandando ? null : alMandar,
                ),
            ],
          ),
          if (conversacion.streaming) ...[
            const SizedBox(height: NexusSpacing.s2),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                // El texto exacto del mockup. Dice la consecuencia y no la
                // prohibición: el botón ya no manda, así que esto explica por qué.
                'Mandar otro encima lo pondría en cola sin decirlo',
                style: NexusTypography.label.copyWith(color: colors.faint),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _hora(DateTime cuando) =>
      '${cuando.hour.toString().padLeft(2, '0')}:'
      '${cuando.minute.toString().padLeft(2, '0')}';
}

/// El botón del compositor: un cuadro con un glifo.
///
/// Cuadrado de 44 —lo mismo que el campo de al lado, así que la fila queda a una sola
/// altura— con un hairline del color de lo que hace y el glifo dentro. Apagado se ve
/// igual pero en `rule`: quitarlo movería el campo justo cuando se está escribiendo.
class _Cuadro extends StatelessWidget {
  const _Cuadro({
    super.key,
    required this.glifo,
    required this.color,
    required this.alTocar,
  });

  final String glifo;
  final Color color;
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final vivo = alTocar != null;

    return InkWell(
      onTap: alTocar,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: vivo ? color : colors.rule),
        ),
        child: Text(
          glifo,
          style: NexusTypography.body.copyWith(
            color: vivo ? color : colors.rule2,
          ),
        ),
      ),
    );
  }
}

/// Lo que hay dentro de la hoja de acciones.
class _HojaDeAcciones extends StatefulWidget {
  const _HojaDeAcciones({
    required this.nombreDeAhora,
    required this.alGuardar,
    required this.alCerrar,
  });

  final String nombreDeAhora;
  final Future<void> Function(String) alGuardar;
  final Future<void> Function() alCerrar;

  @override
  State<_HojaDeAcciones> createState() => _HojaDeAccionesState();
}

class _HojaDeAccionesState extends State<_HojaDeAcciones> {
  late final _campo = TextEditingController(text: widget.nombreDeAhora);

  @override
  void dispose() {
    _campo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(NexusSpacing.s5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MobileField(
              etiqueta: 'Nombre',
              controlador: _campo,
              // Se dice que se puede vaciar: es la forma de deshacer, y sin decirlo
              // nadie la encuentra.
              pista: 'vacío vuelve al primer encargo',
            ),
            const SizedBox(height: NexusSpacing.s4),
            WideAction(
              key: const ValueKey('guardar-nombre'),
              texto: 'Guardar el nombre',
              principal: true,
              alTocar: () => widget.alGuardar(_campo.text),
            ),
            const SizedBox(height: NexusSpacing.s5),
            Text(
              // Lo que hace falta saber **antes** de tocar: cerrar suena a borrar y no
              // lo es.
              'Cerrarla la quita del Mac. Lo dicho sigue en el archivo, y desde ahí '
              'se retoma.',
              style: NexusTypography.mono.copyWith(color: colors.faint),
            ),
            const SizedBox(height: NexusSpacing.s3),
            WideAction(
              key: const ValueKey('cerrar-la-conversacion'),
              texto: 'Cerrar la conversación',
              alTocar: widget.alCerrar,
            ),
          ],
        ),
      ),
    );
  }
}
