import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/design_system/selector_compacto.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/e2e/domain/entities/cuenta_de_pruebas.dart';
import 'package:nexus/features/e2e/domain/usecases/las_variables_del_proyecto.dart';
import 'package:nexus/features/e2e/presentation/providers/repo_de_pruebas_providers.dart';
import 'package:nexus/features/workspace/presentation/providers/workspace_providers.dart';

/// Las cuentas de **un** proyecto: verlas, añadirlas y editarlas.
///
/// **Vive en Ajustes y no en el sheet de pruebas.** Esto se toca una vez cada
/// mucho —una cuenta nueva, una contraseña que caducó— y el sheet de pruebas se
/// abre a diario: meter un formulario de credenciales en la pantalla que se usa
/// para lanzar le cobra a todos los días el precio de un día suelto.
///
/// 🔴 **Por proyecto, y eso no es un detalle de organización.** Una cuenta de
/// `front-mobile-b2c` no sirve para otro repo: son credenciales de una app
/// concreta, y ofrecerlas en otro sitio invita a correr una prueba con la cuenta
/// de otra cosa, que no da un error sino un rojo que parece una regresión.
class CuentasDeUnProyecto extends ConsumerWidget {
  const CuentasDeUnProyecto({super.key, required this.proyecto});

  final String proyecto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final cuentas = ref.watch(cuentasDePruebaProvider(proyecto));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, cuenta) in cuentas.indexed)
          _FilaDeCuenta(cuenta: cuenta, proyecto: proyecto, porDefecto: i == 0),
        TextButton(
          onPressed: () => editarCuenta(context, proyecto, null),
          child: Text(strings.e2eAccountAdd),
        ),
      ],
    );
  }
}

/// Abre el formulario de una cuenta. Fuera de las clases porque lo llaman tanto la
/// lista como cada fila.
Future<void> editarCuenta(
  BuildContext context,
  String proyecto,
  CuentaDePruebas? cuenta,
) => showDialog<void>(
  context: context,
  builder: (_) => _FormularioDeCuenta(proyecto: proyecto, cuenta: cuenta),
);

/// Una cuenta en la lista.
///
/// 🔴 **Enseña los nombres de las variables y su cantidad, nunca los valores.** Es
/// la misma regla de `LasVariablesDelProyecto`: para saber que una cuenta está
/// completa basta con los nombres, y un listado es justo el sitio donde una
/// contraseña se queda a la vista de quien pasa por detrás.
class _FilaDeCuenta extends ConsumerWidget {
  const _FilaDeCuenta({
    required this.cuenta,
    required this.proyecto,
    required this.porDefecto,
  });

  final CuentaDePruebas cuenta;
  final String proyecto;
  final bool porDefecto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;

    return Padding(
      padding: const EdgeInsets.only(bottom: NexusSpacing.s3),
      child: InkWell(
        onTap: () => editarCuenta(context, proyecto, cuenta),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: NexusSpacing.s2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    cuenta.clave,
                    style: NexusTypography.data.copyWith(color: colors.ink),
                  ),
                  if (porDefecto) ...[
                    const SizedBox(width: NexusSpacing.s2),
                    Text(
                      strings.e2eAccountDefault,
                      style: NexusTypography.label.copyWith(
                        color: colors.accent,
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    // Cuántas hay cargadas, que es lo que dice si se puede correr.
                    '${cuenta.variables.length}',
                    style: NexusTypography.label.copyWith(color: colors.faint),
                  ),
                ],
              ),
              if (cuenta.descripcion.isNotEmpty)
                Text(
                  cuenta.descripcion,
                  style: NexusTypography.body.copyWith(color: colors.mute),
                ),
              Text(
                (cuenta.tags.toList()..sort())
                    .map((t) => 'acct-$t')
                    .join(' · '),
                style: NexusTypography.label.copyWith(color: colors.faint),
              ),
              if (!porDefecto)
                TextButton(
                  onPressed: () => ref
                      .read(cuentasDePruebaProvider(proyecto).notifier)
                      .hacerPorDefecto(cuenta.clave),
                  child: Text(strings.e2eAccountMakeDefault),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El formulario de una cuenta.
///
/// **Aquí sí se ven los valores, y es la excepción deliberada.** La regla de no
/// escribirlos en ningún sitio nuestro habla de registros, mensajes de error y
/// páginas: sitios que quedan. Un campo que abriste tú para corregir un PIN mal
/// tecleado no es eso, y esconderlos haría imposible lo único que este formulario
/// existe para hacer.
class _FormularioDeCuenta extends ConsumerStatefulWidget {
  const _FormularioDeCuenta({required this.proyecto, required this.cuenta});

  final String proyecto;
  final CuentaDePruebas? cuenta;

  @override
  ConsumerState<_FormularioDeCuenta> createState() =>
      _FormularioDeCuentaState();
}

class _FormularioDeCuentaState extends ConsumerState<_FormularioDeCuenta> {
  /// A qué proyecto va. **Se elige aquí y no antes**: la pregunta «¿de qué
  /// proyecto es esta cuenta?» es parte de crearla, y sacarla fuera obligaba a
  /// una lista de botones —uno por proyecto— que crecía con el workspace y no
  /// decía qué iba a pasar al pulsarlos.
  late String _proyecto;

  late final TextEditingController _clave;
  late final TextEditingController _tags;
  late final TextEditingController _descripcion;
  late final TextEditingController _variables;

  @override
  void initState() {
    super.initState();
    final c = widget.cuenta;
    _proyecto = widget.proyecto;
    _clave = TextEditingController(text: c?.clave ?? '');
    _tags = TextEditingController(
      text: c == null ? '' : (c.tags.toList()..sort()).join(', '),
    );
    _descripcion = TextEditingController(text: c?.descripcion ?? '');
    _variables = TextEditingController(
      text: c == null
          ? ''
          : (c.variables.entries.toList()
                  ..sort((a, b) => a.key.compareTo(b.key)))
                .map((e) => '${e.key}=${e.value}')
                .join('\n'),
    );
  }

  @override
  void dispose() {
    _clave.dispose();
    _tags.dispose();
    _descripcion.dispose();
    _variables.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;
    final esNueva = widget.cuenta == null;
    final proyectos = [
      for (final c in ref.watch(workspaceControllerProvider).folders)
        c.workingDirectory,
    ];

    return AlertDialog(
      backgroundColor: colors.deep,
      title: Text(
        esNueva ? strings.e2eAccountAdd : widget.cuenta!.clave,
        style: NexusTypography.subtitle.copyWith(color: colors.ink),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Solo al crear: mover una cuenta de proyecto no es editarla, es
              // otra cosa —y hacerlo desde aquí la dejaría duplicada o perdida
              // según cómo se guarde—.
              if (esNueva && proyectos.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: NexusSpacing.s3),
                  child: SelectorCompacto(
                    key: const ValueKey('para-que-proyecto'),
                    valor: _proyecto,
                    opciones: proyectos,
                    pista: strings.e2eWhichProject,
                    etiqueta: (ruta) => ruta.split('/').last,
                    onElegir: (ruta) => setState(() => _proyecto = ruta),
                  ),
                )
              else if (esNueva)
                Padding(
                  padding: const EdgeInsets.only(bottom: NexusSpacing.s3),
                  child: Text(
                    // Con uno solo es un rótulo: un selector de una opción pide
                    // una decisión que no existe.
                    _proyecto.split('/').last,
                    style: NexusTypography.label.copyWith(color: colors.faint),
                  ),
                ),
              _campo(
                controlador: _clave,
                etiqueta: strings.e2eAccountKey,
                pista: strings.e2eAccountKeyHint,
                // La clave es la identidad de la cuenta: cambiarla al editar
                // crearía una segunda en vez de mover la que hay.
                habilitado: esNueva,
              ),
              _campo(
                controlador: _tags,
                etiqueta: strings.e2eAccountTags,
                pista: strings.e2eAccountTagsHint,
              ),
              _campo(
                controlador: _descripcion,
                etiqueta: strings.e2eAccountDesc,
                pista: strings.e2eAccountDescHint,
              ),
              _campo(
                controlador: _variables,
                etiqueta: strings.e2eAccountVars,
                pista: strings.e2eAccountVarsHint,
                lineas: 6,
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (!esNueva)
          TextButton(
            onPressed: () {
              ref
                  .read(cuentasDePruebaProvider(_proyecto).notifier)
                  .borrar(widget.cuenta!.clave);
              Navigator.of(context).pop();
            },
            child: Text(
              strings.e2eAccountDelete,
              style: TextStyle(color: colors.err),
            ),
          ),
        TextButton(onPressed: _guardar, child: Text(strings.e2eAccountSave)),
      ],
    );
  }

  void _guardar() {
    final clave = _clave.text.trim();
    // Sin clave no hay cuenta: guardar una anónima la haría invisible en la lista
    // y no la elegiría ningún flow.
    if (clave.isEmpty) return;

    final tags = <String>{
      for (final t in _tags.text.split(','))
        // El prefijo se quita si alguien lo escribe: la etiqueta del flow es
        // `acct-pe` y es fácil copiarla entera desde el YAML.
        if (t.trim().isNotEmpty)
          t.trim().startsWith('acct-') ? t.trim().substring(5) : t.trim(),
    };

    ref
        .read(cuentasDePruebaProvider(_proyecto).notifier)
        .guardar(
          CuentaDePruebas(
            clave: clave,
            tags: tags,
            descripcion: _descripcion.text.trim(),
            // Se reusa el lector del `.env.local`: es el mismo formato y ya
            // decide qué hacer con una línea que no se entiende.
            variables: LasVariablesDelProyecto.leer(_variables.text),
          ),
        );
    Navigator.of(context).pop();
  }

  Widget _campo({
    required TextEditingController controlador,
    required String etiqueta,
    required String pista,
    bool habilitado = true,
    int lineas = 1,
  }) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: NexusSpacing.s3),
      child: TextField(
        controller: controlador,
        enabled: habilitado,
        maxLines: lineas,
        style: NexusTypography.data.copyWith(color: colors.ink),
        decoration: InputDecoration(
          labelText: etiqueta,
          // 🔴 `helperText` y no `hintText`. El hint de Material solo se enseña
          // con el campo enfocado, así que la pista aparecía justo después de
          // que hiciera falta: quien abre el formulario ve cuatro cajas mudas y
          // tiene que adivinar el formato. Medido en la primera vez que alguien
          // lo usó — preguntó qué escribir teniendo las pistas escritas.
          helperText: pista.isEmpty ? null : pista,
          helperMaxLines: 2,
          labelStyle: NexusTypography.label.copyWith(color: colors.faint),
          helperStyle: NexusTypography.label.copyWith(color: colors.faint),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: colors.rule),
          ),
        ),
      ),
    );
  }
}
