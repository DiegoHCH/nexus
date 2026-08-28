import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/e2e/data/datasources/repo_de_pruebas_data_source.dart';
import 'package:nexus/features/e2e/domain/entities/pasada_de_prueba.dart';
import 'package:nexus/features/e2e/presentation/providers/repo_de_pruebas_providers.dart';

/// Mandar una prueba escrita en Nexus al repo del equipo.
///
/// **Con confirmación y enseñando a dónde va.** Esto sale de tu máquina: crea una
/// rama en un repo compartido y abre un PR que alguien va a ver. Un botón que
/// hiciera eso de un toque sería la clase de acción que se lamenta, así que
/// primero se dice el repo, la ruta de destino, si reemplaza algo y qué va a
/// pasar exactamente.
///
/// 🔴 **Rama y PR, nunca un push a main.** No es una preferencia de estilo: el
/// repo es del equipo y el que escribe una prueba no es siempre el que sabe si
/// rompe otra.
class PublicarPruebaDialogo extends ConsumerStatefulWidget {
  const PublicarPruebaDialogo({super.key, required this.prueba});

  final Prueba prueba;

  static Future<void> abrir(BuildContext context, Prueba prueba) =>
      showDialog<void>(
        context: context,
        builder: (_) => PublicarPruebaDialogo(prueba: prueba),
      );

  @override
  ConsumerState<PublicarPruebaDialogo> createState() =>
      _PublicarPruebaDialogoState();
}

class _PublicarPruebaDialogoState extends ConsumerState<PublicarPruebaDialogo> {
  late final TextEditingController _mensaje;
  var _publicando = false;
  Publicacion? _resultado;

  /// A dónde va dentro del repo. Bajo `flows/`, que es donde vive todo lo que se
  /// lanza; las subcarpetas son de piezas y de `migration/`, y meter ahí una
  /// prueba nueva sin que nadie lo pida sería decidir por el equipo.
  String get _destino => 'flows/${widget.prueba.nombre}.yaml';

  @override
  void initState() {
    super.initState();
    _mensaje = TextEditingController(
      text: 'test(e2e): ${widget.prueba.nombre}',
    );
  }

  @override
  void dispose() {
    _mensaje.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strings = context.strings;
    final slug = ref.watch(slugDelRepoDePruebasProvider);
    final clon = ref.watch(clonDelRepoProvider).value?.clon;

    // El repo tiene que estar clonado: sin él no hay dónde escribir ni contra qué
    // comparar. Se dice, en vez de dejar un botón que falla al tocarlo.
    if (clon == null) {
      return AlertDialog(
        backgroundColor: colors.deep,
        content: Text(
          strings.e2ePublishNoRepo,
          style: NexusTypography.body.copyWith(color: colors.mute),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(strings.cancel),
          ),
        ],
      );
    }

    final resultado = _resultado;

    return AlertDialog(
      backgroundColor: colors.deep,
      title: Text(
        strings.e2ePublishTitle,
        style: NexusTypography.subtitle.copyWith(color: colors.ink),
      ),
      content: SizedBox(
        width: 460,
        child: resultado != null
            ? _Resultado(resultado: resultado)
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.e2ePublishWhere(slug, _destino),
                    style: NexusTypography.mono.copyWith(color: colors.ink),
                  ),
                  const SizedBox(height: NexusSpacing.s2),
                  // Reemplazar y crear no son lo mismo, y el nombre del archivo es
                  // lo único que los separa: se dice antes, no después.
                  FutureBuilder<String?>(
                    future: ref
                        .read(repoDePruebasDataSourceProvider)
                        .leer(clon: clon, ruta: _destino),
                    builder: (context, snap) => Text(
                      snap.connectionState != ConnectionState.done
                          ? ''
                          : snap.data == null
                          ? strings.e2ePublishNew
                          : strings.e2ePublishReplaces,
                      style: NexusTypography.body.copyWith(
                        color: snap.data == null ? colors.mute : colors.warn,
                      ),
                    ),
                  ),
                  const SizedBox(height: NexusSpacing.s3),
                  Text(
                    strings.e2ePublishHow,
                    style: NexusTypography.body.copyWith(color: colors.mute),
                  ),
                  const SizedBox(height: NexusSpacing.s4),
                  TextField(
                    controller: _mensaje,
                    style: NexusTypography.mono.copyWith(color: colors.ink),
                    decoration: InputDecoration(
                      labelText: strings.e2ePublishMessage,
                      labelStyle: NexusTypography.label.copyWith(
                        color: colors.faint,
                      ),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: colors.rule),
                      ),
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        if (resultado != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(strings.close),
          )
        else ...[
          TextButton(
            onPressed: _publicando ? null : () => Navigator.of(context).pop(),
            child: Text(strings.cancel),
          ),
          TextButton(
            onPressed: _publicando ? null : () => _publicar(clon),
            child: Text(
              _publicando ? strings.e2ePublishDoing : strings.e2ePublish,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _publicar(String clon) async {
    setState(() => _publicando = true);

    String contenido;
    try {
      contenido = await File(widget.prueba.ruta).readAsString();
    } on FileSystemException catch (e) {
      setState(() {
        _publicando = false;
        _resultado = Publicacion(ok: false, detalle: e.message);
      });
      return;
    }

    final resultado = await ref
        .read(repoDePruebasDataSourceProvider)
        .publicar(
          clon: clon,
          ruta: _destino,
          contenido: contenido,
          mensaje: _mensaje.text.trim().isEmpty
              ? 'test(e2e): ${widget.prueba.nombre}'
              : _mensaje.text.trim(),
        );

    if (!mounted) return;
    setState(() {
      _publicando = false;
      _resultado = resultado;
    });
    // El clon quedó en la rama base pero con un commit más en el remoto: se
    // vuelve a mirar para que la lista no se quede con la foto de antes.
    ref.invalidate(clonDelRepoProvider);
  }
}

class _Resultado extends ConsumerWidget {
  const _Resultado({required this.resultado});

  final Publicacion resultado;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          resultado.ok ? resultado.detalle : strings.e2ePublishFailed,
          style: NexusTypography.body.copyWith(
            color: resultado.ok ? colors.ok : colors.err,
          ),
        ),
        if (!resultado.ok && resultado.detalle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: NexusSpacing.s2),
            child: Text(
              resultado.detalle,
              style: NexusTypography.mono.copyWith(color: colors.mute),
            ),
          ),
        if (resultado.rama.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: NexusSpacing.s2),
            child: Text(
              resultado.rama,
              style: NexusTypography.mono.copyWith(color: colors.faint),
            ),
          ),
        // La URL entera y seleccionable: sin poder abrirla desde aquí, poder
        // copiarla es la diferencia entre tenerla y no.
        if (resultado.url.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: NexusSpacing.s2),
            child: SelectableText(
              resultado.url,
              style: NexusTypography.mono.copyWith(color: colors.accent),
            ),
          ),
      ],
    );
  }
}
