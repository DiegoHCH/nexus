import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/e2e/domain/entities/cuenta_de_pruebas.dart';
import 'package:nexus/features/e2e/domain/usecases/las_variables_del_proyecto.dart';
import 'package:nexus/features/e2e/presentation/providers/repo_de_pruebas_providers.dart';

/// Las cuentas con las que corren las pruebas: verlas, añadirlas y editarlas.
///
/// **Un sheet aparte y no un trozo del de pruebas.** Esto se toca una vez cada
/// mucho —cuando entra una cuenta nueva o caduca una contraseña— y el de pruebas
/// se abre a diario. Meter un formulario de credenciales en la pantalla que se usa
/// para lanzar es cobrarle a todos los días el precio de un día suelto.
class CuentasDePruebaSheet extends ConsumerWidget {
  const CuentasDePruebaSheet({super.key});

  static Future<void> open(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const CuentasDePruebaSheet(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final cuentas = ref.watch(cuentasDePruebaProvider);

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
            strings.e2eAccountsTitle,
            style: NexusTypography.label.copyWith(color: colors.faint),
          ),
          const SizedBox(height: NexusSpacing.s2),
          Text(
            strings.e2eAccountsWhere,
            style: NexusTypography.body.copyWith(color: colors.mute),
          ),
          const SizedBox(height: NexusSpacing.s4),

          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (cuentas.isEmpty)
                    Text(
                      strings.e2eAccountsNone,
                      style: NexusTypography.body.copyWith(color: colors.mute),
                    )
                  else
                    for (final (i, cuenta) in cuentas.indexed)
                      _FilaDeCuenta(cuenta: cuenta, porDefecto: i == 0),
                  const SizedBox(height: NexusSpacing.s4),
                  TextButton(
                    onPressed: () => _editar(context, ref, null),
                    child: Text(strings.e2eAccountAdd),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> _editar(
    BuildContext context,
    WidgetRef ref,
    CuentaDePruebas? cuenta,
  ) => showDialog<void>(
    context: context,
    builder: (_) => _FormularioDeCuenta(cuenta: cuenta),
  );
}

/// Una cuenta en la lista.
///
/// 🔴 **Enseña los nombres de las variables y su cantidad, nunca los valores.** Es
/// la misma regla de `LasVariablesDelProyecto`: para saber que una cuenta está
/// completa basta con los nombres, y un listado es justo el sitio donde una
/// contraseña se queda a la vista de quien pasa por detrás.
class _FilaDeCuenta extends ConsumerWidget {
  const _FilaDeCuenta({required this.cuenta, required this.porDefecto});

  final CuentaDePruebas cuenta;
  final bool porDefecto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;

    return Padding(
      padding: const EdgeInsets.only(bottom: NexusSpacing.s3),
      child: InkWell(
        onTap: () => CuentasDePruebaSheet._editar(context, ref, cuenta),
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
                      style: NexusTypography.label.copyWith(color: colors.accent),
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
                (cuenta.tags.toList()..sort()).map((t) => 'acct-$t').join(' · '),
                style: NexusTypography.label.copyWith(color: colors.faint),
              ),
              if (!porDefecto)
                TextButton(
                  onPressed: () => ref
                      .read(cuentasDePruebaProvider.notifier)
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
  const _FormularioDeCuenta({required this.cuenta});

  final CuentaDePruebas? cuenta;

  @override
  ConsumerState<_FormularioDeCuenta> createState() => _FormularioDeCuentaState();
}

class _FormularioDeCuentaState extends ConsumerState<_FormularioDeCuenta> {
  late final TextEditingController _clave;
  late final TextEditingController _tags;
  late final TextEditingController _descripcion;
  late final TextEditingController _variables;

  @override
  void initState() {
    super.initState();
    final c = widget.cuenta;
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
                pista: '',
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
                  .read(cuentasDePruebaProvider.notifier)
                  .borrar(widget.cuenta!.clave);
              Navigator.of(context).pop();
            },
            child: Text(
              strings.e2eAccountDelete,
              style: TextStyle(color: colors.err),
            ),
          ),
        TextButton(
          onPressed: _guardar,
          child: Text(strings.e2eAccountSave),
        ),
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

    ref.read(cuentasDePruebaProvider.notifier).guardar(
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
          hintText: pista.isEmpty ? null : pista,
          labelStyle: NexusTypography.label.copyWith(color: colors.faint),
          hintStyle: NexusTypography.body.copyWith(color: colors.faint),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: colors.rule),
          ),
        ),
      ),
    );
  }
}
