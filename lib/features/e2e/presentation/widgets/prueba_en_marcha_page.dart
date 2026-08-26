import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexus/core/design_system/design_system.dart';
import 'package:nexus/core/i18n/strings_scope.dart';
import 'package:nexus/features/e2e/domain/usecases/pasos_de_una_prueba.dart';
import 'package:nexus/features/e2e/presentation/providers/e2e_providers.dart';

/// La prueba que corre, en su propia vista.
///
/// **Aparte y no dentro de la hoja de pruebas**, que es donde estaba: una prueba
/// se mira mientras avanza —medio minuto, ocho pasos que van cambiando— y meterla
/// encima de la lista obligaba a compartir sitio con lo que no cambia. Es el mismo
/// reparto que tienen los documentos: la lista en su hoja, y lo que se está
/// mirando en su propia ventana.
class PruebaEnMarchaPage extends ConsumerWidget {
  const PruebaEnMarchaPage({super.key});

  /// Se abre encima de lo que haya. Se llama al lanzar y desde la hoja.
  static Future<void> abrir(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const PruebaEnMarchaPage()),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final strings = context.strings;
    final prueba = ref.watch(pruebaEnMarchaProvider);

    return Scaffold(
      backgroundColor: colors.void_,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(NexusSpacing.s5),
          child: prueba == null
              ? Center(
                  child: Text(
                    strings.e2eNoRuns,
                    style: NexusTypography.mono.copyWith(color: colors.faint),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.arrow_back, size: 16),
                          color: colors.faint,
                          splashRadius: 15,
                        ),
                        Expanded(
                          child: Text(
                            prueba.flow,
                            style: NexusTypography.data.copyWith(
                              color: colors.ink,
                            ),
                          ),
                        ),
                        Text(
                          '${prueba.terminados}/${prueba.pasos.length}',
                          style: NexusTypography.mono.copyWith(
                            color: colors.faint,
                          ),
                        ),
                        const SizedBox(width: NexusSpacing.s3),
                        if (prueba.viva)
                          OutlinedButton(
                            onPressed: ref
                                .read(pruebaEnMarchaProvider.notifier)
                                .parar,
                            child: Text(strings.e2eStop),
                          )
                        else
                          Icon(
                            prueba.fallo ? Icons.close : Icons.check,
                            size: 16,
                            color: prueba.fallo ? colors.err : colors.ok,
                          ),
                      ],
                    ),
                    const SizedBox(height: NexusSpacing.s4),

                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Los pasos del YAML con su símbolo, o la salida en
                            // plano cuando lo ejecutado no cuadra con el archivo
                            // —`runFlow`, un bucle—: degradarse y no mentir.
                            if (prueba.estados case final estados?)
                              for (final (i, paso) in prueba.pasos.indexed)
                                _Paso(texto: paso, estado: estados[i])
                            else
                              SelectableText(
                                prueba.lineas.join('\n'),
                                style: NexusTypography.mono.copyWith(
                                  color: colors.faint,
                                ),
                              ),

                            // La salida entera debajo, siempre. Cuando un paso
                            // falla, el motivo está aquí y en ningún otro sitio.
                            if (prueba.estados != null &&
                                prueba.lineas.isNotEmpty) ...[
                              const SizedBox(height: NexusSpacing.s5),
                              Text(
                                strings.runLogs,
                                style: NexusTypography.label.copyWith(
                                  color: colors.faint,
                                ),
                              ),
                              const SizedBox(height: NexusSpacing.s2),
                              SelectableText(
                                prueba.lineas.join('\n'),
                                style: NexusTypography.mono.copyWith(
                                  color: colors.faint,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _Paso extends StatelessWidget {
  const _Paso({required this.texto, required this.estado});

  final String texto;
  final EstadoDePaso estado;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (icono, color) = switch (estado) {
      EstadoDePaso.hecho => (Icons.check, colors.ok),
      EstadoDePaso.enCurso => (Icons.autorenew, colors.accent),
      EstadoDePaso.fallado => (Icons.close, colors.err),
      EstadoDePaso.pendiente => (Icons.remove, colors.rule),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icono, size: 13, color: color),
          const SizedBox(width: NexusSpacing.s3),
          Expanded(
            child: Text(
              texto,
              style: NexusTypography.mono.copyWith(
                color: estado == EstadoDePaso.pendiente
                    ? colors.faint
                    : colors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
