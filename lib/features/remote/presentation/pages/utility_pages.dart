import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/nexus_colors.dart';
import 'package:nexus/core/design_system/nexus_spacing.dart';
import 'package:nexus/core/design_system/nexus_typography.dart';
import 'package:nexus/features/remote/presentation/pages/conversation_page.dart';
import 'package:nexus/features/remote/presentation/providers/utility_providers.dart';
import 'package:nexus/features/remote/presentation/widgets/mobile_chrome.dart';

/// El molde de las tres pantallas del menú.
///
/// **Sin orbe.** El orbe es la presencia del asistente, y estas no son el asistente
/// haciendo algo: son un archivo, unos documentos y un selector. Ponerle uno lo
/// convertiría en decoración.
///
/// Y las tres tienen la misma forma porque hacen lo mismo: pedir una lista, enseñarla,
/// y dejar elegir. Un molde común es lo que hace que la tercera no se parezca a otra
/// app — es lo que faltó la primera vez que se escribieron estas pantallas.
class _ListaDeUtilidad extends StatelessWidget {
  const _ListaDeUtilidad({
    required this.rotulo,
    required this.cuerpo,
    required this.pie,
    this.alRefrescar,
    this.arriba,
  });

  final String rotulo;
  final Widget cuerpo;

  /// La nota de abajo. **Obligatoria**: en las tres hay algo que conviene saber antes
  /// de tocar —qué pasa al retomar, qué pesa un artifact, por qué una carpeta está
  /// ocupada— y dejarlo a la intuición es lo que hace que la gente toque y se
  /// arrepienta.
  final String pie;

  final Future<void> Function()? alRefrescar;

  /// Lo que va **entre el rótulo y la lista**: hoy, los botones de cuenta. Va en el
  /// molde y no en cada pantalla para que estén a la misma altura en las dos: el
  /// archivo y las carpetas se recorren seguidas, y un filtro que salta de sitio se
  /// vuelve a buscar cada vez.
  final Widget? arriba;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final columna = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: NexusSpacing.s6),
        Text(
          rotulo.toUpperCase(),
          style: NexusTypography.label.copyWith(color: colors.mute),
        ),
        const SizedBox(height: NexusSpacing.s4),
        if (arriba case final fila?) ...[
          fila,
          const SizedBox(height: NexusSpacing.s4),
        ],
        cuerpo,
        const SizedBox(height: NexusSpacing.s6),
        Text(pie, style: NexusTypography.mono.copyWith(color: colors.faint)),
        const SizedBox(height: NexusSpacing.s6),
      ],
    );

    return Scaffold(
      backgroundColor: colors.void_,
      appBar: AppBar(
        backgroundColor: colors.void_,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        // La cabecera de siempre, sin hamburguesa: desde aquí se vuelve, no se abre
        // otro menú.
        title: const MobileChrome(),
        titleSpacing: NexusSpacing.s3,
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.s5),
          child: alRefrescar == null
              ? SingleChildScrollView(child: columna)
              : RefreshIndicator(
                  onRefresh: alRefrescar!,
                  color: colors.accent,
                  backgroundColor: colors.deep,
                  child: SingleChildScrollView(
                    // Siempre desplazable, o el tirón para refrescar no funciona
                    // cuando la lista es corta — que es justo cuando más se tira.
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: columna,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Una fila de las tres listas: título, un dato debajo, y un chip opcional.
/// Los cubos que hay **en lo que se está enseñando**: «general» y uno por cuenta.
///
/// `null` es general —lo que no es de ningún perfil— y va primero. No hay un botón de
/// «todas»: mezclar cuentas en una sola lista es justo lo que obliga a leer treinta y
/// seis nombres para dar con el de esta mañana, y quien trabaja con dos mundos los
/// mira por separado.
///
/// Salen de los propios datos y no de una lista fija: un botón para un cubo vacío
/// ofrece un sitio donde mirar en el que no hay nada.
List<String?> _cubos(Iterable<String?>? valores) {
  final todos = (valores ?? const <String?>[]).toList();
  return [
    if (todos.any((c) => c == null)) null,
    ...todos.nonNulls.toSet().toList()..sort(),
  ];
}

/// Lo del cubo elegido, y nada más. `null` trae lo que no tiene cuenta.
List<T> _soloDe<T>(
  List<T> todo,
  String? cuenta,
  String? Function(T) cuentaDe,
) => [
  for (final e in todo)
    if (cuentaDe(e) == cuenta) e,
];

/// El cubo preferido al abrir, cuando existe.
///
/// Es una preferencia, no una regla del dominio: se abre en el mundo en el que se
/// trabaja casi siempre, y de ahí un nombre concreto en el código. Cambiarlo es
/// cambiar esta constante; el resto no sabe nada de ella.
const _cuboPreferido = 'work';

/// Qué cubo sale elegido al abrir.
///
/// [_cuboPreferido] si está entre los que hay; si no, el del primero de la lista, que
/// al venir ordenada de lo más reciente a lo más antiguo es el mundo en el que se
/// estaba trabajando. Empezar siempre en «general» abriría el archivo en el cubo casi
/// vacío y obligaría a un toque antes de ver nada.
String? _cuboDePartida<T>(
  List<T>? datos,
  String? Function(T) cuentaDe,
  List<String?> cubos,
) {
  if (cubos.contains(_cuboPreferido)) return _cuboPreferido;
  return (datos == null || datos.isEmpty) ? null : cuentaDe(datos.first);
}

/// Los botones de cuenta, arriba de la lista.
///
/// **Solo existen si hay más de una.** Con una sola cuenta configurada, dividir en
/// botones dibuja una elección que no existe y encima miente sobre que hubiera otra
/// parte donde mirar. Es la misma regla que las pestañas del escritorio, por el mismo
/// motivo.
///
/// Y hay un «todas» porque la lista viene ordenada por fecha: lo último que hiciste
/// suele ser lo que buscas, y saber de qué cuenta era es a menudo lo que se quiere
/// **descubrir**, no lo que se sabe de antemano.
class _CuentasArriba extends StatelessWidget {
  const _CuentasArriba({
    required this.cubos,
    required this.elegida,
    required this.alElegir,
  });

  /// `null` entre ellos es «general».
  final List<String?> cubos;

  final String? elegida;
  final ValueChanged<String?> alElegir;

  @override
  Widget build(BuildContext context) {
    // Con un solo cubo no hay elección que hacer, y un botón único solo ocupa sitio.
    if (cubos.length < 2) return const SizedBox.shrink();

    return Wrap(
      spacing: NexusSpacing.s2,
      runSpacing: NexusSpacing.s2,
      children: [
        for (final cubo in cubos)
          _Boton(
            key: ValueKey('cuenta-${cubo ?? 'general'}'),
            rotulo: cubo ?? 'General',
            activo: elegida == cubo,
            alTocar: () => alElegir(cubo),
          ),
      ],
    );
  }
}

class _Boton extends StatelessWidget {
  const _Boton({
    super.key,
    required this.rotulo,
    required this.activo,
    required this.alTocar,
  });

  final String rotulo;
  final bool activo;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return InkWell(
      onTap: alTocar,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: NexusSpacing.s3,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          // El activo se marca con el acento en el borde y en la letra, no con un
          // relleno: un botón macizo aquí pesa más que la propia lista.
          border: Border.all(color: activo ? colors.accent : colors.rule),
        ),
        child: Text(
          rotulo.toUpperCase(),
          style: NexusTypography.label.copyWith(
            color: activo ? colors.accent : colors.mute,
          ),
        ),
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({
    super.key,
    required this.titulo,
    required this.dato,
    this.chip,
    this.chipVivo = false,
    this.alTocar,
    this.apagada = false,
  });

  final String titulo;
  final String dato;
  final String? chip;
  final bool chipVivo;
  final VoidCallback? alTocar;

  /// Se ve pero no se toca. **Se enseña igual**: esconder lo que no se puede elegir
  /// deja a quien mira preguntándose si falta algo.
  final bool apagada;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return InkWell(
      onTap: apagada ? null : alTocar,
      child: Container(
        width: double.infinity,
        // s3 y no s4: en una lista de teléfono, 16 px arriba y abajo por fila
        // convierten cuatro elementos en una pantalla entera. Con 12 caben seis sin
        // que se toquen.
        padding: const EdgeInsets.symmetric(vertical: NexusSpacing.s3),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.rule)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: NexusTypography.lead.copyWith(
                      color: apagada ? colors.mute : colors.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    dato,
                    style: NexusTypography.data.copyWith(color: colors.faint),
                  ),
                ],
              ),
            ),
            if (chip != null) ...[
              const SizedBox(width: NexusSpacing.s3),
              StateChip(texto: chip!, vivo: chipVivo),
            ],
          ],
        ),
      ),
    );
  }
}

/// El archivo: retomar una conversación de antes.
class ArchivePage extends ConsumerStatefulWidget {
  const ArchivePage({super.key});

  @override
  ConsumerState<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends ConsumerState<ArchivePage> {
  /// `null` es «todas». La elección **no se guarda**: al volver a entrar se ve todo,
  /// que es lo que se quiere el 90 % de las veces. Un filtro que sobrevive es un
  /// filtro que se olvida, y entonces «no aparece» se lee como «no está».
  String? _cuenta;

  /// Si ya se eligió a mano. Hace falta un flag aparte porque `null` **es un cubo de
  /// verdad** —«general»— y por tanto no puede significar también «sin elegir».
  bool _elegido = false;

  @override
  Widget build(BuildContext context) {
    final archivo = ref.watch(archiveProvider);
    final cubos = _cubos(archivo.value?.map((c) => c.account));
    final cuenta = _elegido
        ? _cuenta
        : _cuboDePartida(archivo.value, (e) => e.account, cubos);

    return _ListaDeUtilidad(
      rotulo: 'El archivo',
      alRefrescar: () => ref.refresh(archiveProvider.future),
      arriba: _CuentasArriba(
        cubos: cubos,
        elegida: cuenta,
        alElegir: (cubo) => setState(() {
          _cuenta = cubo;
          _elegido = true;
        }),
      ),
      pie:
          'Retomar una que ya está abierta lleva a la que hay: dos conversaciones '
          'sobre la misma carpeta compartirían la sesión de Claude y se pisarían el '
          'contexto.',
      cuerpo: switch (archivo) {
        AsyncData(:final value) when value.isEmpty => const _Vacia(
          texto: 'Todavía no hay nada guardado.',
        ),
        AsyncData(:final value)
            when _soloDe(value, cuenta, (c) => c.account).isEmpty =>
          _Vacia(texto: 'Nada de «${cuenta ?? 'general'}» en el archivo.'),
        AsyncData(:final value) => Column(
          children: [
            for (final c in _soloDe(value, cuenta, (e) => e.account))
              _Fila(
                key: ValueKey('archivada-${c.id}'),
                titulo: c.title,
                // La cuenta primero cuando la hay: en un archivo con veintitrés
                // de `private` y siete de `work`, la carpeta sola no distingue —dos
                // cuentas pueden trabajar sobre el mismo repo—. El escritorio lo
                // resuelve con pestanas; aqui, sin sitio para pestanas, va en la
                // propia fila.
                dato: [
                  ?c.account,
                  _cola(c.folder),
                  '${c.turns} turnos',
                ].join('  ·  '),
                // Se dice cuál está viva para no ofrecer «retomar» algo que ya lo
                // está — y se deja tocar igual, porque llevar a la abierta es
                // exactamente lo correcto.
                chip: c.open ? 'Abierta' : null,
                chipVivo: c.open,
                alTocar: () async {
                  final id = await ref
                      .read(archiveProvider.notifier)
                      .retomar(c.id);
                  if (id == null || !context.mounted) return;
                  await Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(
                      builder: (_) => ConversationPage(conversationId: id),
                    ),
                  );
                },
              ),
          ],
        ),
        AsyncError() => const _Vacia(
          texto: 'No pude pedirle el archivo al Mac.',
        ),
        _ => const _Cargando(),
      },
    );
  }
}

/// Los artifacts: lo que produjo Claude.
class ArtifactsPage extends ConsumerStatefulWidget {
  const ArtifactsPage({super.key});

  @override
  ConsumerState<ArtifactsPage> createState() => _ArtifactsPageState();
}

class _ArtifactsPageState extends ConsumerState<ArtifactsPage> {
  String? _cuenta;

  /// Si ya se eligió a mano. Hace falta un flag aparte porque `null` **es un cubo de
  /// verdad** —«general»— y por tanto no puede significar también «sin elegir».
  bool _elegido = false;

  @override
  Widget build(BuildContext context) {
    final lista = ref.watch(artifactsListProvider);
    final cubos = _cubos(lista.value?.map((a) => a.account));
    final cuenta = _elegido
        ? _cuenta
        : _cuboDePartida(lista.value, (e) => e.account, cubos);

    return _ListaDeUtilidad(
      rotulo: 'Los artifacts',
      alRefrescar: () => ref.refresh(artifactsListProvider.future),
      arriba: _CuentasArriba(
        cubos: cubos,
        elegida: cuenta,
        alElegir: (cubo) => setState(() {
          _cuenta = cubo;
          _elegido = true;
        }),
      ),
      pie:
          'El peso va delante porque abrir uno grande con datos móviles es una '
          'decisión, no un toque: la lista se pide siempre y el contenido casi nunca.',
      cuerpo: switch (lista) {
        AsyncData(:final value) when value.isEmpty => const _Vacia(
          texto: 'Claude no ha producido documentos todavía.',
        ),
        AsyncData(:final value)
            when _soloDe(value, cuenta, (a) => a.account).isEmpty =>
          _Vacia(texto: 'Ningún documento de «${cuenta ?? 'general'}».'),
        AsyncData(:final value) => Column(
          children: [
            for (final a in _soloDe(value, cuenta, (e) => e.account))
              _Fila(
                key: ValueKey('artifact-${a.id}'),
                titulo: a.name,
                dato: [?a.account, _peso(a.bytes)].join('  ·  '),
                // Lo que no es texto se dice **en la lista**: un `.png` por un canal
                // de texto no da una imagen, da un error, y una fila que solo puede
                // fallar es peor que una fila que avisa.
                chip: a.text ? null : 'Solo en la Mac',
                apagada: !a.text,
                alTocar: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ArtifactPage(id: a.id, nombre: a.name),
                  ),
                ),
              ),
          ],
        ),
        AsyncError() => const _Vacia(
          texto: 'No pude pedirle los documentos al Mac.',
        ),
        _ => const _Cargando(),
      },
    );
  }
}

/// El contenido de un artifact.
class ArtifactPage extends ConsumerWidget {
  const ArtifactPage({super.key, required this.id, required this.nombre});

  final String id;
  final String nombre;

  /// Si hay que pintarlo en vez de leerlo en crudo.
  ///
  /// Por la extensión del nombre y no por mirar el contenido: un documento que empieza
  /// con `<!doctype` casi seguro es HTML, pero uno que no empieza así también puede
  /// serlo, y adivinar acabaría enseñando etiquetas a veces. La extensión es lo que el
  /// Mac ya usa para decidir qué es un documento.
  bool get _sePinta {
    final punto = nombre.lastIndexOf('.');
    if (punto == -1) return false;
    const html = {'.html', '.htm'};
    return html.contains(nombre.substring(punto).toLowerCase());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final contenido = ref.watch(artifactProvider(id));

    return _ListaDeUtilidad(
      rotulo: nombre,
      pie: _sePinta
          ? 'Se pinta dentro de la app: un mockup se mira, no se lee.'
          : 'Se pidió al abrirlo, no con la lista.',
      cuerpo: switch (contenido) {
        AsyncData(:final value) when _sePinta => _Pintado(
          html: value,
          key: const ValueKey('artifact-pintado'),
        ),
        AsyncData(:final value) => SelectableText(
          value,
          key: const ValueKey('contenido-del-artifact'),
          // En mono: son documentos que Claude escribió, casi siempre markdown, y
          // leerlos en proporcional pierde la alineación que tienen dentro.
          style: NexusTypography.mono.copyWith(color: colors.ink, height: 1.6),
        ),
        AsyncError() => const _Vacia(texto: 'No pude leerlo.'),
        _ => const _Cargando(),
      },
    );
  }
}

/// Un documento HTML, pintado **dentro de la app**.
///
/// No se abre en el navegador del sistema, y es el punto: salir de la app para ver un
/// mockup que la propia app acaba de traer por su canal rompe la vuelta —se pierde el
/// sitio en la lista— y encima el navegador no tiene el documento: lo tiene esto.
///
/// El HTML llega por el canal como una cadena porque **un HTML es texto**: no hay
/// fichero que servir ni URL que autorizar, así que el visor no abre ninguna puerta
/// nueva. Sin navegación: lo que se pinta es lo que llegó, y un enlace que saliera a
/// la red convertiría un visor de documentos en un navegador.
class _Pintado extends StatefulWidget {
  const _Pintado({super.key, required this.html});

  final String html;

  @override
  State<_Pintado> createState() => _PintadoState();
}

class _PintadoState extends State<_Pintado> {
  late final WebViewController _control;

  @override
  void initState() {
    super.initState();
    _control = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // Transparente detrás: un mockup con fondo oscuro sobre el blanco de por
      // defecto se ve con un marco blanco alrededor.
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          // Solo se carga lo que se le dio. Un `about:blank` o el propio contenido
          // pasan; cualquier navegación a la red se bloquea, que es lo que separa un
          // visor de un navegador metido con calzador.
          onNavigationRequest: (peticion) =>
              peticion.url.startsWith('http') && peticion.isMainFrame
              ? NavigationDecision.prevent
              : NavigationDecision.navigate,
        ),
      )
      ..loadHtmlString(widget.html);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    // Alto fijo y no `Expanded`: esto vive dentro de un `SingleChildScrollView`, y un
    // `Expanded` ahí es la contradicción que ya rompió tres pantallas. El alto es casi
    // toda la ventana, que es lo que un mockup necesita para leerse.
    height: MediaQuery.of(context).size.height * 0.72,
    child: WebViewWidget(controller: _control),
  );
}

/// Elegir carpeta para una conversación nueva.
class FoldersPage extends ConsumerStatefulWidget {
  const FoldersPage({super.key});

  @override
  ConsumerState<FoldersPage> createState() => _FoldersPageState();
}

class _FoldersPageState extends ConsumerState<FoldersPage> {
  String? _cuenta;

  /// Si ya se eligió a mano. Hace falta un flag aparte porque `null` **es un cubo de
  /// verdad** —«general»— y por tanto no puede significar también «sin elegir».
  bool _elegido = false;

  @override
  Widget build(BuildContext context) {
    final carpetas = ref.watch(foldersProvider);
    final cubos = _cubos(carpetas.value?.map((f) => f.account));
    final cuenta = _elegido
        ? _cuenta
        : _cuboDePartida(carpetas.value, (e) => e.account, cubos);

    return _ListaDeUtilidad(
      rotulo: 'Conversación nueva',
      alRefrescar: () => ref.refresh(foldersProvider.future),
      arriba: _CuentasArriba(
        cubos: cubos,
        elegida: cuenta,
        alElegir: (cubo) => setState(() {
          _cuenta = cubo;
          _elegido = true;
        }),
      ),
      pie:
          'Solo las que el Mac ya tiene emparejadas: la lista la pone él. Emparejar '
          'una carpeta nueva sigue siendo cosa del escritorio.',
      cuerpo: switch (carpetas) {
        AsyncData(:final value) when value.isEmpty => const _Vacia(
          texto: 'El Mac no tiene ninguna carpeta emparejada.',
        ),
        AsyncData(:final value)
            when _soloDe(value, cuenta, (f) => f.account).isEmpty =>
          _Vacia(texto: 'Ninguna carpeta de «${cuenta ?? 'general'}».'),
        AsyncData(:final value) => Column(
          children: [
            for (final f in _soloDe(value, cuenta, (e) => e.account))
              _Fila(
                key: ValueKey('carpeta-${f.path}'),
                titulo: _cola(f.path),
                // La cuenta delante de la ruta: abrir aquí **elige cuenta**, y hasta
                // ahora se elegía sin verlo.
                dato: [?f.account, f.path].join('  ·  '),
                // Las dos cosas se dicen **antes** de abrir: empezar en una de solo
                // lectura y descubrirlo al primer encargo es trabajo para tirar, y
                // una ocupada no se puede abrir dos veces.
                chip: f.busy ? 'Ocupada' : (f.canWrite ? null : 'Solo lectura'),
                apagada: f.busy,
                alTocar: () async {
                  final id = await ref
                      .read(foldersProvider.notifier)
                      .abrir(f.path);
                  if (id == null || !context.mounted) return;
                  await Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(
                      builder: (_) => ConversationPage(conversationId: id),
                    ),
                  );
                },
              ),
          ],
        ),
        AsyncError() => const _Vacia(
          texto: 'No pude pedirle las carpetas al Mac.',
        ),
        _ => const _Cargando(),
      },
    );
  }
}

/// Vacío o error, con la misma forma.
///
/// **Ni un spinner centrado ni una disculpa**: dice qué hay y se calla. Y vacío y
/// error se ven distintos porque son cosas distintas — uno es «no hay nada» y el otro
/// «no pude preguntar».
class _Vacia extends StatelessWidget {
  const _Vacia({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: NexusSpacing.s6),
    child: Text(
      texto,
      key: const ValueKey('lista-vacia'),
      style: NexusTypography.body.copyWith(color: context.colors.mute),
    ),
  );
}

class _Cargando extends StatelessWidget {
  const _Cargando();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: NexusSpacing.s6),
    child: Text(
      'Preguntando al Mac…',
      style: NexusTypography.mono.copyWith(color: context.colors.faint),
    ),
  );
}

/// Los dos últimos tramos de una ruta: en una pantalla estrecha, el principio es lo
/// que todas tienen en común y el final lo que las distingue.
String _cola(String ruta) {
  final tramos = ruta.split('/').where((t) => t.isNotEmpty).toList();
  if (tramos.length <= 2) return ruta;
  return '…/${tramos.sublist(tramos.length - 2).join('/')}';
}

String _peso(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
