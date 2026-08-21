import 'package:flutter/material.dart';
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
/// Las cuentas que hay **en lo que se está enseñando**, ordenadas.
///
/// De los propios datos y no de una lista fija: si el Mac tiene dos perfiles pero
/// todo lo guardado es de uno, dibujar dos botones ofrece un sitio vacío donde mirar.
List<String> _cuentasDe(Iterable<String?>? valores) =>
    (valores ?? const <String?>[]).nonNulls.toSet().toList()..sort();

/// Lo de una cuenta, o todo si no hay ninguna elegida.
List<T> _soloDe<T>(
  List<T> todo,
  String? cuenta,
  String? Function(T) cuentaDe,
) => cuenta == null
    ? todo
    : [
        for (final e in todo)
          if (cuentaDe(e) == cuenta) e,
      ];

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
    required this.cuentas,
    required this.elegida,
    required this.alElegir,
  });

  final List<String> cuentas;

  /// `null` es «todas», y es lo de partida.
  final String? elegida;
  final ValueChanged<String?> alElegir;

  @override
  Widget build(BuildContext context) {
    if (cuentas.length < 2) return const SizedBox.shrink();

    return Wrap(
      spacing: NexusSpacing.s2,
      runSpacing: NexusSpacing.s2,
      children: [
        _Boton(
          rotulo: 'Todas',
          activo: elegida == null,
          alTocar: () => alElegir(null),
        ),
        for (final cuenta in cuentas)
          _Boton(
            key: ValueKey('cuenta-$cuenta'),
            rotulo: cuenta,
            activo: elegida == cuenta,
            alTocar: () => alElegir(cuenta),
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

  @override
  Widget build(BuildContext context) {
    final archivo = ref.watch(archiveProvider);
    final cuentas = _cuentasDe(archivo.value?.map((c) => c.account));

    return _ListaDeUtilidad(
      rotulo: 'El archivo',
      alRefrescar: () => ref.refresh(archiveProvider.future),
      arriba: _CuentasArriba(
        cuentas: cuentas,
        elegida: _cuenta,
        alElegir: (cuenta) => setState(() => _cuenta = cuenta),
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
            when _soloDe(value, _cuenta, (c) => c.account).isEmpty =>
          _Vacia(texto: 'Nada de «$_cuenta» en el archivo.'),
        AsyncData(:final value) => Column(
          children: [
            for (final c in _soloDe(value, _cuenta, (e) => e.account))
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

  @override
  Widget build(BuildContext context) {
    final lista = ref.watch(artifactsListProvider);
    final cuentas = _cuentasDe(lista.value?.map((a) => a.account));

    return _ListaDeUtilidad(
      rotulo: 'Los artifacts',
      alRefrescar: () => ref.refresh(artifactsListProvider.future),
      arriba: _CuentasArriba(
        cuentas: cuentas,
        elegida: _cuenta,
        alElegir: (cuenta) => setState(() => _cuenta = cuenta),
      ),
      pie:
          'El peso va delante porque abrir uno grande con datos móviles es una '
          'decisión, no un toque: la lista se pide siempre y el contenido casi nunca.',
      cuerpo: switch (lista) {
        AsyncData(:final value) when value.isEmpty => const _Vacia(
          texto: 'Claude no ha producido documentos todavía.',
        ),
        AsyncData(:final value)
            when _soloDe(value, _cuenta, (a) => a.account).isEmpty =>
          _Vacia(texto: 'Ningún documento de «$_cuenta».'),
        AsyncData(:final value) => Column(
          children: [
            for (final a in _soloDe(value, _cuenta, (e) => e.account))
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final contenido = ref.watch(artifactProvider(id));

    return _ListaDeUtilidad(
      rotulo: nombre,
      pie: 'Se pidió al abrirlo, no con la lista.',
      cuerpo: switch (contenido) {
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

/// Elegir carpeta para una conversación nueva.
class FoldersPage extends ConsumerStatefulWidget {
  const FoldersPage({super.key});

  @override
  ConsumerState<FoldersPage> createState() => _FoldersPageState();
}

class _FoldersPageState extends ConsumerState<FoldersPage> {
  String? _cuenta;

  @override
  Widget build(BuildContext context) {
    final carpetas = ref.watch(foldersProvider);
    final cuentas = _cuentasDe(carpetas.value?.map((f) => f.account));

    return _ListaDeUtilidad(
      rotulo: 'Conversación nueva',
      alRefrescar: () => ref.refresh(foldersProvider.future),
      arriba: _CuentasArriba(
        cuentas: cuentas,
        elegida: _cuenta,
        alElegir: (cuenta) => setState(() => _cuenta = cuenta),
      ),
      pie:
          'Solo las que el Mac ya tiene emparejadas: la lista la pone él. Emparejar '
          'una carpeta nueva sigue siendo cosa del escritorio.',
      cuerpo: switch (carpetas) {
        AsyncData(:final value) when value.isEmpty => const _Vacia(
          texto: 'El Mac no tiene ninguna carpeta emparejada.',
        ),
        AsyncData(:final value)
            when _soloDe(value, _cuenta, (f) => f.account).isEmpty =>
          _Vacia(texto: 'Ninguna carpeta de «$_cuenta».'),
        AsyncData(:final value) => Column(
          children: [
            for (final f in _soloDe(value, _cuenta, (e) => e.account))
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
