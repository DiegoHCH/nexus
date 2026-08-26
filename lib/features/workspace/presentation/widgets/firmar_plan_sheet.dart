import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/nexus_colors.dart';
import 'package:nexus/core/design_system/nexus_radius.dart';
import 'package:nexus/core/design_system/nexus_spacing.dart';
import 'package:nexus/core/design_system/nexus_typography.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/workspace/presentation/providers/plan_firmado_providers.dart';

/// Donde se firma el plan de una carpeta.
///
/// **Una frase, no un documento.** Lo que hace útil un plan aquí no es el detalle: es que
/// alguien haya tenido que escribir qué va a hacer antes de que se toque un archivo. Un
/// campo grande invita a redactar y a que nadie lo lea; uno de una línea invita a decidir.
///
/// Y explica que se puede negar, porque el gate es fricción deliberada y una fricción que
/// no se explica se lee como un fallo de la app.
class FirmarPlanSheet {
  static void open(
    BuildContext context,
    DondeMirar donde,
  ) => showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    // Sin esto la hoja se queda en 9/16 de la ventana y el contenido se sale por
    // abajo: son un párrafo, un campo y un botón, y en una ventana pequeña no caben.
    // Lo vio un test de widget antes que nadie, con 70 píxeles de desborde.
    isScrollControlled: true,
    builder: (_) => _Hoja(donde: donde),
  );
}

class _Hoja extends ConsumerStatefulWidget {
  const _Hoja({required this.donde});

  final DondeMirar donde;

  @override
  ConsumerState<_Hoja> createState() => _HojaState();
}

class _HojaState extends ConsumerState<_Hoja> {
  /// El controlador lo posee la hoja, no el `build`. Es el fallo que ya se cometió en el
  /// menú de acciones: uno creado al dibujar se usa después de morir.
  final _campo = TextEditingController();

  @override
  void initState() {
    super.initState();
    _precargar();
  }

  /// Trae el plan que hubiera: normalmente firmar otra vez es firmar lo mismo porque
  /// caducó, y obligar a reescribirlo invita a poner cualquier cosa.
  ///
  /// **Se espera al valor, no se lee y ya.** El plan vive en un archivo, así que el primer
  /// `read` puede llegar todavía cargando: leerlo sin esperar enseñaba el campo vacío
  /// teniendo plan en disco, y entonces la precarga no sirve justo cuando más hace falta
  /// —al abrir la app y ponerse a trabajar—.
  Future<void> _precargar() async {
    final plan = await ref.read(planFirmadoProvider(widget.donde).future);
    // Si ya estabas escribiendo, manda lo tuyo: llegar tarde no da derecho a pisarlo.
    if (!mounted || _campo.text.isNotEmpty) return;
    _campo.text = plan?.plan ?? '';
  }

  @override
  void dispose() {
    _campo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;

    return Container(
      decoration: BoxDecoration(
        color: colors.deep,
        border: Border(top: BorderSide(color: colors.rule)),
      ),
      // El teclado se suma abajo: el campo tiene el foco desde que abre, y sin esto
      // quedaría justo debajo de lo que acabas de levantar.
      padding: EdgeInsets.fromLTRB(
        NexusSpacing.s6,
        NexusSpacing.s5,
        NexusSpacing.s6,
        NexusSpacing.s6 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.planSignTitle,
            style: NexusTypography.lead.copyWith(color: colors.ink),
          ),
          // La rama, cuando la hay. Es lo que decide **dónde** va esta firma, así que
          // verla antes de escribir evita el caso feo: firmar creyendo que estás en la
          // rama de la tarea y descubrirlo por una denegación.
          if (widget.donde.rama case final rama? when rama.isNotEmpty) ...[
            const SizedBox(height: NexusSpacing.s2),
            Text(
              strings.planSignBranch(rama),
              style: NexusTypography.label.copyWith(color: colors.accent),
            ),
          ],
          const SizedBox(height: NexusSpacing.s3),
          Text(
            strings.planSignBody,
            style: NexusTypography.body.copyWith(color: colors.mute),
          ),
          const SizedBox(height: NexusSpacing.s5),
          TextField(
            controller: _campo,
            autofocus: true,
            style: NexusTypography.body.copyWith(color: colors.ink),
            decoration: InputDecoration(
              hintText: strings.planSignHint,
              hintStyle: NexusTypography.body.copyWith(color: colors.faint),
              filled: true,
              fillColor: colors.rise,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(NexusRadius.sm),
                borderSide: BorderSide(color: colors.rule),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(NexusRadius.sm),
                borderSide: BorderSide(color: colors.rule),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(NexusRadius.sm),
                borderSide: BorderSide(color: colors.accent),
              ),
            ),
            onSubmitted: (_) => _firmar(),
          ),
          const SizedBox(height: NexusSpacing.s5),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const ValueKey('firmar-el-plan'),
              onPressed: _firmar,
              child: Text(
                strings.planSignAction.toUpperCase(),
                style: NexusTypography.label.copyWith(color: colors.accent),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _firmar() async {
    final texto = _campo.text.trim();
    // Vacío no firma nada, y no se avisa con un error: el botón simplemente no cierra.
    // Firmar es decir qué vas a hacer, no rellenar un campo — y el hook lo rechazaría
    // igual, así que dejarlo pasar aquí sería prometer algo que se cae después.
    if (texto.isEmpty) return;

    // El navegador se captura antes del await: cerrar después de una operación asíncrona
    // con un `context` viejo es el fallo que ya rompió el menú de acciones.
    final navegador = Navigator.of(context);
    await ref.read(planFirmadoProvider(widget.donde).notifier).firmar(texto);
    if (navegador.canPop()) navegador.pop();
  }
}
